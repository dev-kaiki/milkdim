-- MilkDim, fase B: etiqueta do pedido com QR para registrar a entrega.
--
-- Roda depois de 20261123000002_fase_a2_pronto_assinaturas.sql.
--
-- Colunas novas em pedidos:
--   codigo_qr              codigo secreto do pedido (uuid aleatorio), que
--                          vai no QR da etiqueta. Quem tem a etiqueta na mao
--                          abre so aquele pedido. Os pedidos que ja existem
--                          recebem um pelo valor padrao.
--   etiqueta_impressa_em   quando o Controle imprimiu a etiqueta (a ultima vez)
--   etiqueta_impressa_por  quem imprimiu (codigo, ou o e-mail da conta do
--                          Controle sem codigo, como em finalizado_por)
--
-- O app nao escolhe nenhuma das tres:
--   - no INSERT o servidor gera o codigo_qr (ignora o que veio) e zera a
--     etiqueta;
--   - no UPDATE as tres ficam sempre com o valor antigo.
-- So as RPCs desta fase mudam essas colunas.
--
-- RPCs novas (security definer, search_path vazio, so authenticated):
--   pedido_marcar_etiqueta(p_id)              Controle (admin): etiqueta impressa
--   pedido_por_qr(p_codigo)                   qualquer vendedor: o que a
--                                             entrega precisa, sem precos
--   pedido_entregar_por_qr(p_codigo, p_assin) qualquer vendedor: registra a
--                                             entrega com a assinatura
--
-- A RLS de pedidos nao muda: um vendedor continua sem ver por select os
-- pedidos dos outros. As RPCs leem so o pedido do codigo recebido.
--
-- Compativel com os APKs da fase A: colunas novas com valor padrao, nenhuma
-- coluna removida, o resto dos gatilhos igual ao da fase A.2.
--
-- Pode rodar de novo sem estrago (if not exists / or replace). Este arquivo
-- nao abre nem fecha transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- Colunas novas
-- ---------------------------------------------------------------------------
-- O default gen_random_uuid() e volatil: cada linha antiga ganha o seu.

alter table public.pedidos
  add column if not exists codigo_qr             uuid not null default gen_random_uuid(),
  add column if not exists etiqueta_impressa_em  timestamptz,
  add column if not exists etiqueta_impressa_por text;

create unique index if not exists pedidos_codigo_qr_key
  on public.pedidos (codigo_qr);

-- ---------------------------------------------------------------------------
-- pedidos_antes_inserir (BEFORE INSERT)
-- ---------------------------------------------------------------------------
-- Como na fase A.2, mais: codigo_qr sempre gerado aqui (o que o app mandar
-- e ignorado) e etiqueta_impressa_* sempre nulos. Com a marca das RPCs
-- (milkdim.acao_controle = '1') essa parte nao mexe em nada; hoje nenhuma
-- RPC insere pedido. Inclui o INSERT ... ON CONFLICT do app: o excluded.*
-- ja sai daqui com o codigo novo, e o UPDATE que vem depois (gatilho de
-- alteracao) guarda o codigo antigo.

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

  if coalesce(current_setting('milkdim.acao_controle', true), '') <> '1' then
    new.codigo_qr             := gen_random_uuid();
    new.etiqueta_impressa_em  := null;
    new.etiqueta_impressa_por := null;
  end if;

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
-- Ordem da regra (a da fase A.2, com o item 3 maior):
--   1. RPC do Controle (milkdim.acao_controle = '1'): aceita como veio; a
--      RPC ja gravou os campos de auditoria.
--   2. enviado_em nunca muda; id_aparelho, uma vez gravado, nao muda.
--   3. assinatura_pedido: a nova, se veio; nula nao apaga a gravada.
--      pronto_em/pronto_por: sempre os de OLD (so a RPC muda).
--      codigo_qr e etiqueta_impressa_em/_por: sempre os de OLD (so as RPCs
--      da fase B mudam). Fica antes do item 4 para valer tambem na entrega
--      assinada que vence um pedido fechado.
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

  new.codigo_qr             := old.codigo_qr;
  new.etiqueta_impressa_em  := old.etiqueta_impressa_em;
  new.etiqueta_impressa_por := old.etiqueta_impressa_por;

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
-- fase A ja apontam para estas funcoes: o "or replace" basta.

-- ---------------------------------------------------------------------------
-- pedido_marcar_etiqueta (Controle, so admin)
-- ---------------------------------------------------------------------------
-- O Controle chama depois que a fabrica confirma que a etiqueta saiu certa.
-- Grava quando e quem; qualquer situacao do pedido serve. Mesmo molde de
-- pedido_marcar_pronto: a marca milkdim.acao_controle vale so dentro da
-- transacao e e desligada logo depois do UPDATE. Com a marca o gatilho
-- aceita a linha como veio, entao status e alterado_em nao mudam (o UPDATE
-- so toca as duas colunas da etiqueta).
--
-- Erros: 42501 sem permissao; P0002 pedido inexistente.

create or replace function public.pedido_marcar_etiqueta(p_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para marcar a etiqueta do pedido.' using errcode = '42501';
  end if;

  perform 1
    from public.pedidos p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'Nao ha pedido com id %.', p_id using errcode = 'P0002';
  end if;

  perform set_config('milkdim.acao_controle', '1', true);

  update public.pedidos
     set etiqueta_impressa_em  = now(),
         etiqueta_impressa_por = public.app_autor_pedido()
   where id = p_id;

  perform set_config('milkdim.acao_controle', '', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- pedido_por_qr (qualquer vendedor com codigo)
-- ---------------------------------------------------------------------------
-- Quem leu a etiqueta ve so o que a entrega precisa: sem preco, total,
-- CPF/CNPJ, telefone nem assinaturas. Pedido entregue ou cancelado devolve
-- so numero e status: a etiqueta antiga deixa de mostrar o cliente.
--
-- itens: [{"nome", "quantidade"}] na ordem de produtos. quantidade vem de
-- "quantidade" ou, faltando (ou nula), de "qtd", como o app le: numero e
-- truncado para inteiro, texto so vale se for inteiro, o resto vira 0.
--
-- Erros: 42501 conta sem codigo de vendedor; P0002 codigo desconhecido.

create or replace function public.pedido_por_qr(p_codigo uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_meu   text;
  v_p     record;
  v_itens jsonb;
begin
  v_meu := public.app_meu_codigo();
  if v_meu is null then
    raise exception 'So vendedor pode ler a etiqueta do pedido.' using errcode = '42501';
  end if;

  select p.id, p.numero, p.status, p.vendedor_codigo, p.vendedor_nome,
         p.cliente_nome, p.cliente_nome_fantasia, p.cliente_cidade, p.produtos
    into v_p
    from public.pedidos p
   where p.codigo_qr = p_codigo;

  if not found then
    raise exception 'Pedido nao encontrado.' using errcode = 'P0002';
  end if;

  if v_p.status in ('finalizado', 'cancelado') then
    return jsonb_build_object('numero', v_p.numero, 'status', v_p.status);
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'nome', it.item ->> 'nome',
             'quantidade',
               -- CASE aninhado: o cast so roda depois de conferido o tipo.
               case jsonb_typeof(q.valor)
                 when 'number' then
                   case when abs((q.valor #>> '{}')::numeric) < 2147483648
                        then trunc((q.valor #>> '{}')::numeric)::integer
                        else 0 end
                 when 'string' then
                   case when btrim(q.valor #>> '{}') ~ '^[+-]?[0-9]{1,9}$'
                        then btrim(q.valor #>> '{}')::integer
                        else 0 end
                 else 0
               end)
           order by it.ordem), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(
           case when jsonb_typeof(v_p.produtos) = 'array'
                then v_p.produtos else '[]'::jsonb end)
           with ordinality as it(item, ordem)
   cross join lateral (
     select coalesce(nullif(it.item -> 'quantidade', 'null'::jsonb),
                     it.item -> 'qtd') as valor
   ) q;

  return jsonb_build_object(
    'id',                    v_p.id,
    'numero',                v_p.numero,
    'status',                v_p.status,
    'vendedor_codigo',       v_p.vendedor_codigo,
    'vendedor_nome',         v_p.vendedor_nome,
    'cliente_nome',          v_p.cliente_nome,
    'cliente_nome_fantasia', v_p.cliente_nome_fantasia,
    'cliente_cidade',        v_p.cliente_cidade,
    'itens',                 v_itens,
    'do_proprio_vendedor',   coalesce(v_p.vendedor_codigo = v_meu, false));
end;
$$;

-- ---------------------------------------------------------------------------
-- pedido_entregar_por_qr (qualquer vendedor com codigo)
-- ---------------------------------------------------------------------------
-- A mesma transicao que o vendedor faz hoje ao registrar a entrega: status
-- = 'finalizado' com a assinatura. O UPDATE vai SEM a marca das RPCs, para
-- o gatilho de alteracao aplicar as regras de sempre e preencher
-- finalizado_em e finalizado_por. finalizado_por sai de app_autor_pedido(),
-- que le o JWT de quem chamou (o security definer nao muda o JWT): fica o
-- codigo de quem entregou, nao o do vendedor do pedido.
--
-- Quem nao e o vendedor do pedido so entrega pedido pronto. O vendedor do
-- pedido segue as regras de hoje: pode entregar pedido em aberto, e a
-- entrega assinada vence o cancelamento e o "Marcar como entregue" do
-- Controle.
--
-- Erros:
--   42501  conta sem codigo de vendedor
--   22023  assinatura nula ou vazia
--   P0002  codigo desconhecido
--   MD002  pedido ja entregue: qualquer entregue quando quem chama nao e o
--          vendedor do pedido; para o vendedor do pedido, entregue com
--          assinatura ou sem a marca de manual (como os pedidos antigos)
--   MD003  quem chama nao e o vendedor do pedido e ele nao esta pronto
--   MD004  quem chama nao e o vendedor do pedido e ele esta cancelado
--   55000  o gatilho nao aceitou a entrega (nao deveria acontecer depois
--          das checagens acima)

create or replace function public.pedido_entregar_por_qr(p_codigo uuid, p_assinatura bytea)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meu        text;
  v_id         bigint;
  v_numero     text;
  v_status     text;
  v_vendedor   text;
  v_assinatura bytea;
  v_manual     boolean;
  v_novo       record;
begin
  v_meu := public.app_meu_codigo();
  if v_meu is null then
    raise exception 'So vendedor pode registrar a entrega pela etiqueta.' using errcode = '42501';
  end if;

  if p_assinatura is null or length(p_assinatura) = 0 then
    raise exception 'A assinatura da entrega e obrigatoria.' using errcode = '22023';
  end if;

  select p.id, p.numero, p.status, p.vendedor_codigo, p.assinatura, p.finalizado_manual
    into v_id, v_numero, v_status, v_vendedor, v_assinatura, v_manual
    from public.pedidos p
   where p.codigo_qr = p_codigo
     for update;

  if not found then
    raise exception 'Pedido nao encontrado.' using errcode = 'P0002';
  end if;

  if v_vendedor is distinct from v_meu then
    -- Quem nao e o vendedor do pedido: so pronto.
    if v_status = 'finalizado' then
      raise exception 'Este pedido ja foi entregue.' using errcode = 'MD002';
    end if;
    if v_status = 'cancelado' then
      raise exception 'Este pedido foi cancelado.' using errcode = 'MD004';
    end if;
    if v_status is distinct from 'pronto' then
      raise exception 'Este pedido ainda nao esta pronto para entrega.' using errcode = 'MD003';
    end if;
  else
    -- O vendedor do pedido: as regras de hoje. Entregue so aceita a
    -- entrega assinada quando foi o "Marcar como entregue" do Controle sem
    -- assinatura (a mesma condicao do gatilho); entrega assinada, ou
    -- entregue sem marca de manual (os pedidos antigos), da MD002.
    if v_status = 'finalizado'
       and (v_assinatura is not null or not coalesce(v_manual, false)) then
      raise exception 'Este pedido ja foi entregue.' using errcode = 'MD002';
    end if;
  end if;

  update public.pedidos
     set status     = 'finalizado',
         assinatura = p_assinatura
   where id = v_id
  returning status, assinatura, finalizado_em
       into v_novo;

  if v_novo.status is distinct from 'finalizado'
     or v_novo.assinatura is distinct from p_assinatura then
    raise exception 'O pedido % nao aceitou a entrega.', v_numero using errcode = '55000';
  end if;

  return jsonb_build_object(
    'id',            v_id,
    'numero',        v_numero,
    'finalizado_em', v_novo.finalizado_em);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissoes: so authenticated
-- ---------------------------------------------------------------------------

revoke execute on function public.pedido_marcar_etiqueta(bigint) from public, anon;
revoke execute on function public.pedido_por_qr(uuid) from public, anon;
revoke execute on function public.pedido_entregar_por_qr(uuid, bytea) from public, anon;

grant execute on function public.pedido_marcar_etiqueta(bigint) to authenticated;
grant execute on function public.pedido_por_qr(uuid) to authenticated;
grant execute on function public.pedido_entregar_por_qr(uuid, bytea) to authenticated;
