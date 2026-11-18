-- Teste da fase 1 (aditiva). Roda dentro de begin ... rollback, montado por
-- quem executa: este arquivo nao abre nem fecha transacao.
-- Cada bloco da raise exception quando a verificacao falha.

-- 1. Todo vendedor ficou ligado a uma conta do Auth.
do $$
declare
  v_sem int;
begin
  select count(*) into v_sem from public.vendedores where auth_user_id is null;
  if v_sem <> 0 then
    raise exception 'FALHA: % vendedor(es) sem auth_user_id', v_sem;
  end if;
end $$;

-- 2. Cada vendedor tem conta <codigo>@milkdim.local com a senha atual,
--    tokens vazios, phone nulo, identidade 'email' e o mesmo id do vinculo.
do $$
declare
  v record;
  u record;
begin
  for v in select codigo, nome, senha, ativo, auth_user_id from public.vendedores loop
    select * into u from auth.users where email = lower(v.codigo) || '@milkdim.local';
    if not found then
      raise exception 'FALHA: sem auth.users para o vendedor %', v.codigo;
    end if;
    if u.id is distinct from v.auth_user_id then
      raise exception 'FALHA: auth_user_id do vendedor % nao aponta para a conta dele', v.codigo;
    end if;
    if u.encrypted_password is distinct from extensions.crypt(v.senha, u.encrypted_password) then
      raise exception 'FALHA: senha do vendedor % nao confere', v.codigo;
    end if;
    if u.confirmation_token is distinct from '' or u.recovery_token is distinct from ''
       or u.email_change is distinct from '' or u.email_change_token_new is distinct from ''
       or u.email_change_token_current is distinct from '' or u.phone_change is distinct from ''
       or u.phone_change_token is distinct from '' or u.reauthentication_token is distinct from '' then
      raise exception 'FALHA: token nulo ou preenchido na conta do vendedor %', v.codigo;
    end if;
    if u.phone is not null then
      raise exception 'FALHA: phone preenchido na conta do vendedor %', v.codigo;
    end if;
    if u.raw_user_meta_data->>'codigo' is distinct from v.codigo then
      raise exception 'FALHA: user_meta.codigo errado para o vendedor %', v.codigo;
    end if;
    if (u.banned_until is null) is distinct from coalesce(v.ativo, true) then
      raise exception 'FALHA: banned_until nao segue ativo para o vendedor %', v.codigo;
    end if;
    if not exists (select 1 from auth.identities i
                    where i.user_id = u.id and i.provider = 'email' and i.provider_id = u.id::text) then
      raise exception 'FALHA: sem auth.identities para o vendedor %', v.codigo;
    end if;
  end loop;
end $$;

-- 3. app_migrar_admin cria a conta de admin com a senha de acesso_admin.
do $$
declare
  v_uid uuid;
  u record;
  v_senha text;
begin
  v_uid := public.app_migrar_admin('teste_admin', 1);
  select * into u from auth.users where id = v_uid;
  if not found or u.email <> 'teste_admin@milkdim.local' then
    raise exception 'FALHA: app_migrar_admin nao criou teste_admin@milkdim.local';
  end if;
  if u.raw_app_meta_data->>'role' is distinct from 'admin' then
    raise exception 'FALHA: conta de admin sem app_metadata.role = admin';
  end if;
  select senha into v_senha from public.acesso_admin where id = 1;
  if u.encrypted_password is distinct from extensions.crypt(v_senha, u.encrypted_password) then
    raise exception 'FALHA: senha do admin nao confere com acesso_admin id 1';
  end if;
  if u.confirmation_token is distinct from '' or u.phone is not null then
    raise exception 'FALHA: conta de admin com token nulo ou phone preenchido';
  end if;
  if not exists (select 1 from auth.identities
                  where user_id = u.id and provider = 'email' and provider_id = u.id::text) then
    raise exception 'FALHA: conta de admin sem auth.identities';
  end if;
end $$;

-- 3b. As funcoes de vendedor nunca alcancam a conta de um admin, nem quando
--     nao ha linha em vendedores, nem quando ha uma linha sem vinculo com o
--     mesmo codigo do usuario admin.
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'teste_admin@milkdim.local'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
do $$
declare
  v_antes text;
  u record;
begin
  select encrypted_password into v_antes
    from auth.users where email = 'teste_admin@milkdim.local';

  begin
    perform public.app_alterar_senha_vendedor('teste_admin', '123456');
    raise exception 'FALHA: app_alterar_senha_vendedor aceitou codigo sem vendedor (conta de admin)';
  exception when others then
    if sqlerrm like 'FALHA:%' then raise; end if;
  end;

  insert into public.vendedores (id, codigo, nome, ativo) values (-2, 'teste_admin', 'Homonimo', true);
  begin
    perform public.app_alterar_senha_vendedor('teste_admin', '123456');
    raise exception 'FALHA: troca de senha caiu na conta do admin pelo e-mail montado';
  exception when others then
    if sqlerrm like 'FALHA:%' then raise; end if;
  end;
  perform public.app_definir_ativo_vendedor('teste_admin', false);
  perform public.app_excluir_vendedor('teste_admin');

  select * into u from auth.users where email = 'teste_admin@milkdim.local';
  if not found then
    raise exception 'FALHA: app_excluir_vendedor apagou a conta do admin homonimo';
  end if;
  if u.encrypted_password is distinct from v_antes then
    raise exception 'FALHA: senha do admin mudou';
  end if;
  if u.banned_until is not null then
    raise exception 'FALHA: app_definir_ativo_vendedor baniu a conta do admin';
  end if;
  if exists (select 1 from public.vendedores where codigo = 'teste_admin') then
    raise exception 'FALHA: linha homonima continua depois de excluir';
  end if;
end $$;
select set_config('request.jwt.claims', '', true);

-- 4. Com JWT (qualquer role), app_migrar_admin recusa.
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'teste_admin@milkdim.local'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
do $$
begin
  begin
    perform public.app_migrar_admin('outro_admin', 2);
    raise exception 'FALHA: app_migrar_admin rodou com JWT';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
select set_config('request.jwt.claims', '', true);

-- 5. Vendedor sem is_admin: nao gerencia vendedores, mas sabe o proprio codigo.
select set_config('request.jwt.claims',
  json_build_object('sub', (select auth_user_id from public.vendedores where codigo = '0002'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
begin
  if public.app_is_admin() then
    raise exception 'FALHA: app_is_admin verdadeiro para vendedor comum';
  end if;
  if public.app_meu_codigo() is distinct from '0002' then
    raise exception 'FALHA: app_meu_codigo devolveu % para o vendedor 0002', public.app_meu_codigo();
  end if;
  begin
    perform public.app_criar_vendedor('9999', 'X', '123456');
    raise exception 'FALHA: vendedor comum conseguiu criar vendedor';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.app_alterar_senha_vendedor('0003', '123456');
    raise exception 'FALHA: vendedor comum conseguiu trocar senha';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.app_definir_ativo_vendedor('0003', false);
    raise exception 'FALHA: vendedor comum conseguiu desativar vendedor';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.app_excluir_vendedor('0003');
    raise exception 'FALHA: vendedor comum conseguiu excluir vendedor';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;

-- 5b. Enquanto as politicas abertas existem, is_admin e auth_user_id so
--     mudam por admin. O resto da linha continua editavel como hoje.
select set_config('teste.admin_uid',
  (select id::text from auth.users where email = 'teste_admin@milkdim.local'), true);
set local role authenticated;
do $$
begin
  update public.vendedores set nome = nome where auth_user_id = auth.uid();
  if not found then
    raise exception 'FALHA: vendedor nao alterou o nome da propria linha (app antigo quebraria)';
  end if;
  begin
    update public.vendedores set is_admin = true where auth_user_id = auth.uid();
    raise exception 'FALHA: vendedor se fez admin';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    update public.vendedores
       set auth_user_id = current_setting('teste.admin_uid')::uuid
     where codigo = '0003';
    raise exception 'FALHA: vendedor reapontou auth_user_id de outro vendedor';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.vendedores (id, codigo, nome, is_admin) values (-1, '8888', 'Y', true);
    raise exception 'FALHA: vendedor inseriu vendedor admin';
  exception when sqlstate '42501' then
    null;
  end;
  if public.app_is_admin() then
    raise exception 'FALHA: vendedor virou admin';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- Chave anonima sem claims (o caso do enunciado)...
set local role anon;
do $$
begin
  update public.vendedores set nome = nome where codigo = '0001';
  if not found then
    raise exception 'FALHA: anon nao alterou nome (app antigo quebraria)';
  end if;
  begin
    update public.vendedores
       set auth_user_id = current_setting('teste.admin_uid')::uuid
     where codigo = '0001';
    raise exception 'FALHA: anon sem claims reapontou auth_user_id';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    update public.vendedores set is_admin = true where codigo = '0001';
    raise exception 'FALHA: anon sem claims marcou is_admin';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.vendedores (id, codigo, nome, is_admin) values (-1, '8888', 'Y', true);
    raise exception 'FALHA: anon sem claims inseriu vendedor admin';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;

-- ...e com as claims que o PostgREST manda para a chave anonima.
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
begin
  begin
    update public.vendedores
       set auth_user_id = current_setting('teste.admin_uid')::uuid
     where codigo = '0001';
    raise exception 'FALHA: anon reapontou auth_user_id';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

do $$
begin
  if exists (select 1 from public.vendedores where is_admin) then
    raise exception 'FALHA: algum vendedor ficou com is_admin';
  end if;
  if exists (select 1 from public.vendedores v
              join auth.users u on u.id = v.auth_user_id
             where u.email <> lower(v.codigo) || '@milkdim.local') then
    raise exception 'FALHA: algum auth_user_id foi reapontado';
  end if;
end $$;

-- 6. JWT da chave anonima (role anon) tambem nao e admin.
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
do $$
begin
  if public.app_is_admin() then
    raise exception 'FALHA: app_is_admin verdadeiro para role anon';
  end if;
end $$;
select set_config('request.jwt.claims', '', true);

-- 7. Admin: senha curta falha, criar funciona, trocar senha funciona, desativar bane.
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'teste_admin@milkdim.local'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
set local role authenticated;
do $$
declare
  v_id integer;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: app_is_admin falso para conta com app_metadata.role = admin';
  end if;
  begin
    perform public.app_criar_vendedor('9999', 'X', '12345');
    raise exception 'FALHA: aceitou senha de 5 caracteres';
  exception
    when sqlstate '42501' then
      raise exception 'FALHA: senha curta caiu em 42501, deveria ser erro de validacao';
    when others then
      if sqlerrm like 'FALHA:%' then raise; end if;
  end;
  v_id := public.app_criar_vendedor('9999', 'X', '123456');
  if v_id is null then
    raise exception 'FALHA: app_criar_vendedor nao devolveu id';
  end if;
  begin
    perform public.app_alterar_senha_vendedor('9999', '12345');
    raise exception 'FALHA: troca aceitou senha de 5 caracteres';
  exception when others then
    if sqlerrm like 'FALHA:%' then raise; end if;
  end;
  perform public.app_alterar_senha_vendedor('9999', '654321');
  perform public.app_definir_ativo_vendedor('9999', false);
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

do $$
declare
  v record;
  u record;
begin
  select * into v from public.vendedores where codigo = '9999';
  if not found or v.auth_user_id is null or v.ativo is distinct from false or v.is_admin then
    raise exception 'FALHA: linha do vendedor 9999 errada apos criar/desativar';
  end if;
  select * into u from auth.users where id = v.auth_user_id;
  if not found or u.email <> '9999@milkdim.local' then
    raise exception 'FALHA: conta do vendedor 9999 nao existe';
  end if;
  if u.banned_until is distinct from timestamptz '2999-12-31' then
    raise exception 'FALHA: banned_until = % apos desativar', u.banned_until;
  end if;
  if u.encrypted_password is distinct from extensions.crypt('654321', u.encrypted_password) then
    raise exception 'FALHA: senha nova do vendedor 9999 nao confere';
  end if;
  if u.confirmation_token is distinct from '' or u.phone is not null then
    raise exception 'FALHA: conta do vendedor 9999 com token nulo ou phone preenchido';
  end if;
  if not exists (select 1 from auth.identities where user_id = u.id and provider = 'email') then
    raise exception 'FALHA: vendedor 9999 sem auth.identities';
  end if;
end $$;

-- 8. Admin exclui: some a linha e a conta.
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'teste_admin@milkdim.local'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
set local role authenticated;
do $$
begin
  perform public.app_excluir_vendedor('9999');
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

do $$
begin
  if exists (select 1 from public.vendedores where codigo = '9999') then
    raise exception 'FALHA: linha do vendedor 9999 continua depois de excluir';
  end if;
  if exists (select 1 from auth.users where email = '9999@milkdim.local') then
    raise exception 'FALHA: conta do vendedor 9999 continua depois de excluir';
  end if;
end $$;

-- 9. Pedido repetido (numero, vendedor_codigo) e recusado pela constraint.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.pedidos'::regclass
                    and conname = 'pedidos_numero_vendedor_key' and contype = 'u') then
    raise exception 'FALHA: constraint pedidos_numero_vendedor_key nao existe';
  end if;
  begin
    -- id e GENERATED ALWAYS. Passar o id na mao (overriding) em vez de
    -- deixar a sequencia gerar: nextval nao volta no rollback.
    insert into public.pedidos (id, numero, vendedor_codigo)
    overriding system value
    select (select max(id) + 1 from public.pedidos), p.numero, p.vendedor_codigo
      from public.pedidos p
     where p.numero is not null and p.vendedor_codigo is not null
     limit 1;
    raise exception 'FALHA: pedido repetido foi aceito';
  exception when sqlstate '23505' then
    null;
  end;
end $$;

-- 10. Codigo com pedidos (de um vendedor ja excluido): app_criar_vendedor
--     recusa, para o vendedor novo nao herdar pedidos alheios.
insert into public.pedidos (id, numero, vendedor_codigo)
overriding system value
values ((select max(id) + 1 from public.pedidos), 'teste-reuso', 'teste_reuso');

select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where email = 'teste_admin@milkdim.local'),
                    'role', 'authenticated',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
set local role authenticated;
do $$
begin
  begin
    perform public.app_criar_vendedor('teste_reuso', 'X', '123456');
    raise exception 'FALHA: app_criar_vendedor aceitou codigo que ja tem pedidos';
  exception when others then
    if sqlerrm not like 'Ja existem pedidos com o codigo teste_reuso.%' then
      raise exception 'FALHA: erro inesperado ao reusar codigo: %', sqlerrm;
    end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

do $$
begin
  if exists (select 1 from public.vendedores where codigo = 'teste_reuso')
     or exists (select 1 from auth.users where email = 'teste_reuso@milkdim.local') then
    raise exception 'FALHA: recusa do codigo reusado deixou linha ou conta para tras';
  end if;
end $$;

select 'fase1_test: OK' as resultado;
