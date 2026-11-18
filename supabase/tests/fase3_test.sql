-- Teste da fase 3 (fecha o banco). Roda dentro de begin ... rollback,
-- montado por quem executa: este arquivo nao abre nem fecha transacao.
-- Cada bloco da raise exception quando a verificacao falha.
--
-- Ordem:  begin; <fase 1>; fase3_preparo.sql; <fase 3>; <este arquivo>; rollback;
--
-- A guarda do inicio da fase 3 se testa em rodadas proprias, porque o erro
-- dela derruba a transacao inteira: cada uma deve terminar no erro indicado.
--   begin; <fase 1>; <fase 3>; rollback;
--     -> Fase 3 cancelada: nenhuma conta de admin no Auth...
--   begin; <fase 1>; select public.app_migrar_admin('teste_admin_1', 1); <fase 3>; rollback;
--     -> Fase 3 cancelada: 1 conta(s) de admin no Auth para 2 senha(s) ativa(s)...
--   begin; <fase 1>; fase3_preparo.sql;
--          update auth.users set email = 'outro@milkdim.local'
--           where id = (select auth_user_id from public.vendedores where codigo = '0002');
--          <fase 3>; rollback;
--     -> Fase 3 cancelada: vendedor(es) ligados a conta com e-mail diferente...
--   begin; <fase 1>; fase3_preparo.sql;
--          insert into public.vendedores (id, codigo, nome) values (-5, 'teste_sem_conta', 'X');
--          <fase 3>; rollback;
--     -> Fase 3 cancelada: vendedor(es) sem conta no Auth: teste_sem_conta (id -5).
--
-- Ids passados na mao (overriding / max + 1): nextval nao volta no rollback,
-- e um teste que so le nao deve deixar buraco nas sequencias de producao.

-- 0. Preparacao, sem JWT: uma das contas de admin que fase3_preparo.sql
--    criou com app_migrar_admin, e os proximos ids livres.
select set_config('teste.admin_uid',
  (select id::text from auth.users
    where email like 'teste\_admin\_%@milkdim.local'
      and raw_app_meta_data ->> 'role' = 'admin'
    order by email limit 1), true);
do $$
begin
  if current_setting('teste.admin_uid', true) is null
     or current_setting('teste.admin_uid', true) = '' then
    raise exception 'FALHA: sem conta de admin de teste (rodar fase3_preparo.sql antes da fase 3)';
  end if;
end $$;
select set_config('teste.uid_0002',
  (select auth_user_id::text from public.vendedores where codigo = '0002'), true);
select set_config('teste.total_pedidos', (select count(*)::text from public.pedidos), true);
select set_config('teste.total_vendedores', (select count(*)::text from public.vendedores), true);
select set_config('teste.prox_pedido',  (select (max(id) + 1)::text from public.pedidos), true);
select set_config('teste.prox_cliente', (select (max(id) + 1)::text from public.clientes), true);
select set_config('teste.prox_produto', (select (coalesce(max(id), 0) + 1)::text from public.produtos), true);

-- O app insere cliente sem id (default nextval): authenticated precisa de
-- USAGE na sequencia para isso continuar funcionando.
do $$
begin
  if not has_sequence_privilege('authenticated', 'public.clientes_id_seq', 'USAGE') then
    raise exception 'FALHA: authenticated sem USAGE em clientes_id_seq (insert de cliente quebraria)';
  end if;
end $$;

-- 1. Vendedor 0002 logado.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.uid_0002'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_n       bigint;
  v_id      integer;
  v_total   numeric;
begin
  -- Ve so os proprios pedidos, e ve algum.
  select count(*) into v_n from public.pedidos where vendedor_codigo is distinct from '0002';
  if v_n <> 0 then
    raise exception 'FALHA: vendedor 0002 ve % pedido(s) de outros vendedores', v_n;
  end if;
  select count(*) into v_n from public.pedidos;
  if v_n = 0 then
    raise exception 'FALHA: vendedor 0002 nao ve nenhum pedido proprio';
  end if;
  select count(*) into v_n from public.pedidos_with_created_at where vendedor_codigo is distinct from '0002';
  if v_n <> 0 then
    raise exception 'FALHA: view pedidos_with_created_at mostra % pedido(s) de outros', v_n;
  end if;

  -- Pedido com o codigo de outro vendedor: recusado.
  begin
    insert into public.pedidos (id, numero, vendedor_codigo, total)
    overriding system value
    values (current_setting('teste.prox_pedido')::bigint, 'teste-x', '0003', 10);
    raise exception 'FALHA: vendedor 0002 gravou pedido como 0003';
  exception when sqlstate '42501' then
    null;
  end;

  -- Cliente novo: insere e le o id de volta.
  insert into public.clientes (id, nome)
  values (current_setting('teste.prox_cliente')::integer, 'teste')
  returning id into v_id;
  if v_id is distinct from current_setting('teste.prox_cliente')::integer then
    raise exception 'FALHA: insert de cliente nao devolveu o id';
  end if;

  -- Pedido proprio: insere; reenviar a mesma chave (upsert do app) atualiza.
  insert into public.pedidos (id, numero, vendedor_codigo, total, cliente_id, datahora)
  overriding system value
  values (current_setting('teste.prox_pedido')::bigint, 'teste-y', '0002', 10,
          v_id, timestamptz '2999-01-01');

  insert into public.pedidos (id, numero, vendedor_codigo, total, cliente_id, datahora)
  overriding system value
  values (current_setting('teste.prox_pedido')::bigint, 'teste-y', '0002', 10,
          v_id, timestamptz '2999-01-01')
  on conflict (numero, vendedor_codigo) do update set total = 1;

  select total into v_total from public.pedidos where numero = 'teste-y' and vendedor_codigo = '0002';
  if v_total is distinct from 1 then
    raise exception 'FALHA: upsert do pedido proprio nao atualizou (total = %)', v_total;
  end if;

  -- Upsert com o codigo de outro vendedor: recusado.
  begin
    insert into public.pedidos (id, numero, vendedor_codigo, total)
    overriding system value
    values (current_setting('teste.prox_pedido')::bigint + 1, 'teste-y', '0003', 10)
    on conflict (numero, vendedor_codigo) do update set total = 1;
    raise exception 'FALHA: upsert gravou pedido como 0003';
  exception when sqlstate '42501' then
    null;
  end;

  -- Mudar o proprio pedido para outro vendedor: recusado.
  begin
    update public.pedidos set vendedor_codigo = '0003' where numero = 'teste-y';
    raise exception 'FALHA: vendedor passou o proprio pedido para 0003';
  exception when sqlstate '42501' then
    null;
  end;

  -- Vendedor nao apaga pedido.
  delete from public.pedidos where numero = 'teste-y';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor apagou % pedido(s)', v_n;
  end if;

  -- Vendedor nao altera cliente.
  update public.clientes set nome = 'x';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor alterou % cliente(s)', v_n;
  end if;

  -- Vendedor nao cadastra produto.
  begin
    insert into public.produtos (id, nome)
    values (current_setting('teste.prox_produto')::integer, 'x');
    raise exception 'FALHA: vendedor cadastrou produto';
  exception when sqlstate '42501' then
    null;
  end;

  -- Vendedores: so a propria linha, e nao altera nada nela.
  select count(*) into v_n from public.vendedores;
  if v_n <> 1 then
    raise exception 'FALHA: vendedor 0002 ve % linha(s) de vendedores', v_n;
  end if;

  -- codigo fora do grant de update: recusado antes da RLS.
  begin
    update public.vendedores set codigo = '0003' where auth_user_id = auth.uid();
    raise exception 'FALHA: vendedor trocou o proprio codigo';
  exception when sqlstate '42501' then
    null;
  end;

  update public.vendedores set nome = 'x';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor alterou % linha(s) de vendedores', v_n;
  end if;

  begin
    insert into public.vendedores (id, codigo, nome) values (-3, '7777', 'Z');
    raise exception 'FALHA: vendedor inseriu linha em vendedores';
  exception when sqlstate '42501' then
    null;
  end;

  delete from public.vendedores;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor apagou % linha(s) de vendedores', v_n;
  end if;

  if public.app_meu_codigo() is distinct from '0002' then
    raise exception 'FALHA: app_meu_codigo mudou para %', public.app_meu_codigo();
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 1b. O gatilho de pedidos ainda atualiza clientes.ultimo_pedido quando
--     quem insere e vendedor (que nao pode alterar clientes).
do $$
begin
  if (select ultimo_pedido from public.clientes
       where id = current_setting('teste.prox_cliente')::integer)
     is distinct from timestamptz '2999-01-01' then
    raise exception 'FALHA: ultimo_pedido do cliente nao foi atualizado pelo pedido do vendedor';
  end if;
  if exists (select 1 from public.vendedores where codigo = '0002' and nome = 'x') then
    raise exception 'FALHA: nome do vendedor 0002 mudou';
  end if;
end $$;

-- 2. Chave anonima: sem acesso a nada.
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_rel text;
begin
  foreach v_rel in array array['pedidos', 'clientes', 'produtos', 'vendedores',
                               'clientes_com_ultimo_pedido', 'pedidos_with_created_at'] loop
    begin
      execute format('select count(*) from public.%I', v_rel);
      raise exception 'FALHA: anon leu %', v_rel;
    exception when sqlstate '42501' then
      null;
    end;
  end loop;

  begin
    insert into public.pedidos (id, numero, vendedor_codigo)
    overriding system value
    values (current_setting('teste.prox_pedido')::bigint + 2, 'teste-z', '0002');
    raise exception 'FALHA: anon gravou pedido';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.app_is_admin();
    raise exception 'FALHA: anon executou app_is_admin';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3. Admin (app_metadata.role = admin): ve tudo, apaga pedido.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.admin_uid'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
set local role authenticated;
do $$
declare
  v_n bigint;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: app_is_admin falso para o admin';
  end if;

  select count(*) into v_n from public.pedidos;
  if v_n <> current_setting('teste.total_pedidos')::bigint + 1 or v_n < 373 then
    raise exception 'FALHA: admin ve % pedidos, esperado % (372+ e o teste-y)',
      v_n, current_setting('teste.total_pedidos')::bigint + 1;
  end if;

  select count(*) into v_n from public.vendedores;
  if v_n <> current_setting('teste.total_vendedores')::bigint then
    raise exception 'FALHA: admin ve % vendedores, esperado %', v_n, current_setting('teste.total_vendedores');
  end if;

  update public.vendedores set nome = nome, anotacao = anotacao where codigo = '0002';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FALHA: admin nao alterou vendedor';
  end if;

  -- Nem admin troca o codigo (moveria os pedidos do vendedor) nem mexe em
  -- ativo direto (isso e app_definir_ativo_vendedor, que bane a conta junto).
  begin
    update public.vendedores set codigo = 'x' where codigo = '0002';
    raise exception 'FALHA: admin trocou o codigo do vendedor';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    update public.vendedores set ativo = false where codigo = '0002';
    raise exception 'FALHA: admin mudou ativo direto na tabela';
  exception when sqlstate '42501' then
    null;
  end;

  update public.clientes set nome = 'teste2' where id = current_setting('teste.prox_cliente')::integer;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FALHA: admin nao alterou cliente';
  end if;

  insert into public.produtos (id, nome) values (current_setting('teste.prox_produto')::integer, 'x');

  delete from public.pedidos where numero = 'teste-y' and vendedor_codigo = '0002';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FALHA: admin nao apagou teste-y (% linhas)', v_n;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 4. Estrutura: senha, acesso_admin e app_migrar_admin sumiram; nenhuma
--    politica para anon/public; anon sem privilegio em nada de public.
--    Inclui objetos criados DEPOIS da fase 3 pelo postgres (default
--    privileges): uma funcao e uma tabela de teste, criadas aqui.
create function public.teste_default_priv() returns integer
language sql as 'select 1';
create table public.teste_default_priv_t (x integer);

do $$
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;
  if has_function_privilege('anon', 'public.teste_default_priv()', 'execute') then
    raise exception 'FALHA: anon executa funcao nova de public (default privilege de EXECUTE para PUBLIC continua)';
  end if;
  if has_table_privilege('anon', 'public.teste_default_priv_t', 'select, insert, update, delete, truncate') then
    raise exception 'FALHA: anon com privilegio em tabela nova de public';
  end if;
  if has_table_privilege('authenticated', 'public.teste_default_priv_t', 'truncate') then
    raise exception 'FALHA: authenticated com TRUNCATE em tabela nova de public';
  end if;
end $$;

do $$
declare
  v_n bigint;
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'vendedores' and column_name = 'senha') then
    raise exception 'FALHA: coluna vendedores.senha ainda existe';
  end if;
  if to_regclass('public.acesso_admin') is not null then
    raise exception 'FALHA: tabela acesso_admin ainda existe';
  end if;
  if to_regprocedure('public.app_migrar_admin(text, bigint)') is not null then
    raise exception 'FALHA: app_migrar_admin ainda existe';
  end if;
  if exists (select 1 from pg_trigger
              where tgrelid = 'public.vendedores'::regclass and tgname = 'trg_vendedores_proteger') is not true then
    raise exception 'FALHA: gatilho trg_vendedores_proteger sumiu';
  end if;

  select count(*) into v_n from pg_policies
   where schemaname = 'public' and roles <> array['authenticated']::name[];
  if v_n <> 0 then
    raise exception 'FALHA: % politica(s) nao restritas a authenticated', v_n;
  end if;

  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and case when c.relkind in ('r', 'v', 'm', 'p')
              then has_table_privilege('anon', c.oid, 'select, insert, update, delete')
              else false end;
  if v_n <> 0 then
    raise exception 'FALHA: anon com privilegio em % tabela(s)/view(s)', v_n;
  end if;

  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     -- case: sem ele o planner pode chamar has_sequence_privilege em
     -- objeto que nao e sequencia, e isso da erro.
     and case when c.relkind = 'S' then has_sequence_privilege('anon', c.oid, 'usage') else false end;
  if v_n <> 0 then
    raise exception 'FALHA: anon com USAGE em % sequencia(s)', v_n;
  end if;

  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 0 then
    raise exception 'FALHA: anon executa % funcao(oes) de public', v_n;
  end if;
end $$;

select 'fase3_test: OK' as resultado;
