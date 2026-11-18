-- MilkDim, fase 3 da troca para Supabase Auth: FECHA o banco.
--
-- Pressupoe a fase 1 (20261118000001) aplicada e os dois apps ja logando
-- pelo Supabase Auth. Depois disto a chave anonima nao le nem grava nada:
-- o app velho para de funcionar.
--
-- Politicas (todas "to authenticated"):
--
--   tabela      ler                        inserir     alterar        apagar
--   clientes    todos                      todos       admin          admin
--   produtos    todos                      admin       admin          admin
--   vendedores  a propria linha; admin     so por RPC  admin (nome,   so por RPC
--                                                      anotacao)
--   pedidos     os proprios; admin         os proprios os proprios;   admin
--                                                      admin
--
-- Vendedor nao altera a propria linha em vendedores (nem o codigo): o
-- app_meu_codigo() liga auth.uid() ao codigo, e trocar o codigo faria o
-- vendedor herdar os pedidos de outro.
--
-- Este arquivo nao abre nem fecha transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- Pre-condicoes: sem elas esta migracao apagaria a unica copia das senhas
-- ---------------------------------------------------------------------------
-- Mais abaixo saem vendedores.senha e acesso_admin. Antes disso as contas
-- do Auth tem que existir: as dos vendedores (fase 1) e as dos admins
-- (app_migrar_admin, rodado a mao). Faltando qualquer uma, para tudo aqui,
-- antes de mexer em qualquer coisa.

do $$
declare
  v_admins  bigint;
  v_acessos bigint;
  v_lista   text;
begin
  select count(*) into v_admins
    from auth.users
   where raw_app_meta_data ->> 'role' = 'admin';

  if v_admins = 0 then
    raise exception 'Fase 3 cancelada: nenhuma conta de admin no Auth. Rode app_migrar_admin para cada linha de acesso_admin antes.';
  end if;

  select string_agg(coalesce(codigo, '(sem codigo)') || ' (id ' || id || ')', ', ' order by id)
    into v_lista
    from public.vendedores
   where auth_user_id is null;

  if v_lista is not null then
    raise exception 'Fase 3 cancelada: vendedor(es) sem conta no Auth: %.', v_lista;
  end if;

  -- Mesmo e-mail que a fase 1 montou e que o app usa no login.
  select string_agg(v.codigo || ' -> ' || coalesce(u.email, '(conta inexistente)'), ', ' order by v.id)
    into v_lista
    from public.vendedores v
    left join auth.users u on u.id = v.auth_user_id
   where u.email is distinct from lower(btrim(v.codigo)) || '@milkdim.local';

  if v_lista is not null then
    raise exception 'Fase 3 cancelada: vendedor(es) ligados a conta com e-mail diferente do codigo: %.', v_lista;
  end if;

  select count(*) into v_acessos
    from public.acesso_admin
   where coalesce(ativo, true);

  if v_admins < v_acessos then
    raise exception 'Fase 3 cancelada: % conta(s) de admin no Auth para % senha(s) ativa(s) em acesso_admin. Rode app_migrar_admin para as que faltam.',
      v_admins, v_acessos;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Politicas antigas (abertas para public)
-- ---------------------------------------------------------------------------

drop policy if exists public_select_insert     on public.clientes;
drop policy if exists "anon read clientes"     on public.clientes;
drop policy if exists "anon insert clientes"   on public.clientes;
drop policy if exists "anon update clientes"   on public.clientes;
drop policy if exists "anon delete clientes"   on public.clientes;

drop policy if exists public_select_insert     on public.produtos;
drop policy if exists "anon read produtos"     on public.produtos;
drop policy if exists "anon insert produtos"   on public.produtos;
drop policy if exists "anon update produtos"   on public.produtos;
drop policy if exists "anon delete produtos"   on public.produtos;

drop policy if exists public_select_insert       on public.vendedores;
drop policy if exists "anon select vendedores"   on public.vendedores;
drop policy if exists "anon insert vendedores"   on public.vendedores;
drop policy if exists "anon update vendedores"   on public.vendedores;
drop policy if exists "anon delete vendedores"   on public.vendedores;

drop policy if exists public_select_insert on public.pedidos;

-- ---------------------------------------------------------------------------
-- Politicas novas
-- ---------------------------------------------------------------------------
-- As funcoes vao dentro de (select ...) para o Postgres avaliar uma vez por
-- comando, e nao uma vez por linha.

alter table public.clientes   enable row level security;
alter table public.produtos   enable row level security;
alter table public.vendedores enable row level security;
alter table public.pedidos    enable row level security;

-- clientes
create policy clientes_ler on public.clientes
  for select to authenticated
  using (true);

create policy clientes_inserir on public.clientes
  for insert to authenticated
  with check (true);

create policy clientes_alterar_admin on public.clientes
  for update to authenticated
  using ((select public.app_is_admin()))
  with check ((select public.app_is_admin()));

create policy clientes_apagar_admin on public.clientes
  for delete to authenticated
  using ((select public.app_is_admin()));

-- produtos
create policy produtos_ler on public.produtos
  for select to authenticated
  using (true);

create policy produtos_inserir_admin on public.produtos
  for insert to authenticated
  with check ((select public.app_is_admin()));

create policy produtos_alterar_admin on public.produtos
  for update to authenticated
  using ((select public.app_is_admin()))
  with check ((select public.app_is_admin()));

create policy produtos_apagar_admin on public.produtos
  for delete to authenticated
  using ((select public.app_is_admin()));

-- vendedores: sem politica de insert/delete; isso so por app_criar_vendedor
-- e app_excluir_vendedor (SECURITY DEFINER).
create policy vendedores_ler on public.vendedores
  for select to authenticated
  using (auth_user_id = (select auth.uid()) or (select public.app_is_admin()));

create policy vendedores_alterar_admin on public.vendedores
  for update to authenticated
  using ((select public.app_is_admin()))
  with check ((select public.app_is_admin()));

-- A politica nao escolhe coluna; o grant escolhe. Admin so muda nome e
-- anotacao direto na tabela. codigo nao: app_meu_codigo() liga a conta ao
-- codigo, e trocar o codigo deixaria os pedidos pendentes do vendedor fora
-- do alcance dele. ativo, senha e exclusao vao pelas funcoes de gestao
-- (SECURITY DEFINER, nao dependem deste grant).
revoke update on public.vendedores from authenticated;
grant update (nome, anotacao) on public.vendedores to authenticated;

-- pedidos: o with check impede gravar pedido com o codigo de outro vendedor.
create policy pedidos_ler on public.pedidos
  for select to authenticated
  using (vendedor_codigo = (select public.app_meu_codigo()) or (select public.app_is_admin()));

create policy pedidos_inserir on public.pedidos
  for insert to authenticated
  with check (vendedor_codigo = (select public.app_meu_codigo()) or (select public.app_is_admin()));

create policy pedidos_alterar on public.pedidos
  for update to authenticated
  using (vendedor_codigo = (select public.app_meu_codigo()) or (select public.app_is_admin()))
  with check (vendedor_codigo = (select public.app_meu_codigo()) or (select public.app_is_admin()));

create policy pedidos_apagar_admin on public.pedidos
  for delete to authenticated
  using ((select public.app_is_admin()));

-- ---------------------------------------------------------------------------
-- Gatilhos de ultimo_pedido em clientes
-- ---------------------------------------------------------------------------
-- Os dois gatilhos AFTER INSERT de pedidos atualizam clientes.ultimo_pedido.
-- Rodavam com o papel de quem insere; com "alterar clientes = admin", o
-- update deles cairia em 0 linhas para o vendedor, sem erro, e a coluna
-- pararia de andar. Viram SECURITY DEFINER com search_path fixo; a logica
-- e a mesma de antes.

create or replace function public.atualizar_ultimo_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.clientes
     set ultimo_pedido = new.datahora
   where id = new.cliente_id
     and (ultimo_pedido is null or new.datahora > ultimo_pedido);
  return new;
end;
$$;

create or replace function public.set_cliente_ultimo_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.clientes
     set ultimo_pedido = greatest(coalesce(ultimo_pedido, 'epoch'::timestamptz), new.datahora)
   where id = new.cliente_id;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Senhas em texto puro e o login antigo do controle
-- ---------------------------------------------------------------------------

drop function public.app_migrar_admin(text, bigint);
drop table public.acesso_admin;
alter table public.vendedores drop column senha;

-- ---------------------------------------------------------------------------
-- Nada para anon
-- ---------------------------------------------------------------------------
-- "all tables" inclui as views (clientes_com_ultimo_pedido,
-- pedidos_with_created_at). Funcoes: anon tambem herda EXECUTE de PUBLIC,
-- entao sai de PUBLIC tambem; as que o app chama ja tem grant explicito
-- para authenticated (fase 1). TRUNCATE nao passa pela RLS: sai de
-- authenticated.

revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
revoke execute on all functions in schema public from public;
revoke truncate on all tables in schema public from authenticated;

-- O Supabase da grant a anon em tudo que o postgres criar depois em public
-- (default privilege por schema): o revoke por schema desfaz isso.
--
-- EXECUTE para PUBLIC e outra historia: vem do default global do Postgres,
-- e default por schema so SOMA ao global, nunca tira. Um revoke "in schema"
-- dele nao faz nada, e anon (que herda de PUBLIC) executaria toda funcao
-- nova. Tem que ser o global, sem "in schema". Ele vale para funcoes que o
-- postgres criar em qualquer schema; as que precisam de grant para
-- authenticated o recebem explicito, como na fase 1.
--
-- TRUNCATE nao passa pela RLS: tabelas novas tambem nascem sem ele para
-- authenticated.
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke truncate on tables from authenticated;
