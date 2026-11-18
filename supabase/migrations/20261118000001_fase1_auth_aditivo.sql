-- MilkDim, fase 1 da troca para Supabase Auth: so ACRESCENTA.
--
-- Nao mexe em nenhuma politica, nao apaga coluna nem tabela. Os apps atuais
-- continuam funcionando com isto aplicado (eles nao leem as colunas novas e
-- as politicas abertas seguem no lugar). O fechamento e a fase 3.
--
-- Padrao copiado das funcoes app_*_tecnico do projeto Smi_App, trocando
-- @smi.local por @milkdim.local e tecnicos por vendedores.
--
-- Este arquivo nao abre nem fecha transacao: quem aplica decide.

-- ---------------------------------------------------------------------------
-- Colunas novas em vendedores
-- ---------------------------------------------------------------------------

alter table public.vendedores
  add column auth_user_id uuid unique references auth.users(id) on delete set null,
  add column is_admin boolean not null default false;

-- ---------------------------------------------------------------------------
-- Constraint unica (numero, vendedor_codigo) em pedidos
-- ---------------------------------------------------------------------------
-- O banco ja tem o indice unico pedidos_numero_vendedor_uk nessas colunas
-- (criado fora do repositorio). Em vez de um segundo indice igual, o
-- existente vira a constraint; o ON CONFLICT (numero, vendedor_codigo) do
-- app continua achando o mesmo indice. Sem ele, cria do zero.

do $$
begin
  if exists (select 1 from pg_constraint
              where conrelid = 'public.pedidos'::regclass
                and conname = 'pedidos_numero_vendedor_key') then
    return;
  end if;

  if exists (select 1 from pg_index i
               join pg_class c on c.oid = i.indexrelid
              where i.indrelid = 'public.pedidos'::regclass
                and c.relname = 'pedidos_numero_vendedor_uk'
                and i.indisunique and i.indisvalid and i.indpred is null
                and i.indexprs is null and i.indnatts = 2
                and i.indkey[0] = (select attnum from pg_attribute
                                    where attrelid = 'public.pedidos'::regclass
                                      and attname = 'numero')
                and i.indkey[1] = (select attnum from pg_attribute
                                    where attrelid = 'public.pedidos'::regclass
                                      and attname = 'vendedor_codigo')) then
    alter table public.pedidos
      add constraint pedidos_numero_vendedor_key unique using index pedidos_numero_vendedor_uk;
  else
    alter table public.pedidos
      add constraint pedidos_numero_vendedor_key unique (numero, vendedor_codigo);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- app_criar_usuario_auth: interna. Grava auth.users + auth.identities.
-- ---------------------------------------------------------------------------
-- Recebe o hash pronto (crypt feito por quem chama), para servir tanto a
-- criacao com senha nova quanto a copia das senhas que ja existem.

create or replace function public.app_criar_usuario_auth(
  p_email     text,
  p_hash      text,
  p_app_meta  jsonb,
  p_user_meta jsonb,
  p_ativo     boolean
) returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := gen_random_uuid();
begin
  if p_email is null or p_hash is null then
    raise exception 'E-mail e senha sao obrigatorios.';
  end if;

  if exists (select 1 from auth.users where email = p_email) then
    raise exception 'Ja existe um acesso com o e-mail %.', p_email;
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, banned_until,
    -- O GoTrue le estas oito para string, nao para ponteiro: um NULO
    -- quebra a leitura do usuario antes de conferir a senha, e o erro
    -- que chega e "Database error querying schema".
    confirmation_token, recovery_token,
    email_change, email_change_token_new, email_change_token_current,
    phone_change, phone_change_token, reauthentication_token
    -- phone fica de fora de proposito: tem unicidade, e vazio so cabe
    -- uma vez no banco. Nulo cabe sempre.
  ) values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    p_email,
    p_hash,
    now(), now(), now(),
    coalesce(p_app_meta, '{"provider":"email","providers":["email"]}'::jsonb),
    coalesce(p_user_meta, '{}'::jsonb),
    -- Data distante em vez de 'infinity': o GoTrue compara banned_until
    -- com now(), e uma data comum nao depende de como cada versao trata
    -- o valor infinito.
    case when coalesce(p_ativo, true) then null else timestamptz '2999-12-31' end,
    '', '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, provider, identity_data,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_uid, v_uid::text, 'email',
    jsonb_build_object('sub', v_uid::text, 'email', p_email,
                       'email_verified', true, 'phone_verified', false),
    now(), now(), now()
  );

  return v_uid;
end;
$$;

revoke execute on function public.app_criar_usuario_auth(text, text, jsonb, jsonb, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- app_is_admin / app_meu_codigo
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER para poderem ser usadas nas politicas da fase 3 sem
-- cair na RLS de vendedores (e sem recursao).

create or replace function public.app_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Sem JWT (SQL Editor, psql) nao ha role nas claims, e quem chega assim
  -- ja passou por credencial de administrador do projeto. A chave anonima
  -- nao cai neste caso: ela traz role = 'anon'.
  select
    coalesce(auth.jwt() ->> 'role', '') = ''
    -- raw_app_meta_data: o proprio usuario nao consegue alterar.
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
    or exists (
      select 1 from public.vendedores v
       where v.auth_user_id = auth.uid() and v.is_admin
    );
$$;

create or replace function public.app_meu_codigo()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select v.codigo from public.vendedores v where v.auth_user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Gestao de vendedores (so admin)
-- ---------------------------------------------------------------------------

create or replace function public.app_criar_vendedor(
  p_codigo   text,
  p_nome     text,
  p_senha    text,
  p_anotacao text    default null,
  p_ativo    boolean default true,
  p_is_admin boolean default false
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email    text;
  v_uid      uuid;
  v_vendedor integer;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para cadastrar vendedor.' using errcode = '42501';
  end if;

  p_codigo := nullif(btrim(p_codigo), '');
  p_nome   := nullif(btrim(p_nome), '');

  if p_codigo is null or p_nome is null then
    raise exception 'Codigo e nome sao obrigatorios.';
  end if;

  if p_senha is null or length(p_senha) < 6 then
    raise exception 'A senha precisa ter ao menos 6 caracteres.';
  end if;

  -- Mesma regra que os dois aplicativos usam no login.
  v_email := lower(p_codigo) || '@milkdim.local';

  if exists (select 1 from public.vendedores where codigo = p_codigo) then
    raise exception 'Ja existe vendedor com o codigo %.', p_codigo;
  end if;

  v_uid := public.app_criar_usuario_auth(
    v_email,
    extensions.crypt(p_senha, extensions.gen_salt('bf')),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('codigo', p_codigo, 'nome', p_nome),
    coalesce(p_ativo, true)
  );

  insert into public.vendedores (codigo, nome, anotacao, ativo, is_admin, auth_user_id)
  values (p_codigo, p_nome, nullif(btrim(p_anotacao), ''),
          coalesce(p_ativo, true), coalesce(p_is_admin, false), v_uid)
  returning id into v_vendedor;

  return v_vendedor;
end;
$$;

create or replace function public.app_alterar_senha_vendedor(p_codigo text, p_senha text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para alterar senha.' using errcode = '42501';
  end if;

  if p_senha is null or length(p_senha) < 6 then
    raise exception 'A senha precisa ter ao menos 6 caracteres.';
  end if;

  -- Preferir o vinculo gravado na linha; sem ele, o e-mail montado do codigo.
  -- So conta de vendedor: sem linha em vendedores, nada de montar e-mail,
  -- porque as contas de admin moram no mesmo dominio @milkdim.local.
  select v.auth_user_id into v_uid
    from public.vendedores v
   where v.codigo = btrim(p_codigo);

  if not found then
    raise exception 'Nao ha vendedor com o codigo %.', p_codigo;
  end if;

  -- Linha sem vinculo: o e-mail montado do codigo, nunca uma conta de admin.
  if v_uid is null then
    select u.id into v_uid
      from auth.users u
     where u.email = lower(btrim(p_codigo)) || '@milkdim.local'
       and coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')),
         updated_at = now()
   where id = v_uid;

  if not found then
    raise exception 'Nao ha acesso cadastrado para o codigo %.', p_codigo;
  end if;
end;
$$;

create or replace function public.app_definir_ativo_vendedor(p_codigo text, p_ativo boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para alterar o vendedor.' using errcode = '42501';
  end if;

  update public.vendedores
     set ativo = coalesce(p_ativo, false)
   where codigo = btrim(p_codigo)
  returning auth_user_id into v_uid;

  if not found then
    raise exception 'Nao ha vendedor com o codigo %.', p_codigo;
  end if;

  if v_uid is null then
    select u.id into v_uid
      from auth.users u
     where u.email = lower(btrim(p_codigo)) || '@milkdim.local'
       and coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin';
  end if;

  -- Data distante em vez de 'infinity' (ver app_criar_usuario_auth).
  update auth.users
     set banned_until = case when coalesce(p_ativo, false) then null
                             else timestamptz '2999-12-31' end,
         updated_at = now()
   where id = v_uid;
end;
$$;

create or replace function public.app_excluir_vendedor(p_codigo text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  if not public.app_is_admin() then
    raise exception 'Sem permissao para excluir vendedor.' using errcode = '42501';
  end if;

  -- Preferir o auth_user_id gravado na linha: se o codigo ja foi corrigido
  -- alguma vez, o e-mail antigo continua sendo o verdadeiro, e monta-lo a
  -- partir do codigo apagaria o usuario errado, ou nenhum.
  select v.auth_user_id into v_uid
    from public.vendedores v
   where v.codigo = btrim(p_codigo);

  if not found then
    raise exception 'Nao ha vendedor com o codigo %.', p_codigo;
  end if;

  -- O vinculo pode faltar (acesso criado a mao no painel e nunca ligado).
  -- Sem esta volta, a linha sumiria e o acesso continuaria vivo.
  if v_uid is null then
    select u.id into v_uid
      from auth.users u
     where u.email = lower(btrim(p_codigo)) || '@milkdim.local'
       and coalesce(u.raw_app_meta_data ->> 'role', '') <> 'admin';
  end if;

  delete from public.vendedores where codigo = btrim(p_codigo);

  if v_uid is not null then
    -- auth.identities e auth.sessions tem ON DELETE CASCADE a partir de
    -- auth.users, entao vao junto.
    delete from auth.users where id = v_uid;
  end if;
end;
$$;

-- Supabase da EXECUTE a anon por padrao em funcoes novas de public; aqui so
-- usuario autenticado chama (e as de gestao ainda conferem app_is_admin).
revoke execute on function public.app_is_admin() from public, anon;
revoke execute on function public.app_meu_codigo() from public, anon;
revoke execute on function public.app_criar_vendedor(text, text, text, text, boolean, boolean) from public, anon;
revoke execute on function public.app_alterar_senha_vendedor(text, text) from public, anon;
revoke execute on function public.app_definir_ativo_vendedor(text, boolean) from public, anon;
revoke execute on function public.app_excluir_vendedor(text) from public, anon;

grant execute on function public.app_is_admin() to authenticated;
grant execute on function public.app_meu_codigo() to authenticated;
grant execute on function public.app_criar_vendedor(text, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.app_alterar_senha_vendedor(text, text) to authenticated;
grant execute on function public.app_definir_ativo_vendedor(text, boolean) to authenticated;
grant execute on function public.app_excluir_vendedor(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Protecao de is_admin e auth_user_id enquanto as politicas abertas existem
-- ---------------------------------------------------------------------------
-- Ate a fase 3, vendedores ainda tem politicas FOR ALL USING (true) para
-- public. Sem isto, um vendedor logado se faria admin
-- (update ... set is_admin = true) e a chave anonima poderia apontar o
-- auth_user_id de um vendedor para a conta de um admin, que
-- app_excluir_vendedor apagaria depois. Os apps atuais nunca escrevem nessas
-- duas colunas, entao continuam funcionando.
--
-- So o que mexe em is_admin/auth_user_id passa por app_is_admin(); o resto
-- (nome, senha, ativo, anotacao pelo controle antigo) segue como hoje.
-- A chave anonima nunca passa: current_setting('role') e o papel que o
-- PostgREST ligou (anon/authenticated) e nao muda dentro de SECURITY DEFINER.

create or replace function public.app_proteger_vendedores()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.is_admin or new.auth_user_id is not null then
      if current_setting('role', true) = 'anon' or not public.app_is_admin() then
        raise exception 'Sem permissao para definir is_admin ou auth_user_id.'
          using errcode = '42501';
      end if;
    end if;
  elsif new.is_admin is distinct from old.is_admin
     or new.auth_user_id is distinct from old.auth_user_id then
    if current_setting('role', true) = 'anon' or not public.app_is_admin() then
      raise exception 'Sem permissao para alterar is_admin ou auth_user_id.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.app_proteger_vendedores() from public, anon, authenticated;

create trigger trg_vendedores_proteger
  before insert or update on public.vendedores
  for each row execute function public.app_proteger_vendedores();

-- ---------------------------------------------------------------------------
-- app_migrar_admin: cria a conta de admin a partir de acesso_admin
-- ---------------------------------------------------------------------------
-- So roda sem JWT (SQL Editor / MCP). O nome de usuario de cada senha e
-- escolhido pelo dono na hora de aplicar; a senha e copiada da tabela, nunca
-- escrita no repositorio. Esta migracao NAO chama esta funcao.

create or replace function public.app_migrar_admin(p_usuario text, p_acesso_admin_id bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_senha text;
  v_ativo boolean;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> '' then
    raise exception 'app_migrar_admin so roda pelo SQL Editor, sem JWT.' using errcode = '42501';
  end if;

  p_usuario := nullif(btrim(p_usuario), '');
  if p_usuario is null then
    raise exception 'Usuario e obrigatorio.';
  end if;

  -- Quem passa o e-mail inteiro nao ganha @milkdim.local duplicado.
  v_email := lower(p_usuario);
  if position('@' in v_email) = 0 then
    v_email := v_email || '@milkdim.local';
  end if;

  select a.senha, a.ativo into v_senha, v_ativo
    from public.acesso_admin a
   where a.id = p_acesso_admin_id;

  if not found then
    raise exception 'Nao ha acesso_admin com id %.', p_acesso_admin_id;
  end if;

  if v_senha is null or v_senha = '' then
    raise exception 'acesso_admin id % sem senha.', p_acesso_admin_id;
  end if;

  return public.app_criar_usuario_auth(
    v_email,
    extensions.crypt(v_senha, extensions.gen_salt('bf')),
    '{"provider":"email","providers":["email"],"role":"admin"}'::jsonb,
    jsonb_build_object('usuario', p_usuario),
    coalesce(v_ativo, true)
  );
end;
$$;

revoke execute on function public.app_migrar_admin(text, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Contas Auth dos vendedores que ja existem, com a senha que ja usam
-- ---------------------------------------------------------------------------
-- Copia a senha atual como esta (o 0003 tem 4 caracteres): o GoTrue nao
-- confere tamanho no signInWithPassword, entao ninguem precisa trocar.
-- Vendedor inativo ja nasce banido.

do $$
declare
  v     record;
  v_uid uuid;
begin
  for v in
    select id, codigo, nome, senha, ativo
      from public.vendedores
     where auth_user_id is null
     order by id
  loop
    if nullif(btrim(v.codigo), '') is null then
      raise exception 'Vendedor id % sem codigo; corrigir antes de migrar.', v.id;
    end if;
    if v.senha is null or v.senha = '' then
      raise exception 'Vendedor % sem senha; corrigir antes de migrar.', v.codigo;
    end if;

    v_uid := public.app_criar_usuario_auth(
      lower(btrim(v.codigo)) || '@milkdim.local',
      extensions.crypt(v.senha, extensions.gen_salt('bf')),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('codigo', v.codigo, 'nome', v.nome),
      coalesce(v.ativo, true)
    );

    update public.vendedores set auth_user_id = v_uid where id = v.id;
  end loop;
end $$;
