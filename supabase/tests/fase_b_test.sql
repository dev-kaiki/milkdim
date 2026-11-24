-- Teste da fase B (codigo do QR, etiqueta impressa e entrega pelo QR). Roda
-- dentro de begin ... rollback, montado por quem executa: este arquivo nao
-- abre nem fecha transacao. Cada bloco da raise exception quando a
-- verificacao falha.
--
-- Ordem:  begin; <fase A.2, se ainda nao aplicada>; <fase B>;
--         <fase_a_test.sql>; <fase_a2_test.sql>; <este arquivo>; rollback;
-- (fases 1, 3 e A ja aplicadas no banco.) Os testes das fases A e A.2
-- rodam depois da migracao da fase B para mostrar que os gatilhos
-- continuam fazendo o que faziam. Numeros 'teste-fb-*', vendedores
-- -905/-906/-907.
--
-- Tudo roda numa transacao so, entao now() e o mesmo instante em todo o
-- teste: "preenchido pelo servidor" se confere como = now(). Para ver se
-- um valor foi mantido ou re-carimbado, o bloco 3 poe uma data do passado.
--
-- Personagens, criados aqui e desfeitos no rollback (nenhuma senha: o hash
-- e de um valor aleatorio que ninguem conhece):
--   A    vendedor comum, codigo -905: le e entrega pedido de B pelo QR
--   B    vendedor comum, codigo -906: dono dos pedidos de teste
--   adm  vendedor com is_admin, codigo -907: usa o Controle
--   sem  conta autenticada sem linha em vendedores (so no JWT)
--
-- Pedidos de teste, todos de B (id e codigo_qr guardados em teste.fb_p* e
-- teste.fb_qr*):
--   p1  salvo: insert com codigo_qr/etiqueta falsos; o app nao muda as
--       colunas; etiqueta marcada pelo Controle
--   p2  finalizado com assinatura: o app nao muda as colunas; pedido_por_qr
--       devolve so numero e status
--   p3  cancelado que a entrega assinada de B vence: o codigo fica
--   p4  pronto: A le e entrega pelo QR; a segunda entrega da MD002
--   p5  salvo: A recebe MD003; depois B entrega pelo QR
--   p6  cancelado: A recebe MD004; depois B entrega pelo QR
--   p7  salvo: assinatura vazia da 22023 e nada muda
--   p8  entregue sem assinatura e sem marca de manual (como os pedidos
--       antigos de producao): o dono recebe MD002 e nada muda
--   p9  "Marcar como entregue" pelo Controle (manual, sem assinatura): A
--       recebe MD002; o dono entrega pelo QR e a entrega assinada vence

-- 0. Preparacao, sem JWT (como o SQL Editor): contas Auth e vendedores.
--    Ids negativos em vendedores, como nos testes anteriores.
select set_config('request.jwt.claims', '', true);
do $$
declare
  v_uid uuid;
begin
  v_uid := public.app_criar_usuario_auth(
    'teste_fb_a@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-905, '-905', 'Teste fase B vendedor A', false, v_uid);
  perform set_config('teste.fb_uid_a', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fb_b@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-906, '-906', 'Teste fase B vendedor B', false, v_uid);
  perform set_config('teste.fb_uid_b', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fb_adm@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-907, '-907', 'Teste fase B admin', true, v_uid);
  perform set_config('teste.fb_uid_adm', v_uid::text, true);

  perform set_config('teste.fb_uid_sem', gen_random_uuid()::text, true);
end $$;

-- 1. B insere pedidos mandando codigo_qr e etiqueta: o servidor troca o
--    codigo e zera a etiqueta.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_b'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_id    bigint;
  v_r     record;
  v_falso uuid := gen_random_uuid();
begin
  if public.app_meu_codigo() is distinct from '-906' then
    raise exception 'FALHA: app_meu_codigo = % (esperado -906)', public.app_meu_codigo();
  end if;
  if public.app_is_admin() then
    raise exception 'FALHA: B aparece como admin';
  end if;

  -- 1a. p1 salvo, com codigo_qr e etiqueta_impressa_* falsos.
  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              cliente_nome_fantasia, cliente_cidade,
                              produtos, total, status, datahora,
                              codigo_qr, etiqueta_impressa_em, etiqueta_impressa_por)
  values ('teste-fb-1', '-906', 'Teste B', 'Cliente teste', 'Fantasia teste', 'Cidade teste',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
          10, 'salvo', now(), v_falso, timestamptz '2000-01-01', 'X')
  returning id into v_id;

  select * into v_r from public.pedidos where id = v_id;
  if v_r.codigo_qr is null or v_r.codigo_qr = v_falso then
    raise exception 'FALHA: insert aceitou o codigo_qr do app (%)', v_r.codigo_qr;
  end if;
  if v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: insert aceitou etiqueta_impressa_* do app (%, %)',
      v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por;
  end if;
  perform set_config('teste.fb_p1', v_id::text, true);
  perform set_config('teste.fb_qr1', v_r.codigo_qr::text, true);

  -- 1b. Os outros pedidos de B, tambem com codigo falso (o mesmo em todos:
  --     se o servidor aceitasse, o indice unico recusaria o segundo).
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura, codigo_qr)
  values ('teste-fb-2', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'finalizado', now(), decode('02', 'hex'), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p2', v_r.id::text, true);
  perform set_config('teste.fb_qr2', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-3', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'cancelado', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p3', v_r.id::text, true);
  perform set_config('teste.fb_qr3', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              cliente_nome_fantasia, cliente_cidade, cliente_telefone,
                              cliente_cpf_cnpj, produtos, total, status, datahora, codigo_qr)
  values ('teste-fb-4', '-906', 'Teste B', 'Cliente teste', 'Fantasia teste', 'Cidade teste',
          '0000', '000',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10},
            {"nome":"Queijo","preco":30,"qtd":3,"subtotal":90}]'::jsonb,
          100, 'salvo', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p4', v_r.id::text, true);
  perform set_config('teste.fb_qr4', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-5', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'salvo', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p5', v_r.id::text, true);
  perform set_config('teste.fb_qr5', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-6', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'cancelado', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p6', v_r.id::text, true);
  perform set_config('teste.fb_qr6', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-7', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'salvo', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p7', v_r.id::text, true);
  perform set_config('teste.fb_qr7', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-8', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'salvo', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p8', v_r.id::text, true);
  perform set_config('teste.fb_qr8', v_r.codigo_qr::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr)
  values ('teste-fb-9', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'salvo', now(), v_falso)
  returning id, codigo_qr into v_r;
  perform set_config('teste.fb_p9', v_r.id::text, true);
  perform set_config('teste.fb_qr9', v_r.codigo_qr::text, true);

  -- Nove codigos diferentes, nenhum igual ao falso.
  select * into v_r from (
    select count(distinct codigo_qr) as n, bool_or(codigo_qr = v_falso) as falso
      from public.pedidos where numero like 'teste-fb-%' and vendedor_codigo = '-906') t;
  if v_r.n <> 9 or v_r.falso then
    raise exception 'FALHA: % codigos distintos de 9, algum igual ao do app: %', v_r.n, v_r.falso;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 1c. Com a marca das RPCs (milkdim.acao_controle = '1'), o gatilho de
--     insercao nao mexe no codigo nem na etiqueta.
do $$
declare
  v_dado uuid := gen_random_uuid();
  v_r    record;
begin
  perform set_config('milkdim.acao_controle', '1', true);
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, total, status, datahora,
                              codigo_qr, etiqueta_impressa_em, etiqueta_impressa_por)
  values ('teste-fb-marca', '-906', 'Cliente teste', 1, 'salvo', now(),
          v_dado, timestamptz '2000-01-01', 'Y')
  returning codigo_qr, etiqueta_impressa_em, etiqueta_impressa_por into v_r;
  perform set_config('milkdim.acao_controle', '', true);

  if v_r.codigo_qr is distinct from v_dado
     or v_r.etiqueta_impressa_em is distinct from timestamptz '2000-01-01'
     or v_r.etiqueta_impressa_por is distinct from 'Y' then
    raise exception 'FALHA: com a marca, o gatilho de insercao mexeu no codigo/etiqueta (%, %, %)',
      v_r.codigo_qr, v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por;
  end if;
end $$;

-- 2. B tenta mudar codigo_qr e etiqueta_impressa_* por UPDATE: os valores
--    antigos ficam, em pedido salvo, finalizado e na entrega assinada que
--    vence um cancelado.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_b'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r     record;
  v_antes timestamptz;
begin
  -- 2a. Salvo (p1): o UPDATE passa (datahora muda), as tres colunas nao.
  select datahora into v_antes from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  update public.pedidos
     set codigo_qr             = gen_random_uuid(),
         etiqueta_impressa_em  = timestamptz '2000-01-01',
         etiqueta_impressa_por = 'X',
         datahora              = datahora + interval '1 hour'
   where id = current_setting('teste.fb_p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.datahora is distinct from v_antes + interval '1 hour' then
    raise exception 'FALHA: preparo de 2a: o UPDATE de p1 nao passou';
  end if;
  if v_r.codigo_qr is distinct from current_setting('teste.fb_qr1')::uuid then
    raise exception 'FALHA: UPDATE do app mudou codigo_qr de pedido salvo';
  end if;
  if v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: UPDATE do app gravou etiqueta_impressa_* em pedido salvo';
  end if;

  -- 2b. Salvo (p1) pelo upsert do app, mandando codigo_qr = excluded: fica.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, codigo_qr, etiqueta_impressa_por)
  values ('teste-fb-1', '-906', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
          10, 'salvo', now(), gen_random_uuid(), 'X')
  on conflict (numero, vendedor_codigo) do update
     set codigo_qr             = excluded.codigo_qr,
         etiqueta_impressa_por = 'X',
         status                = excluded.status;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.codigo_qr is distinct from current_setting('teste.fb_qr1')::uuid
     or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: upsert do app mudou codigo_qr/etiqueta de pedido salvo';
  end if;

  -- 2c. Finalizado (p2).
  update public.pedidos
     set codigo_qr             = gen_random_uuid(),
         etiqueta_impressa_em  = timestamptz '2000-01-01',
         etiqueta_impressa_por = 'X'
   where id = current_setting('teste.fb_p2')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p2')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.codigo_qr is distinct from current_setting('teste.fb_qr2')::uuid
     or v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: UPDATE do app mudou codigo_qr/etiqueta de pedido finalizado (%, %, %)',
      v_r.codigo_qr, v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por;
  end if;

  -- 2d. Cancelado (p3) entregue com assinatura (o gatilho aceita a versao
  --     do vendedor): mesmo assim o codigo e a etiqueta ficam.
  update public.pedidos
     set status                = 'finalizado',
         assinatura            = decode('03', 'hex'),
         codigo_qr             = gen_random_uuid(),
         etiqueta_impressa_em  = timestamptz '2000-01-01',
         etiqueta_impressa_por = 'X'
   where id = current_setting('teste.fb_p3')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p3')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.finalizado_por is distinct from '-906' then
    raise exception 'FALHA: preparo de 2d: entrega assinada nao venceu o cancelado (status %, por %)',
      v_r.status, v_r.finalizado_por;
  end if;
  if v_r.codigo_qr is distinct from current_setting('teste.fb_qr3')::uuid
     or v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: entrega assinada sobre cancelado mudou codigo_qr/etiqueta';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3. pedido_marcar_etiqueta.
-- 3-preparo. Sem JWT, com a marca: alterado_em de p1 no passado, para ver
--    que a RPC nao re-carimba. p8 vira um pedido como os antigos de
--    producao: entregue, sem assinatura, sem marca de manual
--    (finalizado_manual e not null desde a fase A: false), de ontem.
do $$
declare
  v_r record;
begin
  perform set_config('milkdim.acao_controle', '1', true);
  update public.pedidos
     set alterado_em = now() - interval '2 hours'
   where id = current_setting('teste.fb_p1')::bigint;
  update public.pedidos
     set status            = 'finalizado',
         assinatura        = null,
         finalizado_manual = false,
         finalizado_em     = now() - interval '1 day',
         finalizado_por    = '-906'
   where id = current_setting('teste.fb_p8')::bigint;
  perform set_config('milkdim.acao_controle', '', true);

  select * into v_r from public.pedidos where id = current_setting('teste.fb_p8')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.assinatura is not null
     or v_r.finalizado_manual or v_r.finalizado_em is distinct from now() - interval '1 day' then
    raise exception 'FALHA: preparo de p8 nao gravou (status %, manual %, em %)',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_em;
  end if;
end $$;

-- 3a. Vendedor comum (A): 42501, antes de olhar o alterado_em (o nulo
--     aqui nao bate com o de p1, entao a ordem dos testes aparece).
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_a'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
begin
  begin
    perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p1')::bigint, null);
    raise exception 'FALHA: vendedor comum executou pedido_marcar_etiqueta';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3b. Admin (Controle): grava quando e quem; status e alterado_em ficam.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_adm'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: adm nao aparece como admin';
  end if;

  -- A recusa do 3a nao mexeu em p1.
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null then
    raise exception 'FALHA: p1 ganhou etiqueta depois da recusa a vendedor comum';
  end if;

  -- p4 fica pronto (para os blocos 4 a 7).
  perform public.pedido_marcar_pronto(current_setting('teste.fb_p4')::bigint);

  -- p9: "Marcar como entregue" pelo Controle (para os blocos 8 e 10).
  perform public.pedido_finalizar_manual(current_setting('teste.fb_p9')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p9')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.assinatura is not null or v_r.finalizado_por is distinct from '-907' then
    raise exception 'FALHA: preparo de p9: status %, manual %, por %',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por;
  end if;

  -- alterado_em velho (a tela nao viu a ultima alteracao) ou nulo (a tela
  -- viu o pedido antes de qualquer alteracao): MD001 e nada muda.
  begin
    perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p1')::bigint,
                                          now() - interval '3 hours');
    raise exception 'FALHA: pedido_marcar_etiqueta aceitou alterado_em velho';
  exception when sqlstate 'MD001' then
    null;
  end;
  begin
    perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p1')::bigint, null);
    raise exception 'FALHA: pedido_marcar_etiqueta aceitou alterado_em nulo de pedido alterado';
  exception when sqlstate 'MD001' then
    null;
  end;
  begin
    perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p1')::bigint);
    raise exception 'FALHA: pedido_marcar_etiqueta sem alterado_em aceitou pedido alterado';
  exception when sqlstate 'MD001' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.etiqueta_impressa_em is not null or v_r.etiqueta_impressa_por is not null
     or v_r.status is distinct from 'salvo'
     or v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: recusa MD001 mexeu em p1 (em %, por %, status %, alterado_em %)',
      v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por, v_r.status, v_r.alterado_em;
  end if;
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada depois da recusa MD001';
  end if;

  -- Pedido salvo (p1) com o alterado_em certo: marca.
  perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p1')::bigint,
                                        now() - interval '2 hours');
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.etiqueta_impressa_em is distinct from now()
     or v_r.etiqueta_impressa_por is distinct from '-907' then
    raise exception 'FALHA: marcar etiqueta: em %, por % (esperado now(), -907)',
      v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por;
  end if;
  if v_r.status is distinct from 'salvo'
     or v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: marcar etiqueta mudou status/alterado_em (%, %)',
      v_r.status, v_r.alterado_em;
  end if;
  if v_r.codigo_qr is distinct from current_setting('teste.fb_qr1')::uuid then
    raise exception 'FALHA: marcar etiqueta mudou codigo_qr';
  end if;
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle continua ligada depois de pedido_marcar_etiqueta';
  end if;

  -- Pedido pronto (p4), nunca alterado: nulo = nulo conta como igual;
  -- continua pronto.
  perform public.pedido_marcar_etiqueta(current_setting('teste.fb_p4')::bigint, null);
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p4')::bigint;
  if v_r.status is distinct from 'pronto' or v_r.alterado_em is not null
     or v_r.etiqueta_impressa_em is distinct from now()
     or v_r.etiqueta_impressa_por is distinct from '-907' then
    raise exception 'FALHA: marcar etiqueta de pronto: status %, alterado_em %, em %, por %',
      v_r.status, v_r.alterado_em, v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por;
  end if;

  -- Id inexistente: P0002 (antes do MD001, com ou sem alterado_em).
  begin
    perform public.pedido_marcar_etiqueta(-1);
    raise exception 'FALHA: pedido_marcar_etiqueta aceitou id inexistente';
  exception when sqlstate 'P0002' then
    null;
  end;
  begin
    perform public.pedido_marcar_etiqueta(-1, now());
    raise exception 'FALHA: pedido_marcar_etiqueta aceitou id inexistente com alterado_em';
  exception when sqlstate 'P0002' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3c. B tenta apagar a etiqueta e trocar o codigo de p1: ficam.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_b'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  update public.pedidos
     set etiqueta_impressa_em  = null,
         etiqueta_impressa_por = null,
         codigo_qr             = gen_random_uuid()
   where id = current_setting('teste.fb_p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p1')::bigint;
  if v_r.etiqueta_impressa_em is distinct from now()
     or v_r.etiqueta_impressa_por is distinct from '-907'
     or v_r.codigo_qr is distinct from current_setting('teste.fb_qr1')::uuid then
    raise exception 'FALHA: UPDATE do app apagou a etiqueta ou trocou o codigo (%, %, %)',
      v_r.etiqueta_impressa_em, v_r.etiqueta_impressa_por, v_r.codigo_qr;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 4 a 8. Vendedor A com pedidos de B.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_a'),
                    'role', 'authenticated')::text, true);
set local role authenticated;

-- 4. pedido_por_qr.
do $$
declare
  v jsonb;
  v_n bigint;
begin
  if public.app_meu_codigo() is distinct from '-905' then
    raise exception 'FALHA: app_meu_codigo = % (esperado -905)', public.app_meu_codigo();
  end if;

  -- 4a. Pedido pronto de B: exatamente as 10 chaves.
  v := public.pedido_por_qr(current_setting('teste.fb_qr4')::uuid);
  select count(*) into v_n from jsonb_object_keys(v);
  if v_n <> 10 or not (v ?& array['id', 'numero', 'status', 'vendedor_codigo', 'vendedor_nome',
                                  'cliente_nome', 'cliente_nome_fantasia', 'cliente_cidade',
                                  'itens', 'do_proprio_vendedor']) then
    raise exception 'FALHA: pedido_por_qr devolveu as chaves %',
      (select array_agg(k) from jsonb_object_keys(v) k);
  end if;
  if v -> 'do_proprio_vendedor' is distinct from 'false'::jsonb then
    raise exception 'FALHA: do_proprio_vendedor = % (esperado false)', v -> 'do_proprio_vendedor';
  end if;
  if (v ->> 'id')::bigint is distinct from current_setting('teste.fb_p4')::bigint
     or v ->> 'numero' is distinct from 'teste-fb-4'
     or v ->> 'status' is distinct from 'pronto'
     or v ->> 'vendedor_codigo' is distinct from '-906'
     or v ->> 'vendedor_nome' is distinct from 'Teste B'
     or v ->> 'cliente_nome' is distinct from 'Cliente teste'
     or v ->> 'cliente_nome_fantasia' is distinct from 'Fantasia teste'
     or v ->> 'cliente_cidade' is distinct from 'Cidade teste' then
    raise exception 'FALHA: pedido_por_qr devolveu valores errados: %', v - 'itens';
  end if;

  -- 4b. itens: nome e quantidade (de quantidade ou, na falta, de qtd), sem preco.
  if exists (select 1 from jsonb_array_elements(v -> 'itens') e where e ? 'preco') then
    raise exception 'FALHA: itens de pedido_por_qr trazem preco';
  end if;
  if v -> 'itens' is distinct from
     '[{"nome":"Leite","quantidade":2},{"nome":"Queijo","quantidade":3}]'::jsonb then
    raise exception 'FALHA: itens de pedido_por_qr = %', v -> 'itens';
  end if;

  -- 4c. Pedido finalizado (p2): so numero e status.
  v := public.pedido_por_qr(current_setting('teste.fb_qr2')::uuid);
  if v is distinct from '{"numero":"teste-fb-2","status":"finalizado"}'::jsonb then
    raise exception 'FALHA: pedido_por_qr de finalizado devolveu %', v;
  end if;

  -- 4d. Codigo desconhecido: P0002.
  begin
    perform public.pedido_por_qr(gen_random_uuid());
    raise exception 'FALHA: pedido_por_qr aceitou codigo desconhecido';
  exception when sqlstate 'P0002' then
    null;
  end;
end $$;

-- 5. A continua sem ver os pedidos de B por select.
do $$
declare
  v_n bigint;
begin
  select count(*) into v_n from public.pedidos
   where vendedor_codigo = '-906'
      or codigo_qr = current_setting('teste.fb_qr4')::uuid
      or id = current_setting('teste.fb_p4')::bigint;
  if v_n <> 0 then
    raise exception 'FALHA: A ve % pedido(s) de B por select', v_n;
  end if;
end $$;

-- 6. A entrega o pedido pronto de B (o resto da conferencia, que A nao
--    consegue ler, vem no bloco 6b, sem JWT).
do $$
declare
  v   jsonb;
  v_n bigint;
begin
  v := public.pedido_entregar_por_qr(current_setting('teste.fb_qr4')::uuid, decode('0a0b', 'hex'));
  select count(*) into v_n from jsonb_object_keys(v);
  if v_n <> 3 or not (v ?& array['id', 'numero', 'finalizado_em']) then
    raise exception 'FALHA: pedido_entregar_por_qr devolveu %', v;
  end if;
  if (v ->> 'id')::bigint is distinct from current_setting('teste.fb_p4')::bigint
     or v ->> 'numero' is distinct from 'teste-fb-4'
     or (v ->> 'finalizado_em')::timestamptz is distinct from now() then
    raise exception 'FALHA: pedido_entregar_por_qr devolveu valores errados: %', v;
  end if;

  -- Entregue: pedido_por_qr passa a devolver so numero e status.
  v := public.pedido_por_qr(current_setting('teste.fb_qr4')::uuid);
  if v is distinct from '{"numero":"teste-fb-4","status":"finalizado"}'::jsonb then
    raise exception 'FALHA: pedido_por_qr depois da entrega devolveu %', v;
  end if;
end $$;

-- 7. Repetir a entrega: MD002.
do $$
begin
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr4')::uuid, decode('0c', 'hex'));
    raise exception 'FALHA: segunda entrega de p4 aceita';
  exception when sqlstate 'MD002' then
    null;
  end;
end $$;

-- 8. Quem nao e o dono: salvo (p5) da MD003, cancelado (p6) da MD004,
--    entregue pelo Controle sem assinatura (p9) da MD002.
do $$
begin
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr5')::uuid, decode('0d', 'hex'));
    raise exception 'FALHA: A entregou pedido salvo de B';
  exception when sqlstate 'MD003' then
    null;
  end;
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr6')::uuid, decode('0e', 'hex'));
    raise exception 'FALHA: A entregou pedido cancelado de B';
  exception when sqlstate 'MD004' then
    null;
  end;
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr9')::uuid, decode('1e', 'hex'));
    raise exception 'FALHA: A entregou pedido de B finalizado manual pelo Controle';
  exception when sqlstate 'MD002' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 6b e 8b. Sem JWT: como ficaram p4, p5 e p6.
do $$
declare
  v_r record;
begin
  -- 6b. p4: entregue por A, continua de B.
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p4')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.finalizado_por is distinct from '-905'
     or v_r.finalizado_em is distinct from now()
     or v_r.finalizado_manual then
    raise exception 'FALHA: entrega por A: status %, por %, em %, manual %',
      v_r.status, v_r.finalizado_por, v_r.finalizado_em, v_r.finalizado_manual;
  end if;
  if v_r.assinatura is distinct from decode('0a0b', 'hex') then
    raise exception 'FALHA: entrega por A nao gravou a assinatura enviada (ou a 2a entrega trocou)';
  end if;
  if v_r.vendedor_codigo is distinct from '-906' then
    raise exception 'FALHA: entrega por A mudou vendedor_codigo para %', v_r.vendedor_codigo;
  end if;
  if v_r.codigo_qr is distinct from current_setting('teste.fb_qr4')::uuid
     or v_r.pronto_por is distinct from '-907'
     or v_r.etiqueta_impressa_por is distinct from '-907' then
    raise exception 'FALHA: entrega por A mexeu em codigo_qr/pronto_por/etiqueta';
  end if;

  -- 8b. p5 e p6 nao mudaram.
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p5')::bigint;
  if v_r.status is distinct from 'salvo' or v_r.assinatura is not null
     or v_r.finalizado_em is not null or v_r.finalizado_por is not null then
    raise exception 'FALHA: p5 mudou depois do MD003 (status %)', v_r.status;
  end if;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p6')::bigint;
  if v_r.status is distinct from 'cancelado' or v_r.assinatura is not null
     or v_r.finalizado_em is not null or v_r.finalizado_por is not null then
    raise exception 'FALHA: p6 mudou depois do MD004 (status %)', v_r.status;
  end if;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p9')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.assinatura is not null or v_r.finalizado_por is distinct from '-907' then
    raise exception 'FALHA: p9 mudou depois do MD002 de A (status %, manual %, por %)',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por;
  end if;
end $$;

-- 9 a 11. O dono (B) pelo QR.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_b'),
                    'role', 'authenticated')::text, true);
set local role authenticated;

-- 9. B entrega o proprio pedido salvo (p5): aceita.
do $$
declare
  v   jsonb;
  v_r record;
begin
  v := public.pedido_por_qr(current_setting('teste.fb_qr5')::uuid);
  if v -> 'do_proprio_vendedor' is distinct from 'true'::jsonb or v ->> 'status' is distinct from 'salvo' then
    raise exception 'FALHA: pedido_por_qr do proprio pedido: proprio %, status %',
      v -> 'do_proprio_vendedor', v ->> 'status';
  end if;

  v := public.pedido_entregar_por_qr(current_setting('teste.fb_qr5')::uuid, decode('09', 'hex'));
  if (v ->> 'id')::bigint is distinct from current_setting('teste.fb_p5')::bigint then
    raise exception 'FALHA: entrega do proprio salvo devolveu %', v;
  end if;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p5')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.finalizado_por is distinct from '-906'
     or v_r.finalizado_em is distinct from now()
     or v_r.assinatura is distinct from decode('09', 'hex') then
    raise exception 'FALHA: entrega do proprio salvo: status %, por %, em %',
      v_r.status, v_r.finalizado_por, v_r.finalizado_em;
  end if;

  -- O dono tambem nao entrega de novo um pedido entregue com assinatura (p4).
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr4')::uuid, decode('0f', 'hex'));
    raise exception 'FALHA: o dono entregou de novo um pedido ja entregue';
  exception when sqlstate 'MD002' then
    null;
  end;
end $$;

-- 10. B entrega o proprio pedido cancelado (p6): a entrega assinada vence.
do $$
declare
  v_r record;
begin
  perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr6')::uuid, decode('10', 'hex'));
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p6')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.finalizado_por is distinct from '-906'
     or v_r.finalizado_em is distinct from now()
     or v_r.assinatura is distinct from decode('10', 'hex') then
    raise exception 'FALHA: entrega do proprio cancelado: status %, por %, em %',
      v_r.status, v_r.finalizado_por, v_r.finalizado_em;
  end if;
  if v_r.cancelado_em is distinct from now() or v_r.cancelado_por is distinct from '-906' then
    raise exception 'FALHA: entrega do proprio cancelado apagou o cancelamento (%, %)',
      v_r.cancelado_em, v_r.cancelado_por;
  end if;
end $$;

-- 10b. Pedido como os antigos de producao (p8: entregue, sem assinatura,
--      sem marca de manual): o dono recebe MD002 (nao 55000) e nada muda.
do $$
declare
  v_r record;
begin
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr8')::uuid, decode('18', 'hex'));
    raise exception 'FALHA: o dono entregou de novo um pedido antigo ja entregue';
  exception when sqlstate 'MD002' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p8')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.assinatura is not null
     or v_r.finalizado_manual
     or v_r.finalizado_em is distinct from now() - interval '1 day'
     or v_r.finalizado_por is distinct from '-906' then
    raise exception 'FALHA: p8 mudou depois do MD002 (assinatura %, em %, por %)',
      v_r.assinatura, v_r.finalizado_em, v_r.finalizado_por;
  end if;
end $$;

-- 10c. Entregue pelo Controle sem assinatura (p9): o dono entrega pelo QR
--      e a entrega assinada vence. finalizado_por passa a ser o dono.
do $$
declare
  v   jsonb;
  v_r record;
begin
  v := public.pedido_entregar_por_qr(current_setting('teste.fb_qr9')::uuid, decode('19', 'hex'));
  if (v ->> 'id')::bigint is distinct from current_setting('teste.fb_p9')::bigint
     or (v ->> 'finalizado_em')::timestamptz is distinct from now() then
    raise exception 'FALHA: entrega do dono sobre manual devolveu %', v;
  end if;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p9')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.finalizado_manual
     or v_r.finalizado_por is distinct from '-906'
     or v_r.finalizado_em is distinct from now()
     or v_r.assinatura is distinct from decode('19', 'hex') then
    raise exception 'FALHA: entrega do dono sobre manual: status %, manual %, por %, em %',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por, v_r.finalizado_em;
  end if;
end $$;

-- 11. Assinatura vazia ou nula: 22023, e p7 nao muda.
do $$
declare
  v_r record;
begin
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr7')::uuid, '\x'::bytea);
    raise exception 'FALHA: entrega com assinatura vazia aceita';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr7')::uuid, null);
    raise exception 'FALHA: entrega com assinatura nula aceita';
  exception when sqlstate '22023' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.fb_p7')::bigint;
  if v_r.status is distinct from 'salvo' or v_r.assinatura is not null or v_r.finalizado_em is not null then
    raise exception 'FALHA: p7 mudou depois da assinatura recusada (status %)', v_r.status;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 12. Autenticado sem vendedor: 42501 nas duas RPCs de vendedor.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fb_uid_sem'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
begin
  if public.app_meu_codigo() is not null or public.app_is_admin() then
    raise exception 'FALHA: conta sem vendedor tem codigo (%) ou e admin', public.app_meu_codigo();
  end if;
  begin
    perform public.pedido_por_qr(current_setting('teste.fb_qr7')::uuid);
    raise exception 'FALHA: conta sem vendedor executou pedido_por_qr';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.pedido_entregar_por_qr(current_setting('teste.fb_qr7')::uuid, decode('11', 'hex'));
    raise exception 'FALHA: conta sem vendedor executou pedido_entregar_por_qr';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 13. Estrutura e permissoes.
do $$
declare
  v_n    bigint;
  v_fn   regprocedure;
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  -- Colunas novas com o tipo certo; codigo_qr obrigatorio com default.
  select count(*) into v_n from information_schema.columns
   where table_schema = 'public' and table_name = 'pedidos'
     and ((column_name = 'codigo_qr' and data_type = 'uuid' and is_nullable = 'NO'
           and column_default like '%gen_random_uuid()%')
       or (column_name = 'etiqueta_impressa_em' and data_type = 'timestamp with time zone')
       or (column_name = 'etiqueta_impressa_por' and data_type = 'text'));
  if v_n <> 3 then
    raise exception 'FALHA: % de 3 colunas novas com o tipo esperado', v_n;
  end if;

  -- Indice unico do codigo.
  select count(*) into v_n from pg_index
   where indexrelid = to_regclass('public.pedidos_codigo_qr_key')
     and indrelid = 'public.pedidos'::regclass and indisunique;
  if v_n <> 1 then
    raise exception 'FALHA: indice unico pedidos_codigo_qr_key nao existe';
  end if;

  -- Gatilhos no lugar, e os de ultimo pedido intactos.
  select count(*) into v_n from pg_trigger
   where tgrelid = 'public.pedidos'::regclass and not tgisinternal
     and tgname in ('trg_pedidos_antes_inserir', 'trg_pedidos_antes_alterar',
                    'trg_atualizar_ultimo_pedido', 'trg_pedidos_update_cliente_ultimo');
  if v_n <> 4 then
    raise exception 'FALHA: % de 4 gatilhos esperados em pedidos', v_n;
  end if;

  -- RPCs novas: security definer com search_path vazio; authenticated
  -- executa, anon e PUBLIC nao.
  -- pedido_marcar_etiqueta so existe com (bigint, timestamptz).
  if to_regprocedure('public.pedido_marcar_etiqueta(bigint)') is not null then
    raise exception 'FALHA: pedido_marcar_etiqueta(bigint) ainda existe';
  end if;
  select count(*) into v_n from pg_proc
   where proname = 'pedido_marcar_etiqueta'
     and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception 'FALHA: % versoes de pedido_marcar_etiqueta (esperada 1)', v_n;
  end if;

  foreach v_fn in array array['public.pedido_marcar_etiqueta(bigint, timestamptz)'::regprocedure,
                              'public.pedido_por_qr(uuid)'::regprocedure,
                              'public.pedido_entregar_por_qr(uuid, bytea)'::regprocedure]
  loop
    select count(*) into v_n from pg_proc
     where oid = v_fn and prosecdef and proconfig @> array['search_path=""'];
    if v_n <> 1 then
      raise exception 'FALHA: % sem security definer / search_path vazio', v_fn;
    end if;
    if not has_function_privilege('authenticated', v_fn::oid, 'execute') then
      raise exception 'FALHA: authenticated sem EXECUTE em %', v_fn;
    end if;
    if has_function_privilege('anon', v_fn::oid, 'execute') then
      raise exception 'FALHA: anon executa %', v_fn;
    end if;
    select count(*) into v_n
      from pg_proc p, aclexplode(p.proacl) a
     where p.oid = v_fn and a.grantee = 0 and a.privilege_type = 'EXECUTE';
    if v_n <> 0 then
      raise exception 'FALHA: PUBLIC executa %', v_fn;
    end if;
  end loop;

  -- Funcoes de gatilho continuam fora do alcance do app.
  if has_function_privilege('authenticated', 'public.pedidos_antes_inserir()', 'execute')
     or has_function_privilege('authenticated', 'public.pedidos_antes_alterar()', 'execute')
     or has_function_privilege('anon', 'public.pedidos_antes_inserir()', 'execute')
     or has_function_privilege('anon', 'public.pedidos_antes_alterar()', 'execute') then
    raise exception 'FALHA: funcao de gatilho executavel por authenticated/anon';
  end if;

  -- Nenhum codigo repetido.
  select count(*) - count(distinct codigo_qr) into v_n from public.pedidos;
  if v_n <> 0 then
    raise exception 'FALHA: % codigo(s) repetido(s)', v_n;
  end if;

  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada no fim do teste';
  end if;
end $$;

select 'fase_b_test: OK' as resultado;
