-- Teste da fase A.2 (pronto para entrega e assinatura do pedido). Roda
-- dentro de begin ... rollback, montado por quem executa: este arquivo nao
-- abre nem fecha transacao. Cada bloco da raise exception quando a
-- verificacao falha.
--
-- Ordem:  begin; <fase A.2>; <fase_a_test.sql>; <este arquivo>; rollback;
-- (fases 1, 3 e A ja aplicadas no banco.) Roda depois do fase_a_test na
-- mesma transacao: numeros 'teste-fa2-*', vendedores -903/-904.
--
-- Tudo roda numa transacao so, entao now() e o mesmo instante em todo o
-- teste: "preenchido pelo servidor" se confere como = now(). Para ver se
-- um valor foi mantido ou re-carimbado, a secao 3 poe datas do passado.
--
-- Personagens, criados aqui e desfeitos no rollback (nenhuma senha: o hash
-- e de um valor aleatorio que ninguem conhece):
--   teste_fa2_vend  vendedor comum
--   teste_fa2_adm   vendedor com is_admin, que usa o Controle
--
-- Pedidos de teste (id gerado pelo banco, guardado em teste.fa2_p*):
--   p1  salvo com assinatura_pedido: nao vira pronto pelo vendedor; pronto
--       pela RPC; reenvio igual mantem pronto; mudar quantidade devolve
--   p2  insert 'pronto' que entra salvo; pronto pela RPC; cancelado pelo
--       Controle
--   p3  pronto, "Marcar como entregue" pelo Controle, depois a entrega
--       assinada do vendedor vence
--   p4  pronto, entregue pelo vendedor com a assinatura da entrega
--   p5  finalizado direto (para a RPC recusar)

-- 0. Preparacao, sem JWT (como o SQL Editor): contas Auth e vendedores.
select set_config('request.jwt.claims', '', true);
do $$
declare
  v_uid uuid;
begin
  v_uid := public.app_criar_usuario_auth(
    'teste_fa2_vend@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-903, 'teste_fa2_vend', 'Teste fase A.2 vendedor', false, v_uid);
  perform set_config('teste.fa2_uid_vend', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fa2_adm@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-904, 'teste_fa2_adm', 'Teste fase A.2 admin', true, v_uid);
  perform set_config('teste.fa2_uid_adm', v_uid::text, true);
end $$;

-- 1. Vendedor comum: nao grava pronto; assinatura do pedido.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fa2_uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_id   bigint;
  v_r    record;
  v_nome text;
begin
  if public.app_is_admin() then
    raise exception 'FALHA: teste_fa2_vend aparece como admin';
  end if;

  -- 1a. Insert salvo com assinatura_pedido, mandando pronto_* falsos: a
  --     assinatura fica, pronto_* nulos.
  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              produtos, total, status, datahora,
                              assinatura_pedido, pronto_em, pronto_por)
  values ('teste-fa2-1', 'teste_fa2_vend', 'Teste', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
          10, 'salvo', now(), decode('11', 'hex'), timestamptz '2000-01-01', 'X')
  returning id into v_id;
  perform set_config('teste.fa2_p1', v_id::text, true);

  select * into v_r from public.pedidos where id = v_id;
  if v_r.assinatura_pedido is distinct from decode('11', 'hex') then
    raise exception 'FALHA: insert nao guardou assinatura_pedido';
  end if;
  if v_r.pronto_em is not null or v_r.pronto_por is not null then
    raise exception 'FALHA: insert aceitou pronto_em/pronto_por do cliente (%, %)',
      v_r.pronto_em, v_r.pronto_por;
  end if;

  -- 1b. UPDATE do vendedor pedindo pronto (e escolhendo pronto_*): fica salvo.
  update public.pedidos
     set status = 'pronto', pronto_em = timestamptz '2000-01-01', pronto_por = 'X'
   where id = v_id;
  select * into v_r from public.pedidos where id = v_id;
  if v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: vendedor gravou status % por UPDATE (esperado salvo)', v_r.status;
  end if;
  if v_r.pronto_em is not null or v_r.pronto_por is not null then
    raise exception 'FALHA: UPDATE do vendedor gravou pronto_em/pronto_por';
  end if;
  if v_r.alterado_em is not null then
    raise exception 'FALHA: pedir pronto sem mudar itens preencheu alterado_em';
  end if;

  -- 1c. assinatura_pedido: UPDATE com ela nula nao apaga; com outra, substitui.
  update public.pedidos set assinatura_pedido = null, datahora = datahora + interval '1 hour'
   where id = v_id;
  select * into v_r from public.pedidos where id = v_id;
  if v_r.assinatura_pedido is distinct from decode('11', 'hex') then
    raise exception 'FALHA: UPDATE com assinatura_pedido nula apagou a gravada';
  end if;

  update public.pedidos set assinatura_pedido = decode('12', 'hex') where id = v_id;
  select * into v_r from public.pedidos where id = v_id;
  if v_r.assinatura_pedido is distinct from decode('12', 'hex') then
    raise exception 'FALHA: UPDATE com outra assinatura_pedido nao substituiu';
  end if;

  -- 1d. Insert ja como pronto: entra salvo, pronto_* nulos.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, pronto_em, pronto_por)
  values ('teste-fa2-2', 'teste_fa2_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'pronto', now(), timestamptz '2000-01-01', 'X')
  returning id into v_id;
  perform set_config('teste.fa2_p2', v_id::text, true);
  select * into v_r from public.pedidos where id = v_id;
  if v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: insert pronto ficou % (esperado salvo)', v_r.status;
  end if;
  if v_r.pronto_em is not null or v_r.pronto_por is not null
     or v_r.finalizado_em is not null or v_r.cancelado_em is not null then
    raise exception 'FALHA: insert pronto preencheu pronto_*/finalizado_*/cancelado_*';
  end if;

  -- Abertos para as RPCs e a entrega (secoes 2 e 4), e um finalizado.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa2-3', 'teste_fa2_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.fa2_p3', v_id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total, status, datahora)
  values ('teste-fa2-4', 'teste_fa2_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5, 'salvo', now())
  returning id into v_id;
  perform set_config('teste.fa2_p4', v_id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura)
  values ('teste-fa2-5', 'teste_fa2_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb, 5,
          'finalizado', now(), decode('05', 'hex'))
  returning id into v_id;
  perform set_config('teste.fa2_p5', v_id::text, true);

  -- 1e. Vendedor nao admin nao chama pedido_marcar_pronto.
  begin
    perform public.pedido_marcar_pronto(current_setting('teste.fa2_p1')::bigint);
    raise exception 'FALHA: vendedor comum executou pedido_marcar_pronto';
  exception when sqlstate '42501' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'salvo' or v_r.pronto_em is not null then
    raise exception 'FALHA: p1 mudou (status %, pronto_em %) depois da RPC recusada',
      v_r.status, v_r.pronto_em;
  end if;

  -- 1f. Situacao fora das quatro: recusada pela constraint.
  begin
    insert into public.pedidos (numero, vendedor_codigo, total, status, datahora)
    values ('teste-fa2-rascunho', 'teste_fa2_vend', 1, 'rascunho', now());
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

-- 2. Admin (Controle): Producao concluida, cancelar e marcar como entregue
--    num pronto.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fa2_uid_adm'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: teste_fa2_adm nao aparece como admin';
  end if;

  -- 2a. pedido_marcar_pronto num salvo: pronto, pronto_em = now(),
  --     pronto_por = codigo do admin; o resto fica.
  perform public.pedido_marcar_pronto(current_setting('teste.fa2_p1')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'pronto'
     or v_r.pronto_em is distinct from now()
     or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: marcar pronto: status %, pronto_em %, pronto_por %',
      v_r.status, v_r.pronto_em, v_r.pronto_por;
  end if;
  if v_r.alterado_em is not null or v_r.finalizado_em is not null or v_r.cancelado_em is not null
     or v_r.assinatura_pedido is distinct from decode('12', 'hex')
     or (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 2 then
    raise exception 'FALHA: marcar pronto mexeu em outros campos';
  end if;
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle continua ligada depois de pedido_marcar_pronto';
  end if;

  -- 2b. So salvo: pronto e finalizado dao 55000; id inexistente, P0002.
  begin
    perform public.pedido_marcar_pronto(current_setting('teste.fa2_p1')::bigint);
    raise exception 'FALHA: pedido_marcar_pronto aceitou pedido pronto';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform public.pedido_marcar_pronto(current_setting('teste.fa2_p5')::bigint);
    raise exception 'FALHA: pedido_marcar_pronto aceitou pedido finalizado';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform public.pedido_marcar_pronto(-1);
    raise exception 'FALHA: pedido_marcar_pronto aceitou id inexistente';
  exception when sqlstate 'P0002' then
    null;
  end;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p5')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.pronto_em is not null then
    raise exception 'FALHA: p5 mudou depois do pedido_marcar_pronto recusado';
  end if;

  perform public.pedido_marcar_pronto(current_setting('teste.fa2_p2')::bigint);
  perform public.pedido_marcar_pronto(current_setting('teste.fa2_p3')::bigint);
  perform public.pedido_marcar_pronto(current_setting('teste.fa2_p4')::bigint);

  -- 2c. pedido_cancelar num pronto: cancelado; pronto_* guardados.
  perform public.pedido_cancelar(current_setting('teste.fa2_p2')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p2')::bigint;
  if v_r.status is distinct from 'cancelado'
     or v_r.cancelado_em is distinct from now()
     or v_r.cancelado_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: cancelar pronto: status %, em %, por %',
      v_r.status, v_r.cancelado_em, v_r.cancelado_por;
  end if;
  if v_r.pronto_em is distinct from now() or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: cancelar pronto apagou pronto_em/pronto_por';
  end if;

  -- 2d. pedido_finalizar_manual num pronto: finalizado manual.
  perform public.pedido_finalizar_manual(current_setting('teste.fa2_p3')::bigint);
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p3')::bigint;
  if v_r.status is distinct from 'finalizado' or not v_r.finalizado_manual
     or v_r.finalizado_em is distinct from now()
     or v_r.finalizado_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: finalizar manual de pronto: status %, manual %, em %, por %',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_em, v_r.finalizado_por;
  end if;

  -- 2e. As RPCs continuam recusando pedido fechado.
  begin
    perform public.pedido_cancelar(current_setting('teste.fa2_p3')::bigint);
    raise exception 'FALHA: pedido_cancelar aceitou pedido finalizado';
  exception when sqlstate '55000' then
    null;
  end;
  begin
    perform public.pedido_finalizar_manual(current_setting('teste.fa2_p2')::bigint);
    raise exception 'FALHA: pedido_finalizar_manual aceitou pedido cancelado';
  exception when sqlstate '55000' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 3. Sem JWT, com a marca das RPCs: poe em p1 (pronto) datas do passado,
--    pronto_em depois de alterado_em, para a secao 4 ver o que foi mantido
--    e o que foi re-carimbado.
do $$
declare
  v_r record;
begin
  perform set_config('milkdim.acao_controle', '1', true);
  update public.pedidos
     set alterado_em = now() - interval '2 hours',
         pronto_em   = now() - interval '1 hour'
   where id = current_setting('teste.fa2_p1')::bigint;
  perform set_config('milkdim.acao_controle', '', true);

  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'pronto'
     or v_r.alterado_em is distinct from now() - interval '2 hours'
     or v_r.pronto_em is distinct from now() - interval '1 hour' then
    raise exception 'FALHA: preparo da secao 4 nao gravou (status %, alterado_em %, pronto_em %)',
      v_r.status, v_r.alterado_em, v_r.pronto_em;
  end if;
end $$;

-- 4. Vendedor comum: o celular reenviando um pedido pronto, e a entrega.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fa2_uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  -- 4a. Reenvio com os mesmos itens e status = 'salvo' (copia do celular,
  --     pelo upsert do app, sem assinatura_pedido): continua pronto, nada
  --     re-carimbado, assinatura_pedido mantida.
  insert into public.pedidos (numero, vendedor_codigo, vendedor_nome, cliente_nome,
                              produtos, total, status, datahora, assinatura_pedido)
  values ('teste-fa2-1', 'teste_fa2_vend', 'Teste', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":2,"subtotal":10}]'::jsonb,
          10, 'salvo', now(), null)
  on conflict (numero, vendedor_codigo) do update
     set produtos          = excluded.produtos,
         total             = excluded.total,
         status            = excluded.status,
         datahora          = excluded.datahora,
         cliente_nome      = excluded.cliente_nome,
         assinatura_pedido = excluded.assinatura_pedido;

  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'pronto' then
    raise exception 'FALHA: reenvio igual tirou o pedido de pronto (status %)', v_r.status;
  end if;
  if v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: reenvio igual re-carimbou alterado_em (%)', v_r.alterado_em;
  end if;
  if v_r.pronto_em is distinct from now() - interval '1 hour'
     or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: reenvio igual mexeu em pronto_em/pronto_por (%, %)',
      v_r.pronto_em, v_r.pronto_por;
  end if;
  if v_r.assinatura_pedido is distinct from decode('12', 'hex') then
    raise exception 'FALHA: reenvio sem assinatura_pedido apagou a gravada';
  end if;

  -- 4b. Reenvio igual pedindo pronto: continua pronto.
  update public.pedidos set status = 'pronto'
   where id = current_setting('teste.fa2_p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'pronto'
     or v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: reenvio igual com status pronto: status %, alterado_em %',
      v_r.status, v_r.alterado_em;
  end if;

  -- 4c. Vendedor muda a quantidade: volta para salvo, alterado_em = now(),
  --     pronto_em/pronto_por guardados, e "alterado depois de pronto" vale.
  update public.pedidos
     set produtos = '[{"nome":"Leite","preco":5,"quantidade":4,"subtotal":20}]'::jsonb,
         total = 20, status = 'salvo'
   where id = current_setting('teste.fa2_p1')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p1')::bigint;
  if v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: mudar quantidade de pronto nao voltou para salvo (status %)', v_r.status;
  end if;
  if v_r.alterado_em is distinct from now() then
    raise exception 'FALHA: mudar quantidade de pronto: alterado_em = % (esperado now())', v_r.alterado_em;
  end if;
  if v_r.pronto_em is distinct from now() - interval '1 hour'
     or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: voltar para salvo apagou pronto_em/pronto_por (%, %)',
      v_r.pronto_em, v_r.pronto_por;
  end if;
  if not (v_r.status = 'salvo' and v_r.pronto_em is not null and v_r.alterado_em > v_r.pronto_em) then
    raise exception 'FALHA: condicao "alterado depois de pronto" nao vale para p1';
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 4 then
    raise exception 'FALHA: mudar quantidade de pronto nao gravou os produtos';
  end if;

  -- 4d. Vendedor entrega um pronto com a assinatura da entrega (UPDATE
  --     comum, autor falso): finalizado pelo vendedor; pronto_* guardados.
  update public.pedidos
     set status = 'finalizado', assinatura = decode('04', 'hex'),
         finalizado_por = 'X', finalizado_em = timestamptz '2000-01-01',
         finalizado_manual = true
   where id = current_setting('teste.fa2_p4')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p4')::bigint;
  if v_r.status is distinct from 'finalizado'
     or v_r.finalizado_por is distinct from 'teste_fa2_vend'
     or v_r.finalizado_em is distinct from now()
     or v_r.finalizado_manual then
    raise exception 'FALHA: entrega de pronto: status %, por %, em %, manual %',
      v_r.status, v_r.finalizado_por, v_r.finalizado_em, v_r.finalizado_manual;
  end if;
  if v_r.assinatura is distinct from decode('04', 'hex') then
    raise exception 'FALHA: entrega de pronto nao gravou a assinatura';
  end if;
  if v_r.pronto_em is distinct from now() or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: entrega de pronto apagou pronto_em/pronto_por';
  end if;

  -- 4e. Entrega assinada vence o "Marcar como entregue" de um pronto (p3),
  --     pelo upsert do app: quantidade nova, manual false, autor vendedor.
  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura)
  values ('teste-fa2-3', 'teste_fa2_vend', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":6,"subtotal":30}]'::jsonb, 30,
          'finalizado', now(), decode('03', 'hex'))
  on conflict (numero, vendedor_codigo) do update
     set produtos   = excluded.produtos,
         total      = excluded.total,
         status     = excluded.status,
         datahora   = excluded.datahora,
         assinatura = excluded.assinatura;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p3')::bigint;
  if v_r.status is distinct from 'finalizado' or v_r.finalizado_manual
     or v_r.finalizado_por is distinct from 'teste_fa2_vend' then
    raise exception 'FALHA: entrega assinada nao venceu o manual de um pronto (status %, manual %, por %)',
      v_r.status, v_r.finalizado_manual, v_r.finalizado_por;
  end if;
  if (v_r.produtos -> 0 ->> 'quantidade')::numeric is distinct from 6
     or v_r.assinatura is distinct from decode('03', 'hex') then
    raise exception 'FALHA: entrega assinada sobre manual de pronto nao ficou com a versao do vendedor';
  end if;
  if v_r.pronto_em is distinct from now() or v_r.pronto_por is distinct from 'teste_fa2_adm' then
    raise exception 'FALHA: entrega assinada apagou pronto_em/pronto_por';
  end if;

  -- 4f. Pronto cancelado pelo Controle (p2): reenvio salvo do celular nao
  --     reabre.
  update public.pedidos set status = 'salvo'
   where id = current_setting('teste.fa2_p2')::bigint;
  select * into v_r from public.pedidos where id = current_setting('teste.fa2_p2')::bigint;
  if v_r.status is distinct from 'cancelado' then
    raise exception 'FALHA: celular reabriu pronto cancelado (status %)', v_r.status;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- 5. Estrutura e permissoes.
do $$
declare
  v_n   bigint;
  v_def text;
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  -- Colunas novas com o tipo certo.
  select count(*) into v_n from information_schema.columns
   where table_schema = 'public' and table_name = 'pedidos'
     and ((column_name = 'assinatura_pedido' and data_type = 'bytea')
       or (column_name = 'pronto_em' and data_type = 'timestamp with time zone')
       or (column_name = 'pronto_por' and data_type = 'text'));
  if v_n <> 3 then
    raise exception 'FALHA: % de 3 colunas novas com o tipo esperado', v_n;
  end if;

  -- Constraint com as quatro situacoes.
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conrelid = 'public.pedidos'::regclass and conname = 'pedidos_status_check';
  if v_def is null or v_def not like '%''pronto''%' or v_def not like '%''salvo''%'
     or v_def not like '%''finalizado''%' or v_def not like '%''cancelado''%' then
    raise exception 'FALHA: pedidos_status_check = %', v_def;
  end if;

  -- Gatilhos no lugar, e os de ultimo pedido intactos.
  select count(*) into v_n from pg_trigger
   where tgrelid = 'public.pedidos'::regclass and not tgisinternal
     and tgname in ('trg_pedidos_antes_inserir', 'trg_pedidos_antes_alterar',
                    'trg_atualizar_ultimo_pedido', 'trg_pedidos_update_cliente_ultimo');
  if v_n <> 4 then
    raise exception 'FALHA: % de 4 gatilhos esperados em pedidos', v_n;
  end if;

  -- RPC nova: authenticated executa, anon nao; security definer com
  -- search_path vazio.
  if not has_function_privilege('authenticated', 'public.pedido_marcar_pronto(bigint)', 'execute') then
    raise exception 'FALHA: authenticated sem EXECUTE em pedido_marcar_pronto';
  end if;
  if has_function_privilege('anon', 'public.pedido_marcar_pronto(bigint)', 'execute') then
    raise exception 'FALHA: anon executa pedido_marcar_pronto';
  end if;
  select count(*) into v_n from pg_proc
   where oid = 'public.pedido_marcar_pronto(bigint)'::regprocedure
     and prosecdef and proconfig @> array['search_path=""'];
  if v_n <> 1 then
    raise exception 'FALHA: pedido_marcar_pronto sem security definer / search_path vazio';
  end if;

  -- As RPCs e funcoes da fase A continuam com as permissoes de antes.
  if not has_function_privilege('authenticated', 'public.pedido_finalizar_manual(bigint)', 'execute')
     or not has_function_privilege('authenticated', 'public.pedido_cancelar(bigint)', 'execute') then
    raise exception 'FALHA: authenticated sem EXECUTE nas RPCs do Controle';
  end if;
  if has_function_privilege('anon', 'public.pedido_finalizar_manual(bigint)', 'execute')
     or has_function_privilege('anon', 'public.pedido_cancelar(bigint)', 'execute') then
    raise exception 'FALHA: anon executa RPC do Controle';
  end if;
  if has_function_privilege('authenticated', 'public.pedidos_antes_inserir()', 'execute')
     or has_function_privilege('authenticated', 'public.pedidos_antes_alterar()', 'execute')
     or has_function_privilege('anon', 'public.pedidos_antes_alterar()', 'execute') then
    raise exception 'FALHA: funcao de gatilho executavel por authenticated/anon';
  end if;

  -- Nenhum pronto sem pronto_em.
  select count(*) into v_n from public.pedidos
   where status = 'pronto' and pronto_em is null;
  if v_n <> 0 then
    raise exception 'FALHA: % pedido(s) pronto(s) sem pronto_em', v_n;
  end if;

  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada no fim do teste';
  end if;
end $$;

select 'fase_a2_test: OK' as resultado;
