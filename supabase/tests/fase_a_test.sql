-- Teste da fase A (fluxo do pedido). Roda dentro de begin ... rollback,
-- montado por quem executa: este arquivo nao abre nem fecha transacao.
-- Cada bloco da raise exception quando a verificacao falha.
--
-- Ordem:  begin; <fase A>; <este arquivo>; rollback;
-- (fases 1 e 3 ja aplicadas no banco.)
--
-- Tudo roda numa transacao so, entao now() e o mesmo instante em todo o
-- teste: "preenchido pelo servidor" se confere como = now().
--
-- Personagens, criados aqui e desfeitos no rollback (nenhuma senha: o hash
-- e de um valor aleatorio que ninguem conhece):
--   teste_fa_vend   vendedor comum
--   teste_fa_adm    vendedor com is_admin (como 0001, 0002 e 700122), que
--                   usa o app do vendedor e tambem o Controle
--   controle        conta de admin do Controle sem linha em vendedores
--                   (app_metadata.role = admin), so no JWT
--
-- Pedidos de teste (id gerado pelo banco, guardado em teste.p*):
--   p1  salvo do vendedor: alterado_em, finalizar manual, entrega assinada
--   p2  finalizado sem id_aparelho (APK antigo), com auditoria falsa
--   p3  salvo que o proprio vendedor cancela
--   p4  finalizado com assinatura, que nao pode ser substituido
--   p5  salvo do admin, finalizado manual e depois "reaberto" pelo celular
--   p6  salvo cancelado pelo Controle e depois entregue com assinatura
--   p8  salvo finalizado pela conta do Controle sem codigo

-- 0. Preparacao, sem JWT (como o SQL Editor): contas Auth e vendedores.
--    Ids negativos em vendedores, como no fase3_test: nao gasta a sequencia.
select set_config('request.jwt.claims', '', true);
do $$
declare
  v_uid uuid;
begin
  v_uid := public.app_criar_usuario_auth(
    'teste_fa_vend@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-901, 'teste_fa_vend', 'Teste fase A vendedor', false, v_uid);
  perform set_config('teste.uid_vend', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fa_adm@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-902, 'teste_fa_adm', 'Teste fase A admin', true, v_uid);
  perform set_config('teste.uid_adm', v_uid::text, true);

  perform set_config('teste.uid_controle', gen_random_uuid()::text, true);
end $$;

-- 1. Vendedor comum logado.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_id   bigint;
  v_r    record;
  v_ap   uuid := gen_random_uuid();
  v_nome text;
begin
  if public.app_is_admin() then
    raise exception 'FALHA: teste_fa_vend aparece como admin';
  end if;
  if public.app_meu_codigo() is distinct from 'teste_fa_vend' then
    raise exception 'FALHA: app_meu_codigo = % (esperado teste_fa_vend)', public.app_meu_codigo();
  end if;

  -- 1a. Insere salvo com id_aparelho: enviado_em preenchido, finalizado_em nulo.
  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              produtos, total, status, datahora, id_aparelho)
  values ('teste-fa-1', 'teste_fa_vend', 'Teste', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
          10, 'salvo', now(), v_ap)
  returning id into v_id;
  perform set_config('teste.p1', v_id::text, true);

  select * into v_r from public.pedidos where id = v_id;
  if v_r.enviado_em is distinct from now() then
    raise exception 'FALHA: p1 enviado_em = % (esperado now())', v_r.enviado_em;
  end if;
  if v_r.finalizado_em is not null or v_r.finalizado_por is not null or v_r.finalizado_manual then
    raise exception 'FALHA: p1 salvo nasceu com finalizado_* preenchido';
  end if;
  if v_r.alterado_em is not null or v_r.cancelado_em is not null or v_r.cancelado_por is not null then
    raise exception 'FALHA: p1 salvo nasceu com alterado_em/cancelado_* preenchido';
  end if;
  if v_r.id_aparelho is distinct from v_ap then
    raise exception 'FALHA: p1 id_aparelho nao gravou';
  end if;

  -- 1b. O mesmo id_aparelho em outro pedido: recusado pelo indice unico.
  begin
    insert into public.pedidos (numero, vendedor_codigo, total, status, datahora, id_aparelho)
    values ('teste-fa-dup', 'teste_fa_vend', 1, 'salvo', now(), v_ap);
    raise exception 'FALHA: id_aparelho repetido entrou';
  exception when unique_violation then
    get stacked diagnostics v_nome = constraint_name;
    if v_nome is distinct from 'pedidos_id_aparelho_key' then
      raise exception 'FALHA: id_aparelho repetido caiu em % (esperado pedidos_id_aparelho_key)', v_nome;
    end if;
  end;

  -- 1c. Finalizado sem id_aparelho (APK antigo), mandando datas e autores
  --     falsos: o servidor ignora e preenche os seus.
  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              produtos, total, status, datahora,
                              enviado_em, alterado_em, finalizado_em, finalizado_por,
                              finalizado_manual, cancelado_em, cancelado_por)
  values ('teste-fa-2', 'teste_fa_vend', 'Teste', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb,
          5, 'finalizado', now(),
          timestamptz '2000-01-01', timestamptz '2000-01-01', timestamptz '2000-01-01', 'X',
          true, timestamptz '2000-01-01', 'X')
  returning id into v_id;
  perform set_config('teste.p2', v_id::text, true);

  select * into v_r from public.pedidos where id = v_id;
  if v_r.finalizado_em is distinct from now() then
    raise exception 'FALHA: p2 finalizado_em = % (esperado now())', v_r.finalizado_em;
  end if;
  if v_r.finalizado_por is distinct from 'teste_fa_vend' then
    raise exception 'FALHA: p2 finalizado_por = % (esperado teste_fa_vend; X veio do cliente)', v_r.finalizado_por;
  end if;
  if v_r.finalizado_manual then
    raise exception 'FALHA: p2 finalizado_manual veio do cliente';
  end if;
  if v_r.enviado_em is distinct from now() or v_r.alterado_em is not null
     or v_r.cancelado_em is not null or v_r.cancelado_por is not null then
    raise exception 'FALHA: p2 aceitou enviado_em/alterado_em/cancelado_* do cliente';
  end if;
  if v_r.id_aparelho is not null then
    raise exception 'FALHA: p2 ganhou id_aparelho';
  end if;

  -- 1d. alterado_em: so datahora nao conta; produtos conta.
  update public.pedidos set datahora = datahora + interval '1 hour'
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.alterado_em is not null then
    raise exception 'FALHA: mudar so datahora preencheu alterado_em';
  end if;

  update public.pedidos
     set produtos = '[{"nome":"Leite","preco":5,"quantidade":3,"subtotal":15}]'::jsonb,
         total = 15
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: mudar a quantidade nao preencheu alterado_em (%)', v_r.alterado_em;
  end if;

  update public.pedidos set datahora = datahora + interval '1 hour'
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: mudar so datahora mexeu em alterado_em (%)', v_r.alterado_em;
  end if;

  -- 1e. Pedido em aberto: o cliente nao escolhe auditoria, enviado_em nem
  --     troca o id_aparelho ja gravado.
  update public.pedidos
     set finalizado_por = 'X', finalizado_em = timestamptz '2000-01-01',
         finalizado_manual = true,
         cancelado_por = 'X', cancelado_em = timestamptz '2000-01-01',
         alterado_em = timestamptz '2000-01-01',
         enviado_em = timestamptz '2000-01-01',
         id_aparelho = gen_random_uuid()
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: p1 mudou de situacao (%)', v_r.status;
  end if;
  if v_r.finalizado_por is not null or v_r.finalizado_em is not null or v_r.finalizado_manual
     or v_r.cancelado_por is not null or v_r.cancelado_em is not null then
    raise exception 'FALHA: UPDATE do cliente gravou finalizado_*/cancelado_* em pedido aberto';
  end if;
  if v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: UPDATE do cliente escolheu alterado_em (%)', v_r.alterado_em;
  end if;
  if v_r.enviado_em is distinct from now() then
    raise exception 'FALHA: UPDATE do cliente trocou enviado_em (%)', v_r.enviado_em;
  end if;
  if v_r.id_aparelho is distinct from v_ap then
    raise exception 'FALHA: UPDATE do cliente trocou id_aparelho';
  end if;

  -- 1f. O vendedor cancela com UPDATE comum; depois nao reabre nem
  --     finaliza sem assinatura.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa-3', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.p3', v_id::text, true);

  update public.pedidos set status = 'cancelado', cancelado_por = 'X' where id = v_id;
  select * into v_r from public.pedidos where id = v_id;
  if v_r.status is distinct from 'cancelado' or v_r.cancelado_em is distinct from now()
     or v_r.cancelado_por is distinct from 'teste_fa_vend' then
    raise exception 'FALHA: cancelamento do vendedor: status %, cancelado_em %, cancelado_por %',
      v_r.status, v_r.cancelado_em, v_r.cancelado_por;
  end if;
  if v_r.finalizado_em is not null or v_r.finalizado_por is not null then
    raise exception 'FALHA: cancelamento preencheu finalizado_*';
  end if;

  update public.pedidos
     set status = 'salvo',
         produtos = '[{"nome":"Leite","preco":5,"quantidade":9,"subtotal":45}]'::jsonb
   where id = v_id;
  update public.pedidos set status = 'finalizado' where id = v_id;  -- sem assinatura
  select * into v_r from public.pedidos where id = v_id;
  if v_r.status is distinct from 'cancelado' then
    raise exception 'FALHA: pedido cancelado virou % por UPDATE do celular', v_r.status;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 1 then
    raise exception 'FALHA: pedido cancelado teve os produtos trocados';
  end if;

  -- 1g. Pedido ja finalizado com assinatura nao e substituido por outro
  --     envio finalizado com outra assinatura (upsert, como o app faz).
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura)
  values ('teste-fa-4', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'finalizado', now(), decode('01', 'hex'))
  returning id into v_id;
  perform set_config('teste.p4', v_id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura)
  values ('teste-fa-4', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":9,"subtotal":45}]'::jsonb, 45,
          'finalizado', now() + interval '1 hour', decode('02', 'hex'))
  on conflict (numero, vendedor_codigo) do update
     set produtos   = excluded.produtos,
         total      = excluded.total,
         status     = excluded.status,
         datahora   = excluded.datahora,
         assinatura = excluded.assinatura;

  select * into v_r from public.pedidos where id = v_id;
  if v_r.assinatura is distinct from decode('01', 'hex')
     or (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 1
     or v_r.total is distinct from 5
     or v_r.datahora is distinct from now() then
    raise exception 'FALHA: pedido assinado foi substituido por outro envio';
  end if;

  -- Abertos para as RPCs (secoes 2 e 4).
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa-6', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.p6', v_id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa-8', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.p8', v_id::text, true);

  -- 1h. Vendedor nao admin nao chama as RPCs.
  begin
    perform public.pedido_finalizar_manual(current_setting('teste.p1')::bigint);
    raise exception 'FALHA: vendedor comum executou pedido_finalizar_manual';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.pedido_cancelar(current_setting('teste.p6')::bigint);
    raise exception 'FALHA: vendedor comum executou pedido_cancelar';
  exception when sqlstate '42501' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: p1 mudou para % depois da RPC recusada', v_r.status;
  end if;

  -- 1i. Situacao fora das tres: recusada pela constraint.
  begin
    insert into public.pedidos (numero, vendedor_codigo, total, status, datahora)
    values ('teste-fa-rascunho', 'teste_fa_vend', 1, 'rascunho', now());
    raise exception 'FALHA: status rascunho entrou';
  exception when check_violation then
    get stacked diagnostics v_nome = constraint_name;
    if v_nome is distinct from 'pedidos_status_check' then
      raise exception 'FALHA: rascunho caiu em % (esperado pedidos_status_check)', v_nome;
    end if;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 2. Admin que tambem e vendedor (como o 0002).
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.uid_adm'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_id bigint;
  v_r  record;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: teste_fa_adm nao aparece como admin';
  end if;

  -- 2a. Finalizar manual: grava finalizado_* com finalizado_manual = true.
  perform public.pedido_finalizar_manual(current_setting('teste.p1')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.finalizado_em is distinct from now()
     or v_r.finalizado_por is distinct from 'teste_fa_adm' then
    raise exception 'FALHA: finalizar manual: status %, manual %, em %, por %',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_em, v_r.finalizado_por;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 3 then
    raise exception 'FALHA: finalizar manual mexeu nos produtos';
  end if;

  -- A marca da RPC nao fica ligada para o resto da transacao.
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle continua ligada depois da RPC';
  end if;

  -- 2b. Admin agindo como vendedor, por UPDATE direto, nao reabre.
  update public.pedidos set status = 'salvo'
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'finalizado' then
    raise exception 'FALHA: admin reabriu pedido do vendedor por UPDATE direto (%)', v_r.status;
  end if;

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa-5', 'teste_fa_adm', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.p5', v_id::text, true);

  perform public.pedido_finalizar_manual(v_id);
  update public.pedidos
     set status = 'salvo',
         produtos = '[{"nome":"Leite","preco":5,"quantidade":4,"subtotal":20}]'::jsonb
   where id = v_id;
  select * into v_r from public.pedidos where id = v_id;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual then
    raise exception 'FALHA: admin 0002 pelo celular reabriu o proprio pedido (status %, manual %)',
      v_r.status, v_r.finalizado_manual;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 1 then
    raise exception 'FALHA: UPDATE do celular trocou produtos de pedido fechado';
  end if;

  -- 2c. Cancelar pelo Controle.
  perform public.pedido_cancelar(current_setting('teste.p6')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.p6')::bigint;
  if v_r.status is distinct from 'cancelado'
     or v_r.cancelado_em is distinct from now()
     or v_r.cancelado_por is distinct from 'teste_fa_adm' then
    raise exception 'FALHA: pedido_cancelar: status %, em %, por %',
      v_r.status, v_r.cancelado_em, v_r.cancelado_por;
  end if;
  if v_r.finalizado_em is not null or v_r.finalizado_por is not null then
    raise exception 'FALHA: pedido_cancelar preencheu finalizado_*';
  end if;

  -- 2d. As RPCs so aceitam pedido em aberto.
  begin
    perform public.pedido_cancelar(current_setting('teste.p2')::bigint);
    raise exception 'FALHA: pedido_cancelar aceitou pedido finalizado';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform public.pedido_finalizar_manual(current_setting('teste.p6')::bigint);
    raise exception 'FALHA: pedido_finalizar_manual aceitou pedido cancelado';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform public.pedido_finalizar_manual(-1);
    raise exception 'FALHA: pedido_finalizar_manual aceitou id inexistente';
  exception when sqlstate 'P0002' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.p2')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.cancelado_em is not null then
    raise exception 'FALHA: p2 mudou depois do pedido_cancelar recusado';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3. Vendedor comum de novo: o celular reenviando depois do Controle.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  -- 3a. Depois do finalizar manual, UPDATE com status = 'salvo': continua
  --     finalizado e manual.
  update public.pedidos set status = 'salvo'
   where id = current_setting('teste.p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.finalizado_por is distinct from 'teste_fa_adm' then
    raise exception 'FALHA: celular reabriu pedido finalizado manual (status %, manual %, por %)',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por;
  end if;

  -- 3b. Entrega assinada vence o finalizado manual: fica a quantidade
  --     nova, manual volta a false, autor passa a ser o vendedor.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura, finalizado_por)
  values ('teste-fa-1', 'teste_fa_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":7,"subtotal":35}]'::jsonb, 35,
          'finalizado', now(), decode('0a', 'hex'), 'X')
  on conflict (numero, vendedor_codigo) do update
     set produtos       = excluded.produtos,
         total          = excluded.total,
         status         = excluded.status,
         datahora       = excluded.datahora,
         assinatura     = excluded.assinatura,
         finalizado_por = excluded.finalizado_por;

  select * into v_r from public.pedidos where id = current_setting('teste.p1')::bigint;
  if v_r.status is distinct from 'finalizado' then
    raise exception 'FALHA: entrega assinada: status %', v_r.status;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 7 or v_r.total is distinct from 35 then
    raise exception 'FALHA: entrega assinada nao ficou com a quantidade nova';
  end if;
  if v_r.finalizado_manual then
    raise exception 'FALHA: entrega assinada deixou finalizado_manual = true';
  end if;
  if v_r.finalizado_por is distinct from 'teste_fa_vend' then
    raise exception 'FALHA: entrega assinada: finalizado_por = % (esperado teste_fa_vend)', v_r.finalizado_por;
  end if;
  if v_r.assinatura is distinct from decode('0a', 'hex') then
    raise exception 'FALHA: entrega assinada nao gravou a assinatura';
  end if;
  if v_r.cancelado_em is not null or v_r.enviado_em is distinct from now() then
    raise exception 'FALHA: entrega assinada mexeu em cancelado_em/enviado_em';
  end if;

  -- 3c. Entrega assinada vence o cancelado pelo Controle, e o cancelamento
  --     continua registrado.
  update public.pedidos
     set status = 'finalizado',
         assinatura = decode('0b', 'hex'),
         produtos = '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
         total = 10
   where id = current_setting('teste.p6')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.p6')::bigint;
  if v_r.status is distinct from 'finalizado' then
    raise exception 'FALHA: entrega assinada nao venceu o cancelado (status %)', v_r.status;
  end if;
  if v_r.cancelado_em is null or v_r.cancelado_por is distinct from 'teste_fa_adm' then
    raise exception 'FALHA: entrega assinada apagou o cancelamento (em %, por %)',
      v_r.cancelado_em, v_r.cancelado_por;
  end if;
  if v_r.finalizado_por is distinct from 'teste_fa_vend' or v_r.finalizado_manual
     or v_r.finalizado_em is distinct from now() then
    raise exception 'FALHA: entrega assinada sobre cancelado: finalizado_por %, manual %',
      v_r.finalizado_por, v_r.finalizado_manual;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 2 then
    raise exception 'FALHA: entrega assinada sobre cancelado nao ficou com a quantidade nova';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 4. Conta de admin do Controle sem linha em vendedores: finalizado_por
--    fica com o e-mail, nao vazio.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.uid_controle'),
                    'role', 'authenticated',
                    'email', 'teste_fa_controle@milkdim.local',
                    'app_metadata', json_build_object('role', 'admin'))::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  if not public.app_is_admin() or public.app_meu_codigo() is not null then
    raise exception 'FALHA: conta do Controle de teste mal montada';
  end if;

  perform public.pedido_finalizar_manual(current_setting('teste.p8')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.p8')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.finalizado_por is distinct from 'teste_fa_controle@milkdim.local' then
    raise exception 'FALHA: finalizar pelo Controle sem codigo: status %, manual %, por %',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 5. Estrutura e permissoes.
do $$
declare
  v_n bigint;
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  -- Gatilhos novos no lugar, e os de ultimo pedido intactos.
  select count(*) into v_n from pg_trigger
   where tgrelid = 'public.pedidos'::regclass and not tgisinternal
     and tgname in ('trg_pedidos_antes_inserir', 'trg_pedidos_antes_alterar',
                    'trg_atualizar_ultimo_pedido', 'trg_pedidos_update_cliente_ultimo');
  if v_n <> 4 then
    raise exception 'FALHA: % de 4 gatilhos esperados em pedidos', v_n;
  end if;

  -- RPCs: authenticated executa, anon nao. Internas: ninguem de fora.
  if not has_function_privilege('authenticated', 'public.pedido_finalizar_manual(bigint)', 'execute')
     or not has_function_privilege('authenticated', 'public.pedido_cancelar(bigint)', 'execute') then
    raise exception 'FALHA: authenticated sem EXECUTE nas RPCs do Controle';
  end if;
  if has_function_privilege('anon', 'public.pedido_finalizar_manual(bigint)', 'execute')
     or has_function_privilege('anon', 'public.pedido_cancelar(bigint)', 'execute') then
    raise exception 'FALHA: anon executa RPC do Controle';
  end if;
  if has_function_privilege('authenticated', 'public.app_autor_pedido()', 'execute')
     or has_function_privilege('authenticated', 'public.pedidos_antes_inserir()', 'execute')
     or has_function_privilege('authenticated', 'public.pedidos_antes_alterar()', 'execute')
     or has_function_privilege('anon', 'public.app_autor_pedido()', 'execute') then
    raise exception 'FALHA: funcao interna da fase A executavel por authenticated/anon';
  end if;

  -- Preenchimento dos antigos: nenhum finalizado sem finalizado_em.
  select count(*) into v_n from public.pedidos
   where status = 'finalizado' and finalizado_em is null;
  if v_n <> 0 then
    raise exception 'FALHA: % pedido(s) finalizado(s) sem finalizado_em', v_n;
  end if;

  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada no fim do teste';
  end if;
end $$;

select 'fase_a_test: OK' as resultado;
