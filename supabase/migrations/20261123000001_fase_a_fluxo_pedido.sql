-- MilkDim, fase A: fluxo do pedido.
--
-- O pedido passa a existir no servidor em tres situacoes:
--   salvo       em aberto (o vendedor ainda pode mexer)
--   finalizado  entregue (pelo vendedor, com assinatura, ou pelo Controle)
--   cancelado   pelo vendedor ou pelo Controle
--
-- Colunas de auditoria (enviado_em, alterado_em, finalizado_*, cancelado_*)
-- sao preenchidas so pelos gatilhos e pelas RPCs: o que o cliente mandar
-- nelas e ignorado.
--
-- Protecao de pedido fechado: um UPDATE comum em pedido finalizado ou
-- cancelado e ignorado em silencio (a linha volta como estava, e o eco
-- devolve ao app a versao do servidor). Excecao: a entrega assinada vence
-- um pedido cancelado ou finalizado manualmente. A protecao NAO depende de
-- app_is_admin(): os admins tambem usam o app do vendedor. So as RPCs do
-- Controle (milkdim.acao_controle = '1') passam direto.
--
-- RLS de pedidos continua a mesma da fase 3. Os gatilhos AFTER INSERT de
-- ultimo pedido (trg_atualizar_ultimo_pedido, trg_pedidos_update_cliente_ultimo)
-- nao sao tocados.
--
-- Pode rodar de novo sem estrago (if not exists / or replace / drop if
-- exists); o preenchimento das linhas antigas so roda na primeira vez.
--
-- Este arquivo nao abre nem fecha transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- Colunas novas e preenchimento dos pedidos antigos
-- ---------------------------------------------------------------------------
-- enviado_em nasce com now() nas linhas antigas (default de coluna nova);
-- logo em seguida vira a datahora do pedido. Sem datahora, fica created_at
-- ou, faltando os dois, o now() do default.

do $$
declare
  v_primeira_vez boolean;
begin
  v_primeira_vez := not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pedidos'
       and column_name = 'enviado_em');

  alter table public.pedidos
    add column if not exists id_aparelho       uuid,
    add column if not exists enviado_em        timestamptz not null default now(),
    add column if not exists alterado_em       timestamptz,
    add column if not exists finalizado_em     timestamptz,
    add column if not exists finalizado_por    text,
    add column if not exists finalizado_manual boolean not null default false,
    add column if not exists cancelado_em      timestamptz,
    add column if not exists cancelado_por     text;

  if v_primeira_vez then
    -- Na primeira vez os gatilhos desta fase ainda nao existem (sao criados
    -- mais abaixo); a marca e so precaucao, e e desligada logo depois.
    perform set_config('milkdim.acao_controle', '1', true);

    update public.pedidos
       set enviado_em     = coalesce(datahora, created_at::timestamptz, enviado_em),
           finalizado_em  = case when status = 'finalizado'
                                 then coalesce(datahora, created_at::timestamptz, enviado_em) end,
           finalizado_por = case when status = 'finalizado' then vendedor_codigo end;

    perform set_config('milkdim.acao_controle', '', true);
  end if;
end $$;

-- Um aparelho gera um id_aparelho por pedido; o mesmo id nao entra duas vezes.
-- APK antigo nao manda: nulo nao conta.
create unique index if not exists pedidos_id_aparelho_key
  on public.pedidos (id_aparelho)
  where id_aparelho is not null;

-- ---------------------------------------------------------------------------
-- Situacoes validas
-- ---------------------------------------------------------------------------
-- Antes de aplicar, conferir: select status, count(*) from pedidos group by 1;
-- Qualquer valor fora destes tres faz este comando falhar (e a migracao toda).

alter table public.pedidos drop constraint if exists pedidos_status_check;
alter table public.pedidos
  add constraint pedidos_status_check
  check (status in ('salvo', 'finalizado', 'cancelado'));

-- ---------------------------------------------------------------------------
-- app_autor_pedido: quem fez a acao, para finalizado_por / cancelado_por
-- ---------------------------------------------------------------------------
-- O codigo do vendedor logado (app_meu_codigo). Conta de admin do Controle
-- que nao e vendedor (<usuario>@milkdim.local) nao tem codigo: fica o e-mail,
-- para o campo nao ficar vazio. Interna: so os gatilhos e as RPCs chamam.

create or replace function public.app_autor_pedido()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.app_meu_codigo(), nullif(auth.jwt() ->> 'email', ''));
$$;

revoke execute on function public.app_autor_pedido() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- pedidos_antes_inserir (BEFORE INSERT)
-- ---------------------------------------------------------------------------
-- Inclui o INSERT ... ON CONFLICT do app: a linha proposta passa por aqui
-- antes do conflito, e o UPDATE que vem depois passa por pedidos_antes_alterar.

create or replace function public.pedidos_antes_inserir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.enviado_em        := now();
  new.alterado_em       := null;
  new.cancelado_em      := null;
  new.cancelado_por     := null;
  new.finalizado_manual := false;

  if new.status = 'finalizado' then
    new.finalizado_em  := now();
    new.finalizado_por := public.app_autor_pedido();
  else
    new.finalizado_em  := null;
    new.finalizado_por := null;
  end if;

  return new;
end;
$$;

revoke execute on function public.pedidos_antes_inserir() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- pedidos_antes_alterar (BEFORE UPDATE)
-- ---------------------------------------------------------------------------
-- Ordem da regra:
--   1. RPC do Controle (milkdim.acao_controle = '1'): aceita como veio; a
--      RPC ja gravou os campos de auditoria.
--   2. enviado_em nunca muda; id_aparelho, uma vez gravado, nao muda.
--   3. Pedido fechado (finalizado/cancelado): so a entrega assinada sobre
--      um cancelado ou finalizado manual passa. O resto volta OLD, sem erro.
--   4. Pedido em aberto: alterado_em so anda quando muda produtos ou
--      cliente; finalizado_* / cancelado_* conforme a nova situacao, e
--      copiados de OLD no resto (o cliente nao escolhe esses valores).

create or replace function public.pedidos_antes_alterar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    return new;
  end if;

  new.enviado_em  := old.enviado_em;
  new.id_aparelho := coalesce(old.id_aparelho, new.id_aparelho);

  if old.status in ('finalizado', 'cancelado') then
    if new.status = 'finalizado'
       and new.assinatura is not null
       and (old.status = 'cancelado' or old.finalizado_manual) then
      -- Entrega assinada vence: fica a versao do vendedor (produtos,
      -- total, assinatura, situacao). Cancelamento anterior continua
      -- registrado.
      new.finalizado_em     := now();
      new.finalizado_por    := public.app_autor_pedido();
      new.finalizado_manual := false;
      new.cancelado_em      := old.cancelado_em;
      new.cancelado_por     := old.cancelado_por;
      new.alterado_em       := old.alterado_em;
      return new;
    end if;

    -- Ignora em silencio: o eco devolve a versao do servidor.
    return old;
  end if;

  -- Pedido em aberto (salvo).
  if new.produtos     is distinct from old.produtos
     or new.cliente_id   is distinct from old.cliente_id
     or new.cliente_nome is distinct from old.cliente_nome then
    new.alterado_em := now();
  else
    new.alterado_em := old.alterado_em;
  end if;

  if new.status = 'finalizado' then
    new.finalizado_em     := now();
    new.finalizado_por    := public.app_autor_pedido();
    new.finalizado_manual := false;
    new.cancelado_em      := old.cancelado_em;
    new.cancelado_por     := old.cancelado_por;
  elsif new.status = 'cancelado' then
    new.cancelado_em      := now();
    new.cancelado_por     := public.app_autor_pedido();
    new.finalizado_em     := old.finalizado_em;
    new.finalizado_por    := old.finalizado_por;
    new.finalizado_manual := old.finalizado_manual;
  else
    new.finalizado_em     := old.finalizado_em;
    new.finalizado_por    := old.finalizado_por;
    new.finalizado_manual := old.finalizado_manual;
    new.cancelado_em      := old.cancelado_em;
    new.cancelado_por     := old.cancelado_por;
  end if;

  return new;
end;
$$;

revoke execute on function public.pedidos_antes_alterar() from public, anon, authenticated;

drop trigger if exists trg_pedidos_antes_inserir on public.pedidos;
create trigger trg_pedidos_antes_inserir
  before insert on public.pedidos
  for each row execute function public.pedidos_antes_inserir();

drop trigger if exists trg_pedidos_antes_alterar on public.pedidos;
create trigger trg_pedidos_antes_alterar
  before update on public.pedidos
  for each row execute function public.pedidos_antes_alterar();

-- ---------------------------------------------------------------------------
-- RPCs do Controle (so admin)
-- ---------------------------------------------------------------------------
-- So pedido em aberto (salvo). A marca milkdim.acao_controle vale so dentro
-- da transacao e e desligada logo depois do UPDATE, para nao liberar outro
-- UPDATE que venha na mesma transacao. O cliente nao liga a marca: pelo
-- PostgREST ele so chama funcoes expostas, e nenhuma delas recebe nome de
-- configuracao.
--
-- Erros: 42501 sem permissao; P0002 pedido inexistente; 55000 pedido que
-- nao esta em aberto.

create or replace function public.pedido_finalizar_manual(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para finalizar pedido.' using errcode = '42501';
  end if;

  select p.status into v_status
    from public.pedidos p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'Nao ha pedido com id %.', p_id using errcode = 'P0002';
  end if;

  if v_status is distinct from 'salvo' then
    raise exception 'So pedido em aberto pode ser finalizado (pedido % esta %).',
      p_id, coalesce(v_status, 'sem situacao') using errcode = '55000';
  end if;

  perform set_config('milkdim.acao_controle', '1', true);

  update public.pedidos
     set status            = 'finalizado',
         finalizado_em     = now(),
         finalizado_por    = public.app_autor_pedido(),
         finalizado_manual = true
   where id = p_id;

  perform set_config('milkdim.acao_controle', '', true);
end;
$$;

create or replace function public.pedido_cancelar(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para cancelar pedido.' using errcode = '42501';
  end if;

  select p.status into v_status
    from public.pedidos p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'Nao ha pedido com id %.', p_id using errcode = 'P0002';
  end if;

  if v_status is distinct from 'salvo' then
    raise exception 'So pedido em aberto pode ser cancelado (pedido % esta %).',
      p_id, coalesce(v_status, 'sem situacao') using errcode = '55000';
  end if;

  perform set_config('milkdim.acao_controle', '1', true);

  update public.pedidos
     set status        = 'cancelado',
         cancelado_em  = now(),
         cancelado_por = public.app_autor_pedido()
   where id = p_id;

  perform set_config('milkdim.acao_controle', '', true);
end;
$$;

revoke execute on function public.pedido_finalizar_manual(bigint) from public, anon;
revoke execute on function public.pedido_cancelar(bigint) from public, anon;

grant execute on function public.pedido_finalizar_manual(bigint) to authenticated;
grant execute on function public.pedido_cancelar(bigint) to authenticated;
