-- Teste da fase D (saidas e categorias de saida do financeiro). Roda dentro
-- de begin ... rollback, montado por quem executa: este arquivo nao abre nem
-- fecha transacao. Cada bloco da raise exception quando a verificacao falha.
--
-- Teste de pre-aplicacao: o bloco 1 espera exatamente 8 categorias, entao so
-- vale antes de a migracao ir de verdade para o banco (dentro do rollback).
--
-- Ordem:  begin; <fase D, 20261125000001_fase_d_saidas.sql>; <este arquivo>;
--         rollback;
-- (fases 1 a B ja aplicadas no banco.) Vendedores -910 e -911.
--
-- Tudo roda numa transacao so, entao now() e o mesmo instante em todo o
-- teste: "preenchido pelo servidor" se confere como = now(). Para ver se um
-- valor foi forjado, o bloco 2 manda uma data do passado.
--
-- Personagens, criados aqui e desfeitos no rollback (nenhuma senha: o hash
-- e de um valor aleatorio que ninguem conhece):
--   vend  vendedor comum, codigo -910
--   adm   vendedor com is_admin, codigo -911
--   sem   conta autenticada sem linha em vendedores (so no JWT)
--
-- A fase so le pedidos: o bloco 0 guarda a contagem e a soma dos totais e o
-- bloco 8 confere que nada mudou.

-- 0. Preparacao, sem JWT (como o SQL Editor): contas Auth, vendedores e a
--    foto dos pedidos.
select set_config('request.jwt.claims', '', true);
do $$
declare
  v_uid uuid;
  v_n   bigint;
  v_s   numeric;
begin
  v_uid := public.app_criar_usuario_auth(
    'teste_fd_vend@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-910, '-910', 'Teste fase D vendedor', false, v_uid);
  perform set_config('teste.fd_uid_vend', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fd_adm@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-911, '-911', 'Teste fase D admin', true, v_uid);
  perform set_config('teste.fd_uid_adm', v_uid::text, true);

  perform set_config('teste.fd_uid_sem', gen_random_uuid()::text, true);

  select count(*), coalesce(sum(total), 0) into v_n, v_s from public.pedidos;
  perform set_config('teste.fd_ped_n', v_n::text, true);
  perform set_config('teste.fd_ped_soma', v_s::text, true);
end $$;

-- 1. As 8 categorias iniciais: nomes, ordem de 1 a 8, todas ativas.
do $$
declare
  v_n     bigint;
  v_nomes text[];
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  select count(*) into v_n from public.categorias_saida;
  if v_n <> 8 then
    raise exception 'FALHA: % categorias (esperadas 8)', v_n;
  end if;

  select array_agg(nome order by ordem) into v_nomes from public.categorias_saida;
  if v_nomes is distinct from array[
       'Matéria-prima', 'Embalagens', 'Combustível/entrega', 'Salários',
       'Aluguel/contas (água, luz, gás)', 'Impostos', 'Manutenção', 'Outros'] then
    raise exception 'FALHA: categorias iniciais fora de ordem ou com nome errado: %', v_nomes;
  end if;

  select count(*) into v_n from public.categorias_saida
   where ordem between 1 and 8 and ativa;
  if v_n <> 8 then
    raise exception 'FALHA: % de 8 categorias com ordem 1..8 e ativas', v_n;
  end if;

  select count(distinct ordem) into v_n from public.categorias_saida;
  if v_n <> 8 then
    raise exception 'FALHA: ordem repetida nas categorias (% distintas)', v_n;
  end if;
end $$;

-- 2 a 4. Admin (-911).
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fd_uid_adm'),
                    'role', 'authenticated')::text, true);
set local role authenticated;

-- 2. Auditoria: o cliente nao forja criado_*; o update grava alterado_* e
--    mantem criado_*.
do $$
declare
  v_cat bigint;
  v_id  bigint;
  v_r   record;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: adm nao aparece como admin';
  end if;
  if public.app_meu_codigo() is distinct from '-911' then
    raise exception 'FALHA: app_meu_codigo = % (esperado -911)', public.app_meu_codigo();
  end if;

  select id into v_cat from public.categorias_saida where nome = 'Outros';
  if v_cat is null then
    raise exception 'FALHA: admin nao le a categoria Outros';
  end if;
  perform set_config('teste.fd_cat_outros', v_cat::text, true);

  -- 2a. Insert mandando autor e data falsos.
  insert into public.saidas (data, categoria_id, descricao, valor,
                             criado_por, criado_em, alterado_por, alterado_em)
  values (date '2026-11-10', v_cat, 'teste fd', 100.50,
          'forjado', timestamptz '2000-01-01', 'forjado', timestamptz '2000-01-01')
  returning id into v_id;
  perform set_config('teste.fd_saida', v_id::text, true);

  select * into v_r from public.saidas where id = v_id;
  if v_r.criado_por is distinct from '-911' or v_r.criado_em is distinct from now() then
    raise exception 'FALHA: insert aceitou autor/data do cliente (%, %)',
      v_r.criado_por, v_r.criado_em;
  end if;
  if v_r.alterado_por is distinct from '-911' or v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: insert aceitou alterado_* do cliente (%, %)',
      v_r.alterado_por, v_r.alterado_em;
  end if;
  if v_r.valor <> 100.50 or v_r.descricao <> 'teste fd' or v_r.data <> date '2026-11-10' then
    raise exception 'FALHA: insert gravou valores errados (%, %, %)',
      v_r.valor, v_r.descricao, v_r.data;
  end if;

  -- 2b. Update do valor, tentando trocar criado_* e alterado_*.
  update public.saidas
     set valor        = 200.75,
         criado_por   = 'forjado',
         criado_em    = timestamptz '2000-01-01',
         alterado_por = 'forjado',
         alterado_em  = timestamptz '2000-01-01'
   where id = v_id;
  select * into v_r from public.saidas where id = v_id;
  if v_r.valor <> 200.75 then
    raise exception 'FALHA: update nao gravou o valor (%)', v_r.valor;
  end if;
  if v_r.alterado_por is distinct from '-911' or v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: update aceitou alterado_* do cliente (%, %)',
      v_r.alterado_por, v_r.alterado_em;
  end if;
  if v_r.criado_por is distinct from '-911' or v_r.criado_em is distinct from now() then
    raise exception 'FALHA: update mexeu em criado_* (%, %)', v_r.criado_por, v_r.criado_em;
  end if;
end $$;

-- 3. Valor zero ou negativo nao entra: 23514.
do $$
begin
  begin
    insert into public.saidas (data, categoria_id, descricao, valor)
    values (date '2026-11-10', current_setting('teste.fd_cat_outros')::bigint, 'zero', 0);
    raise exception 'FALHA: saida com valor 0 aceita';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    insert into public.saidas (data, categoria_id, descricao, valor)
    values (date '2026-11-10', current_setting('teste.fd_cat_outros')::bigint, 'negativo', -5);
    raise exception 'FALHA: saida com valor negativo aceita';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    update public.saidas set valor = 0 where id = current_setting('teste.fd_saida')::bigint;
    raise exception 'FALHA: update para valor 0 aceito';
  exception when sqlstate '23514' then
    null;
  end;
end $$;

-- 4. Categoria: nome repetido (sem contar caixa nem espacos) da 23505;
--    apagar categoria com saida da 23503.
do $$
declare
  v_n bigint;
begin
  begin
    insert into public.categorias_saida (nome) values (' matéria-PRIMA ');
    raise exception 'FALHA: categoria com nome repetido aceita';
  exception when sqlstate '23505' then
    null;
  end;

  -- Nome vazio (so espacos): 23514.
  begin
    insert into public.categorias_saida (nome) values ('   ');
    raise exception 'FALHA: categoria com nome so de espacos aceita';
  exception when sqlstate '23514' then
    null;
  end;

  -- Categoria nova entra, com os valores padrao.
  insert into public.categorias_saida (nome) values ('Teste fase D');
  select count(*) into v_n from public.categorias_saida
   where nome = 'Teste fase D' and ativa and ordem = 100;
  if v_n <> 1 then
    raise exception 'FALHA: categoria nova sem ativa = true / ordem = 100';
  end if;

  -- Categoria sem saida pode ser apagada.
  delete from public.categorias_saida where nome = 'Teste fase D';
  select count(*) into v_n from public.categorias_saida where nome = 'Teste fase D';
  if v_n <> 0 then
    raise exception 'FALHA: categoria sem saidas nao foi apagada';
  end if;

  -- Categoria com saida (Outros, usada no bloco 2): 23503.
  begin
    delete from public.categorias_saida
     where id = current_setting('teste.fd_cat_outros')::bigint;
    raise exception 'FALHA: categoria com saida foi apagada';
  exception when sqlstate '23503' then
    null;
  end;

  -- Desativar vale.
  update public.categorias_saida set ativa = false
   where id = current_setting('teste.fd_cat_outros')::bigint;
  select count(*) into v_n from public.categorias_saida
   where id = current_setting('teste.fd_cat_outros')::bigint and not ativa;
  if v_n <> 1 then
    raise exception 'FALHA: admin nao conseguiu desativar a categoria';
  end if;
  update public.categorias_saida set ativa = true
   where id = current_setting('teste.fd_cat_outros')::bigint;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 5. Vendedor comum (-910): nao ve nem escreve.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fd_uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_n bigint;
begin
  if public.app_meu_codigo() is distinct from '-910' then
    raise exception 'FALHA: app_meu_codigo = % (esperado -910)', public.app_meu_codigo();
  end if;
  if public.app_is_admin() then
    raise exception 'FALHA: vendedor comum aparece como admin';
  end if;

  -- A saida existe (criada pelo admin), mas o vendedor ve 0 linhas.
  select count(*) into v_n from public.saidas;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum ve % saida(s)', v_n;
  end if;

  select count(*) into v_n from public.categorias_saida;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum ve % categoria(s)', v_n;
  end if;

  -- Insert recusado pela RLS: 42501.
  begin
    insert into public.saidas (data, categoria_id, descricao, valor)
    values (date '2026-11-10', current_setting('teste.fd_cat_outros')::bigint, 'vend', 10);
    raise exception 'FALHA: vendedor comum inseriu saida';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.categorias_saida (nome) values ('Categoria do vendedor');
    raise exception 'FALHA: vendedor comum inseriu categoria';
  exception when sqlstate '42501' then
    null;
  end;

  -- Update e delete: a RLS esconde as linhas, entao nada muda (0 linhas).
  update public.saidas set valor = 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum alterou % saida(s)', v_n;
  end if;
  delete from public.saidas;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum apagou % saida(s)', v_n;
  end if;
  update public.categorias_saida set ativa = false;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum alterou % categoria(s)', v_n;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 6. Autenticado sem vendedor: 0 linhas, e insert recusado.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fd_uid_sem'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_n bigint;
begin
  if public.app_meu_codigo() is not null or public.app_is_admin() then
    raise exception 'FALHA: conta sem vendedor tem codigo (%) ou e admin', public.app_meu_codigo();
  end if;

  select count(*) into v_n from public.saidas;
  if v_n <> 0 then
    raise exception 'FALHA: conta sem vendedor ve % saida(s)', v_n;
  end if;
  select count(*) into v_n from public.categorias_saida;
  if v_n <> 0 then
    raise exception 'FALHA: conta sem vendedor ve % categoria(s)', v_n;
  end if;

  begin
    insert into public.saidas (data, categoria_id, descricao, valor)
    values (date '2026-11-10', current_setting('teste.fd_cat_outros')::bigint, 'sem', 10);
    raise exception 'FALHA: conta sem vendedor inseriu saida';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 7. Anonimo (chave anonima): sem permissao nenhuma, 42501.
select set_config('request.jwt.claims',
  json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_n bigint;
begin
  begin
    select count(*) into v_n from public.saidas;
    raise exception 'FALHA: anon leu saidas';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    select count(*) into v_n from public.categorias_saida;
    raise exception 'FALHA: anon leu categorias_saida';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.saidas (data, categoria_id, descricao, valor)
    values (date '2026-11-10', 1, 'anon', 10);
    raise exception 'FALHA: anon inseriu saida';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 8. Pedidos intactos e estrutura.
do $$
declare
  v_n bigint;
  v_s numeric;
begin
  select count(*), coalesce(sum(total), 0) into v_n, v_s from public.pedidos;
  if v_n <> current_setting('teste.fd_ped_n')::bigint
     or v_s <> current_setting('teste.fd_ped_soma')::numeric then
    raise exception 'FALHA: pedidos mudaram (% / % antes, % / % depois)',
      current_setting('teste.fd_ped_n'), current_setting('teste.fd_ped_soma'), v_n, v_s;
  end if;

  -- RLS ligada nas duas tabelas, uma politica em cada.
  select count(*) into v_n from pg_class
   where oid in ('public.saidas'::regclass, 'public.categorias_saida'::regclass)
     and relrowsecurity;
  if v_n <> 2 then
    raise exception 'FALHA: RLS ligada em % de 2 tabelas', v_n;
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename in ('saidas', 'categorias_saida');
  if v_n <> 2 then
    raise exception 'FALHA: % politicas nas duas tabelas (esperada 1 em cada)', v_n;
  end if;

  -- anon sem nada; authenticated com as quatro operacoes.
  if has_table_privilege('anon', 'public.saidas', 'select')
     or has_table_privilege('anon', 'public.saidas', 'insert')
     or has_table_privilege('anon', 'public.categorias_saida', 'select')
     or has_table_privilege('anon', 'public.categorias_saida', 'insert') then
    raise exception 'FALHA: anon tem permissao em saidas/categorias_saida';
  end if;
  if not (has_table_privilege('authenticated', 'public.saidas', 'select')
          and has_table_privilege('authenticated', 'public.saidas', 'insert')
          and has_table_privilege('authenticated', 'public.saidas', 'update')
          and has_table_privilege('authenticated', 'public.saidas', 'delete')
          and has_table_privilege('authenticated', 'public.categorias_saida', 'select')
          and has_table_privilege('authenticated', 'public.categorias_saida', 'insert')
          and has_table_privilege('authenticated', 'public.categorias_saida', 'update')
          and has_table_privilege('authenticated', 'public.categorias_saida', 'delete')) then
    raise exception 'FALHA: authenticated sem as 4 permissoes nas tabelas';
  end if;
  if has_table_privilege('authenticated', 'public.saidas', 'truncate')
     or has_table_privilege('authenticated', 'public.categorias_saida', 'truncate') then
    raise exception 'FALHA: authenticated pode truncar saidas/categorias_saida';
  end if;

  -- Gatilho de auditoria: security definer, search_path vazio, fora do alcance do app.
  select count(*) into v_n from pg_proc
   where oid = 'public.saidas_auditoria()'::regprocedure
     and prosecdef and proconfig @> array['search_path=""'];
  if v_n <> 1 then
    raise exception 'FALHA: saidas_auditoria sem security definer / search_path vazio';
  end if;
  if has_function_privilege('authenticated', 'public.saidas_auditoria()', 'execute')
     or has_function_privilege('anon', 'public.saidas_auditoria()', 'execute') then
    raise exception 'FALHA: saidas_auditoria executavel por authenticated/anon';
  end if;
  select count(*) into v_n from pg_trigger
   where tgrelid = 'public.saidas'::regclass and not tgisinternal
     and tgname = 'saidas_auditoria';
  if v_n <> 1 then
    raise exception 'FALHA: gatilho saidas_auditoria ausente';
  end if;

  -- Indices.
  if to_regclass('public.saidas_data_idx') is null
     or to_regclass('public.categorias_saida_nome_key') is null then
    raise exception 'FALHA: indice saidas_data_idx ou categorias_saida_nome_key ausente';
  end if;
end $$;

select 'fase_d_test: OK' as resultado;
