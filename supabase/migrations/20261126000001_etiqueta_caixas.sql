-- MilkDim: etiqueta por caixa (volumes do pedido).
--
-- Roda depois de 20261124000001_fase_b_etiqueta_qr.sql.
--
-- Tabelas novas:
--   tipos_caixa     os tipos de caixa da fabrica (Pote, Copo, Medio...):
--                   nome unico sem contar maiusculas nem espacos nas pontas,
--                   e nunca vazio; capacidade = quantos itens cabem numa
--                   caixa; mistura_sabores = a caixa aceita produtos
--                   diferentes juntos; ativo = so o app desliga (nunca se
--                   apaga tipo em uso: produtos.tipo_caixa_id vira nulo se
--                   o tipo for apagado).
--   pedido_volumes  como o Controle montou as caixas de um pedido (uma
--                   linha por pedido; apagar o pedido apaga a linha).
--                   volumes e um array de objetos
--                     {"tipo": "caixa"|"avulso", "caixa": text|null,
--                      "itens": [{"nome": text, "quantidade": int}]}
--                   pedido_alterado_em guarda o alterado_em do pedido no
--                   momento em que as caixas foram salvas: o app so confia
--                   nos volumes salvos enquanto a soma por produto bater
--                   com os itens atuais.
--
-- Coluna nova em produtos:
--   tipo_caixa_id   tipo de caixa do produto (nulo = vai para os avulsos).
--                   As politicas de produtos nao mudam: todos os
--                   autenticados leem e so admin altera.
--
-- RPC nova (security definer, search_path vazio, so authenticated):
--   pedido_salvar_volumes(p_id, p_solto, p_volumes)   Controle (admin)
--     Grava (upsert) os volumes de um pedido salvo ou pronto, depois de
--     conferir que a soma por produto (nome com btrim) bate com os itens do
--     pedido. Nao mexe em pedidos. Erros:
--       42501  nao e admin
--       P0002  pedido inexistente
--       MD010  pedido que nao esta salvo nem pronto
--       22023  formato invalido, volume sem item, quantidade que nao e
--              inteiro maior que zero, ou p_solto sem exatamente 1 volume
--              do tipo avulso
--       MD011  a soma por produto nao bate com o pedido
--
-- Permissoes: so admin (public.app_is_admin()) le tipos_caixa e
-- pedido_volumes; so admin escreve em tipos_caixa; ninguem escreve direto em
-- pedido_volumes (so a RPC, que roda como dono da tabela); anon nao tem
-- acesso nenhum.
--
-- Dados iniciais: os 3 tipos, so se ainda nao existirem, e a ligacao dos
-- produtos pelo nome, so nos produtos que ainda estao sem tipo (uma nova
-- rodada nao desfaz escolha feita a mao):
--   nome que comeca com "pote" e contem "160g"  -> Pote
--   nome que comeca com "copo"                  -> Copo
--   nome que comeca com "550g"                  -> Medio
-- (sem contar maiusculas nem espacos nas pontas). O resto fica sem tipo.
--
-- Pode rodar de novo sem estrago (if not exists / or replace / drop ... if
-- exists / on conflict do nothing). Este arquivo nao abre nem fecha
-- transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- tipos_caixa
-- ---------------------------------------------------------------------------

create table if not exists public.tipos_caixa (
  id               bigint  generated always as identity primary key,
  nome             text    not null
                   constraint tipos_caixa_nome_nao_vazio check (btrim(nome) <> ''),
  capacidade       int     not null check (capacidade > 0),
  mistura_sabores  boolean not null default true,
  ativo            boolean not null default true
);

create unique index if not exists tipos_caixa_nome_key
  on public.tipos_caixa (lower(btrim(nome)));

-- ---------------------------------------------------------------------------
-- produtos.tipo_caixa_id
-- ---------------------------------------------------------------------------

alter table public.produtos
  add column if not exists tipo_caixa_id bigint
    references public.tipos_caixa (id) on delete set null;

create index if not exists produtos_tipo_caixa_id_idx
  on public.produtos (tipo_caixa_id);

-- ---------------------------------------------------------------------------
-- pedido_volumes
-- ---------------------------------------------------------------------------

create table if not exists public.pedido_volumes (
  pedido_id           bigint      primary key
                      references public.pedidos (id) on delete cascade,
  solto               boolean     not null,
  volumes             jsonb       not null
                      check (jsonb_typeof(volumes) = 'array'),
  pedido_alterado_em  timestamptz,
  salvo_em            timestamptz not null,
  salvo_por           text
);

-- ---------------------------------------------------------------------------
-- Permissoes das tabelas
-- ---------------------------------------------------------------------------

alter table public.tipos_caixa    enable row level security;
alter table public.pedido_volumes enable row level security;

-- tipos_caixa: so admin, para tudo.
drop policy if exists tipos_caixa_admin on public.tipos_caixa;
create policy tipos_caixa_admin on public.tipos_caixa
  for all to authenticated
  using (public.app_is_admin())
  with check (public.app_is_admin());

-- pedido_volumes: so admin le; nenhuma politica de escrita.
drop policy if exists pedido_volumes_ler_admin on public.pedido_volumes;
create policy pedido_volumes_ler_admin on public.pedido_volumes
  for select to authenticated
  using (public.app_is_admin());

revoke all on public.tipos_caixa    from anon;
revoke all on public.pedido_volumes from anon;

-- pedido_volumes: tira tudo de authenticated (inclusive privilegios padrao
-- do projeto) e devolve so o select. Escrever = so pela RPC.
revoke all on public.pedido_volumes from authenticated;

grant select, insert, update, delete on public.tipos_caixa to authenticated;
grant select on public.pedido_volumes to authenticated;

-- ---------------------------------------------------------------------------
-- RPC pedido_salvar_volumes (Controle, so admin)
-- ---------------------------------------------------------------------------
-- A linha de pedidos fica travada (for update) durante a conferencia, para
-- ninguem mudar os itens entre a soma e a gravacao. O alterado_em gravado e
-- o do pedido nesse instante. O UPDATE de pedidos nao acontece aqui: gatilhos
-- e alterado_em de pedidos ficam como estao.
--
-- Soma por nome: nome do item com btrim, sem diferenciar nada alem disso
-- (o app manda o nome do item do pedido como esta). Quantidade do item do
-- pedido: "quantidade" ou, faltando (ou nula), "qtd", lida como em
-- pedido_por_qr. Compara nos dois sentidos: nome que falta e nome que sobra
-- nos volumes dao MD011.

create or replace function public.pedido_salvar_volumes(
  p_id      bigint,
  p_solto   boolean,
  p_volumes jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status    text;
  v_alterado  timestamptz;
  v_produtos  jsonb;
  v_vol       jsonb;
  v_item      jsonb;
  v_q         numeric;
  v_difere    boolean;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para salvar as caixas do pedido.' using errcode = '42501';
  end if;

  select p.status, p.alterado_em, p.produtos
    into v_status, v_alterado, v_produtos
    from public.pedidos p
   where p.id = p_id
     for update;

  if not found then
    raise exception 'Nao ha pedido com id %.', p_id using errcode = 'P0002';
  end if;

  if v_status is distinct from 'salvo' and v_status is distinct from 'pronto' then
    raise exception 'Este pedido nao pode ter as caixas alteradas.' using errcode = 'MD010';
  end if;

  -- Formato.
  if p_solto is null then
    raise exception 'p_solto nao pode ser nulo.' using errcode = '22023';
  end if;

  if jsonb_typeof(p_volumes) is distinct from 'array' then
    raise exception 'p_volumes tem que ser um array.' using errcode = '22023';
  end if;

  if jsonb_array_length(p_volumes) = 0 then
    raise exception 'p_volumes nao pode ser vazio.' using errcode = '22023';
  end if;

  for v_vol in select e.value from jsonb_array_elements(p_volumes) as e loop
    if jsonb_typeof(v_vol) is distinct from 'object' then
      raise exception 'Cada volume tem que ser um objeto.' using errcode = '22023';
    end if;

    if jsonb_typeof(v_vol -> 'tipo') is distinct from 'string'
       or (v_vol ->> 'tipo') not in ('caixa', 'avulso') then
      raise exception 'O tipo do volume tem que ser caixa ou avulso.' using errcode = '22023';
    end if;

    if (v_vol -> 'caixa') is not null
       and jsonb_typeof(v_vol -> 'caixa') not in ('string', 'null') then
      raise exception 'O campo caixa do volume tem que ser texto ou nulo.' using errcode = '22023';
    end if;

    if jsonb_typeof(v_vol -> 'itens') is distinct from 'array' then
      raise exception 'Os itens do volume tem que ser um array.' using errcode = '22023';
    end if;

    if jsonb_array_length(v_vol -> 'itens') = 0 then
      raise exception 'Volume sem item.' using errcode = '22023';
    end if;

    for v_item in select e.value from jsonb_array_elements(v_vol -> 'itens') as e loop
      if jsonb_typeof(v_item) is distinct from 'object' then
        raise exception 'Cada item do volume tem que ser um objeto.' using errcode = '22023';
      end if;

      if jsonb_typeof(v_item -> 'nome') is distinct from 'string'
         or btrim(v_item ->> 'nome') = '' then
        raise exception 'O nome do item tem que ser um texto nao vazio.' using errcode = '22023';
      end if;

      if jsonb_typeof(v_item -> 'quantidade') is distinct from 'number' then
        raise exception 'A quantidade do item tem que ser um numero.' using errcode = '22023';
      end if;

      v_q := (v_item ->> 'quantidade')::numeric;
      if v_q <> trunc(v_q) or v_q < 1 or v_q >= 2147483648 then
        raise exception 'A quantidade do item tem que ser um inteiro maior que zero.'
          using errcode = '22023';
      end if;
    end loop;
  end loop;

  -- Pedido solto: um volume so, avulso.
  if p_solto
     and (jsonb_array_length(p_volumes) <> 1
          or (p_volumes -> 0 ->> 'tipo') is distinct from 'avulso') then
    raise exception 'Pedido solto tem exatamente 1 volume, do tipo avulso.'
      using errcode = '22023';
  end if;

  -- Soma por nome (btrim), nos dois sentidos.
  select exists (
    select 1
      from (
        select coalesce(btrim(it.item ->> 'nome'), '') as nome,
               sum(
                 case jsonb_typeof(q.valor)
                   when 'number' then
                     case when abs((q.valor #>> '{}')::numeric) < 2147483648
                          then trunc((q.valor #>> '{}')::numeric)::bigint
                          else 0 end
                   when 'string' then
                     case when btrim(q.valor #>> '{}') ~ '^[+-]?[0-9]{1,9}$'
                          then btrim(q.valor #>> '{}')::bigint
                          else 0 end
                   else 0
                 end) as qtd
          from jsonb_array_elements(
                 case when jsonb_typeof(v_produtos) = 'array'
                      then v_produtos else '[]'::jsonb end) as it(item)
         cross join lateral (
           select coalesce(nullif(it.item -> 'quantidade', 'null'::jsonb),
                           it.item -> 'qtd') as valor
         ) q
         group by 1
      ) ped
      full join (
        select btrim(i.item ->> 'nome') as nome,
               sum(trunc((i.item ->> 'quantidade')::numeric)::bigint) as qtd
          from jsonb_array_elements(p_volumes) as v(vol)
         cross join lateral jsonb_array_elements(v.vol -> 'itens') as i(item)
         group by 1
      ) vol on vol.nome = ped.nome
     where coalesce(ped.qtd, 0) <> coalesce(vol.qtd, 0)
  ) into v_difere;

  if v_difere then
    raise exception 'As caixas nao batem com o pedido.' using errcode = 'MD011';
  end if;

  insert into public.pedido_volumes
         (pedido_id, solto, volumes, pedido_alterado_em, salvo_em, salvo_por)
  values (p_id, p_solto, p_volumes, v_alterado, now(), public.app_autor_pedido())
  on conflict (pedido_id) do update
     set solto              = excluded.solto,
         volumes            = excluded.volumes,
         pedido_alterado_em = excluded.pedido_alterado_em,
         salvo_em           = excluded.salvo_em,
         salvo_por          = excluded.salvo_por;
end;
$$;

revoke execute on function public.pedido_salvar_volumes(bigint, boolean, jsonb) from public, anon;
grant execute on function public.pedido_salvar_volumes(bigint, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Dados iniciais
-- ---------------------------------------------------------------------------
-- Roda como dono das tabelas (migracao), sem passar pela RLS. O conflito e
-- sobre o indice unico do nome: de novo, nao duplica nem muda capacidade.

insert into public.tipos_caixa (nome, capacidade, mistura_sabores, ativo) values
  ('Pote',  16, true, true),
  ('Copo',  20, true, true),
  ('Médio',  4, true, true)
on conflict ((lower(btrim(nome)))) do nothing;

-- Ligacao inicial dos produtos pelo nome, so onde ainda nao ha tipo. Os tres
-- padroes nao se cruzam (comecos diferentes), entao a ordem nao importa.
update public.produtos
   set tipo_caixa_id = (select t.id from public.tipos_caixa t
                         where lower(btrim(t.nome)) = 'pote')
 where tipo_caixa_id is null
   and lower(btrim(nome)) like 'pote%'
   and lower(btrim(nome)) like '%160g%';

update public.produtos
   set tipo_caixa_id = (select t.id from public.tipos_caixa t
                         where lower(btrim(t.nome)) = 'copo')
 where tipo_caixa_id is null
   and lower(btrim(nome)) like 'copo%';

update public.produtos
   set tipo_caixa_id = (select t.id from public.tipos_caixa t
                         where lower(btrim(t.nome)) = lower('Médio'))
 where tipo_caixa_id is null
   and lower(btrim(nome)) like '550g%';
