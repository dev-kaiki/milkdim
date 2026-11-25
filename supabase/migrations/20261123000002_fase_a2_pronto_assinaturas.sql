-- MilkDim, fase A.2: "pronto para entrega" e a assinatura do pedido.
--
-- Roda depois de 20261123000001_fase_a_fluxo_pedido.sql (ja aplicada).
--
-- Situacoes do pedido a partir daqui:
--   salvo       em aberto (o vendedor ainda pode mexer)
--   pronto      producao concluida, pronto para entrega (so o Controle
--               grava, pela RPC pedido_marcar_pronto)
--   finalizado  entregue (pelo vendedor, com a assinatura da entrega, ou
--               pelo Controle, "Marcar como entregue")
--   cancelado   pelo vendedor ou pelo Controle, antes da entrega
--
-- Duas assinaturas:
--   assinatura_pedido  o cliente confirma o pedido (coluna nova). O app
--                      exige; o servidor so guarda: nula nao apaga a que
--                      ja existe.
--   assinatura         o cliente confirma a entrega (ja existia). A regra
--                      "a entrega assinada vence" continua usando esta.
--
-- pronto_em / pronto_por: preenchidos so pela RPC. Quando uma alteracao do
-- vendedor (itens ou cliente) devolve o pedido de pronto para salvo, eles
-- ficam guardados como historico; o Controle mostra "alterado depois de
-- pronto" quando status = 'salvo', pronto_em is not null e
-- alterado_em > pronto_em.
--
-- Os gatilhos AFTER INSERT de ultimo pedido (trg_atualizar_ultimo_pedido,
-- trg_pedidos_update_cliente_ultimo) nao sao tocados, nem a RLS.
--
-- Pode rodar de novo sem estrago (if not exists / or replace / drop if
-- exists). Este arquivo nao abre nem fecha transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- Colunas novas
-- ---------------------------------------------------------------------------

alter table public.pedidos
  add column if not exists assinatura_pedido bytea,
  add column if not exists pronto_em         timestamptz,
  add column if not exists pronto_por        text;

-- ---------------------------------------------------------------------------
-- Situacoes validas
-- ---------------------------------------------------------------------------

alter table public.pedidos drop constraint if exists pedidos_status_check;
alter table public.pedidos
  add constraint pedidos_status_check
  check (status in ('salvo', 'pronto', 'finalizado', 'cancelado'));

-- ---------------------------------------------------------------------------
-- pedidos_antes_inserir (BEFORE INSERT)
-- ---------------------------------------------------------------------------
-- Como na fase A, mais: pronto_em/pronto_por sempre nulos, e um INSERT com
-- status = 'pronto' entra como 'salvo' (so a RPC grava pronto). Inclui o
-- INSERT ... ON CONFLICT do app: a linha proposta (e o excluded.*) ja sai
-- daqui corrigida. assinatura_pedido entra como veio.

create or replace function public.pedidos_antes_inserir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'pronto' then
    new.status := 'salvo';
  end if;

  new.enviado_em        := now();
  new.alterado_em       := null;
  new.finalizado_manual := false;
  new.pronto_em         := null;
  new.pronto_por        := null;

  if new.status = 'finalizado' then
    new.finalizado_em  := now();
    new.finalizado_por := public.app_autor_pedido();
  else
    new.finalizado_em  := null;
    new.finalizado_por := null;
  end if;

  if new.status = 'cancelado' then
    new.cancelado_em  := now();
    new.cancelado_por := public.app_autor_pedido();
  else
    new.cancelado_em  := null;
    new.cancelado_por := null;
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
--   3. assinatura_pedido: a nova, se veio; nula nao apaga a gravada.
--      pronto_em/pronto_por: sempre os de OLD (so a RPC muda).
--   4. Pedido fechado (finalizado/cancelado): so a entrega assinada
--      (assinatura, a da entrega) sobre um cancelado ou finalizado manual
--      passa. O resto volta OLD, sem erro.
--   5. Pedido em aberto ou pronto:
--      - alterado_em so anda quando muda produtos ou cliente;
--      - situacao pedida salvo/pronto: de salvo fica salvo (o vendedor nao
--        grava pronto); de pronto fica pronto, a nao ser que tenha mudado
--        produtos ou cliente, e entao volta para salvo (com alterado_em =
--        now(), pronto_em/pronto_por guardados);
--      - finalizado/cancelado: a regra da fase A, igual para salvo e pronto;
--      - finalizado_* / cancelado_* conforme a nova situacao, e copiados de
--        OLD no resto (o cliente nao escolhe esses valores).

create or replace function public.pedidos_antes_alterar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mudou boolean;
begin
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    return new;
  end if;

  new.enviado_em  := old.enviado_em;
  new.id_aparelho := coalesce(old.id_aparelho, new.id_aparelho);

  new.assinatura_pedido := coalesce(new.assinatura_pedido, old.assinatura_pedido);
  new.pronto_em         := old.pronto_em;
  new.pronto_por        := old.pronto_por;

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

  -- Pedido em aberto (salvo) ou pronto.
  v_mudou := new.produtos     is distinct from old.produtos
          or new.cliente_id   is distinct from old.cliente_id
          or new.cliente_nome is distinct from old.cliente_nome;

  if v_mudou then
    new.alterado_em := now();
  else
    new.alterado_em := old.alterado_em;
  end if;

  -- Situacao pedida salvo/pronto: o servidor decide entre as duas. Outros
  -- valores (fora da constraint) passam para a constraint recusar.
  if new.status in ('salvo', 'pronto') then
    if old.status = 'pronto' and not v_mudou then
      new.status := 'pronto';
    else
      new.status := 'salvo';
    end if;
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

-- Os gatilhos trg_pedidos_antes_inserir / trg_pedidos_antes_alterar da
-- fase A ja apontam para estas funcoes: o "or replace" basta, eles nao sao
-- recriados.

-- ---------------------------------------------------------------------------
-- RPCs do Controle (so admin)
-- ---------------------------------------------------------------------------
-- Mesmo molde da fase A: a marca milkdim.acao_controle vale so dentro da
-- transacao e e desligada logo depois do UPDATE.
--
-- Erros: 42501 sem permissao; P0002 pedido inexistente; 55000 pedido fora
-- da situacao aceita; MD001 (codigo proprio do MilkDim, so em
-- pedido_marcar_pronto) pedido mudou depois que a tela do Controle foi
-- atualizada.

-- Producao concluida: salvo -> pronto.
--
-- p_alterado_em: o alterado_em que a tela do Controle mostrava quando a
-- fabrica clicou "Producao concluida". Se o vendedor mudou o pedido depois
-- disso, o alterado_em do banco ja e outro e a RPC recusa com MD001, para
-- a fabrica nao marcar como pronta uma versao que ela nao viu (e produzir
-- as quantidades antigas). Nulo = nulo conta como igual: pedido nunca
-- alterado. Quem chama sempre manda o valor que viu; a chamada com um
-- argumento so (p_alterado_em nulo) continua valendo para pedido nunca
-- alterado.
--
-- A versao de um argumento so nao fica ao lado desta (deixaria a chamada
-- com um argumento ambigua); o drop cobre um banco onde ela exista.
drop function if exists public.pedido_marcar_pronto(bigint);

create or replace function public.pedido_marcar_pronto(
  p_id bigint,
  p_alterado_em timestamptz default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status   text;
  v_alterado timestamptz;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para marcar pedido como pronto.' using errcode = '42501';
  end if;

  select p.status, p.alterado_em into v_status, v_alterado
    from public.pedidos p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'Nao ha pedido com id %.', p_id using errcode = 'P0002';
  end if;

  if v_status is distinct from 'salvo' then
    raise exception 'So pedido em aberto pode ser marcado como pronto (pedido % esta %).',
      p_id, coalesce(v_status, 'sem situacao') using errcode = '55000';
  end if;

  if v_alterado is distinct from p_alterado_em then
    raise exception 'O pedido mudou depois que a tela foi atualizada. Atualize e confira.'
      using errcode = 'MD001';
  end if;

  perform set_config('milkdim.acao_controle', '1', true);

  update public.pedidos
     set status     = 'pronto',
         pronto_em  = now(),
         pronto_por = public.app_autor_pedido()
   where id = p_id;

  perform set_config('milkdim.acao_controle', '', true);
end;
$$;

-- Marcar como entregue (manual): salvo ou pronto -> finalizado.
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

  if v_status is null or v_status not in ('salvo', 'pronto') then
    raise exception 'So pedido em aberto ou pronto pode ser finalizado (pedido % esta %).',
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

-- Cancelar: salvo ou pronto -> cancelado.
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

  if v_status is null or v_status not in ('salvo', 'pronto') then
    raise exception 'So pedido em aberto ou pronto pode ser cancelado (pedido % esta %).',
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

revoke execute on function public.pedido_marcar_pronto(bigint, timestamptz) from public, anon;
revoke execute on function public.pedido_finalizar_manual(bigint) from public, anon;
revoke execute on function public.pedido_cancelar(bigint) from public, anon;

grant execute on function public.pedido_marcar_pronto(bigint, timestamptz) to authenticated;
grant execute on function public.pedido_finalizar_manual(bigint) to authenticated;
grant execute on function public.pedido_cancelar(bigint) to authenticated;
