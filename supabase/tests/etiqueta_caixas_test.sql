-- Teste da etiqueta por caixa (tipos de caixa, volumes do pedido e a RPC
-- pedido_salvar_volumes). Roda dentro de begin ... rollback, montado por
-- quem executa: este arquivo nao abre nem fecha transacao. Cada bloco da
-- raise exception quando a verificacao falha.
--
-- Teste de pre-aplicacao: o bloco 1 espera os 3 tipos iniciais recem
-- criados, entao so vale com a migracao aplicada dentro do mesmo rollback.
--
-- Ordem:  begin; <20261126000001_etiqueta_caixas.sql>; <este arquivo>;
--         rollback;
-- (fases 1 a B ja aplicadas no banco.) Vendedores -920 e -921.
--
-- Tudo roda numa transacao so, entao now() e o mesmo instante em todo o
-- teste: "preenchido pelo servidor" se confere como = now(). Para ver se um
-- valor foi mantido ou re-carimbado, o bloco C poe datas do passado.
--
-- Personagens, criados aqui e desfeitos no rollback (nenhuma senha: o hash
-- e de um valor aleatorio que ninguem conhece):
--   vend  vendedor comum, codigo -920: dono dos pedidos de teste
--   adm   vendedor com is_admin, codigo -921: usa o Controle
--   sem   conta autenticada sem linha em vendedores (so no JWT)
--   anon  chave anonima (role anon)
--
-- Pedidos de teste, todos de vend (ids em teste.fc_p*):
--   p1  pronto: Copo teste 160g x8 e Pudim teste x5; alterado_em de 2 horas
--       atras (para conferir pedido_alterado_em)
--   p2  salvo: Copo teste 160g em duas linhas (5 e 3) e Pudim teste x2
--   p3  finalizado (com assinatura): Leite x1
--   p4  cancelado: Leite x1
--
-- Produtos de teste (bloco C): ids acima do maior id existente.
--
-- A RPC so grava em pedido_volumes: o bloco C guarda a contagem e a soma
-- dos totais dos pedidos e o bloco G confere que nada mudou.

-- A. Preparacao, sem JWT (como o SQL Editor): contas Auth e vendedores.
select set_config('request.jwt.claims', '', true);
do $$
declare
  v_uid uuid;
begin
  v_uid := public.app_criar_usuario_auth(
    'teste_fc_vend@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-920, '-920', 'Teste caixas vendedor', false, v_uid);
  perform set_config('teste.fc_uid_vend', v_uid::text, true);

  v_uid := public.app_criar_usuario_auth(
    'teste_fc_adm@milkdim.local',
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    null, '{}'::jsonb, true);
  insert into public.vendedores (id, codigo, nome, is_admin, auth_user_id)
  values (-921, '-921', 'Teste caixas admin', true, v_uid);
  perform set_config('teste.fc_uid_adm', v_uid::text, true);

  perform set_config('teste.fc_uid_sem', gen_random_uuid()::text, true);
end $$;

-- B. O vendedor -920 cria os pedidos de teste.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fc_uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_r record;
begin
  if public.app_meu_codigo() is distinct from '-920' then
    raise exception 'FALHA: app_meu_codigo = % (esperado -920)', public.app_meu_codigo();
  end if;
  if public.app_is_admin() then
    raise exception 'FALHA: vendedor comum aparece como admin';
  end if;

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora)
  values ('teste-fc-1', '-920', 'Cliente teste',
          '[{"nome":"Copo teste 160g","preco":2,"quantidade":8,"subtotal":16},
            {"nome":"Pudim teste","preco":3,"quantidade":5,"subtotal":15}]'::jsonb,
          31, 'salvo', now())
  returning id into v_r;
  perform set_config('teste.fc_p1', v_r.id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora)
  values ('teste-fc-2', '-920', 'Cliente teste',
          '[{"nome":"Copo teste 160g","preco":2,"quantidade":5,"subtotal":10},
            {"nome":"Pudim teste","preco":3,"quantidade":2,"subtotal":6},
            {"nome":"Copo teste 160g","preco":2,"quantidade":3,"subtotal":6}]'::jsonb,
          22, 'salvo', now())
  returning id into v_r;
  perform set_config('teste.fc_p2', v_r.id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora, assinatura)
  values ('teste-fc-3', '-920', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb,
          5, 'finalizado', now(), decode('0f', 'hex'))
  returning id into v_r;
  perform set_config('teste.fc_p3', v_r.id::text, true);

  insert into public.pedidos (numero, vendedor_codigo, cliente_nome, produtos, total,
                              status, datahora)
  values ('teste-fc-4', '-920', 'Cliente teste',
          '[{"nome":"Leite","preco":5,"quantidade":1,"subtotal":5}]'::jsonb,
          5, 'cancelado', now())
  returning id into v_r;
  perform set_config('teste.fc_p4', v_r.id::text, true);

  select * into v_r from public.pedidos where id = current_setting('teste.fc_p3')::bigint;
  if v_r.status is distinct from 'finalizado' then
    raise exception 'FALHA: preparo: p3 esta % (esperado finalizado)', v_r.status;
  end if;
  select * into v_r from public.pedidos where id = current_setting('teste.fc_p4')::bigint;
  if v_r.status is distinct from 'cancelado' then
    raise exception 'FALHA: preparo: p4 esta % (esperado cancelado)', v_r.status;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- C. Sem JWT: alterado_em do passado em p1 (para ver que a RPC copia o do
--    pedido), foto dos pedidos, e a ligacao inicial dos produtos pelo nome.
do $$
declare
  v_r    record;
  v_n    bigint;
  v_s    numeric;
  v_base bigint;
  v_medio bigint;
  v_tipo  bigint;
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  perform set_config('milkdim.acao_controle', '1', true);
  update public.pedidos
     set alterado_em = now() - interval '2 hours'
   where id = current_setting('teste.fc_p1')::bigint;
  perform set_config('milkdim.acao_controle', '', true);

  select * into v_r from public.pedidos where id = current_setting('teste.fc_p1')::bigint;
  if v_r.alterado_em is distinct from now() - interval '2 hours' or v_r.status is distinct from 'salvo' then
    raise exception 'FALHA: preparo de p1: alterado_em %, status %', v_r.alterado_em, v_r.status;
  end if;

  select count(*), coalesce(sum(total), 0) into v_n, v_s from public.pedidos;
  perform set_config('teste.fc_ped_n', v_n::text, true);
  perform set_config('teste.fc_ped_soma', v_s::text, true);

  -- Produtos de teste. A migracao ja rodou, entao a ligacao inicial se
  -- refaz com a mesma regra (os tres UPDATEs da migracao, copiados abaixo).
  select id into v_medio from public.tipos_caixa where lower(btrim(nome)) = lower('Médio');
  select coalesce(max(id), 0) into v_base from public.produtos;

  insert into public.produtos (id, nome) values (v_base + 1, 'Copo teste 160g');
  insert into public.produtos (id, nome) values (v_base + 2, 'Pudim teste');
  insert into public.produtos (id, nome) values (v_base + 3, '  POTE teste 160G ');
  insert into public.produtos (id, nome) values (v_base + 4, '550g teste');
  insert into public.produtos (id, nome) values (v_base + 5, 'Pote sem gramas');
  -- Escolha feita a mao: a nova rodada nao pode desfazer.
  insert into public.produtos (id, nome, tipo_caixa_id) values (v_base + 6, 'Copo manual', v_medio);
  perform set_config('teste.fc_prod_base', v_base::text, true);

  -- (copia da migracao)
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

  -- 2a. Copo teste 160g -> Copo.
  select t.nome into v_r from public.produtos p join public.tipos_caixa t on t.id = p.tipo_caixa_id
   where p.id = v_base + 1;
  if v_r.nome is distinct from 'Copo' then
    raise exception 'FALHA: Copo teste 160g ligou ao tipo % (esperado Copo)', v_r.nome;
  end if;

  -- 2b. Pudim teste -> sem tipo.
  select tipo_caixa_id into v_tipo from public.produtos where id = v_base + 2;
  if v_tipo is not null then
    raise exception 'FALHA: Pudim teste ligou ao tipo % (esperado nenhum)', v_tipo;
  end if;

  -- 2c. "  POTE teste 160G " (btrim, sem diferenciar maiusculas) -> Pote.
  select t.nome into v_r from public.produtos p join public.tipos_caixa t on t.id = p.tipo_caixa_id
   where p.id = v_base + 3;
  if v_r.nome is distinct from 'Pote' then
    raise exception 'FALHA: POTE teste 160G ligou ao tipo % (esperado Pote)', v_r.nome;
  end if;

  -- 2d. 550g -> Medio.
  select tipo_caixa_id into v_tipo from public.produtos where id = v_base + 4;
  if v_tipo is distinct from v_medio then
    raise exception 'FALHA: 550g teste ligou ao tipo % (esperado Medio %)', v_tipo, v_medio;
  end if;

  -- 2e. Pote sem "160g" fica sem tipo.
  select tipo_caixa_id into v_tipo from public.produtos where id = v_base + 5;
  if v_tipo is not null then
    raise exception 'FALHA: Pote sem gramas ligou ao tipo % (esperado nenhum)', v_tipo;
  end if;

  -- 2f. Escolha manual (Copo manual = Medio) nao muda.
  select tipo_caixa_id into v_tipo from public.produtos where id = v_base + 6;
  if v_tipo is distinct from v_medio then
    raise exception 'FALHA: a nova rodada desfez a escolha manual de Copo manual (%)', v_tipo;
  end if;
end $$;

-- D. Controle (admin).
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fc_uid_adm'),
                    'role', 'authenticated')::text, true);
set local role authenticated;

-- D1. Tipos de caixa: 3 tipos com as capacidades certas.
do $$
declare
  v_n bigint;
begin
  if not public.app_is_admin() then
    raise exception 'FALHA: adm nao aparece como admin';
  end if;

  select count(*) into v_n from public.tipos_caixa
   where (lower(btrim(nome)), capacidade, mistura_sabores, ativo) in (
           (lower('Pote'), 16, true, true),
           (lower('Copo'), 20, true, true),
           (lower('Médio'), 4, true, true));
  if v_n <> 3 then
    raise exception 'FALHA: % de 3 tipos iniciais com a capacidade certa', v_n;
  end if;

  select count(*) into v_n from public.tipos_caixa;
  if v_n <> 3 then
    raise exception 'FALHA: % tipos de caixa (esperados 3 recem criados)', v_n;
  end if;
end $$;

-- D2. p1 passa a pronto (para os testes seguintes).
do $$
declare
  v_r record;
begin
  perform public.pedido_marcar_pronto(current_setting('teste.fc_p1')::bigint,
                                      now() - interval '2 hours');
  select * into v_r from public.pedidos where id = current_setting('teste.fc_p1')::bigint;
  if v_r.status is distinct from 'pronto' or v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: preparo: p1 status %, alterado_em %', v_r.status, v_r.alterado_em;
  end if;
end $$;

-- D3. O admin salva os volumes de p1 (pronto, itens somam certo).
do $$
declare
  v_r   record;
  v_vol jsonb := '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8}]},
                   {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5}]}]'::jsonb;
begin
  perform public.pedido_salvar_volumes(current_setting('teste.fc_p1')::bigint, false, v_vol);

  select * into v_r from public.pedido_volumes where pedido_id = current_setting('teste.fc_p1')::bigint;
  if not found then
    raise exception 'FALHA: pedido_salvar_volumes nao gravou a linha de p1';
  end if;
  if v_r.solto or v_r.volumes is distinct from v_vol then
    raise exception 'FALHA: p1: solto %, volumes %', v_r.solto, v_r.volumes;
  end if;
  if v_r.salvo_por is distinct from '-921' then
    raise exception 'FALHA: p1: salvo_por % (esperado -921)', v_r.salvo_por;
  end if;
  if v_r.salvo_em is distinct from now() then
    raise exception 'FALHA: p1: salvo_em % (esperado now())', v_r.salvo_em;
  end if;
  if v_r.pedido_alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: p1: pedido_alterado_em % (esperado o alterado_em do pedido)', v_r.pedido_alterado_em;
  end if;

  -- O pedido nao mudou.
  select * into v_r from public.pedidos where id = current_setting('teste.fc_p1')::bigint;
  if v_r.status is distinct from 'pronto' or v_r.alterado_em is distinct from now() - interval '2 hours' then
    raise exception 'FALHA: salvar volumes mexeu em p1 (status %, alterado_em %)', v_r.status, v_r.alterado_em;
  end if;
  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada depois de pedido_salvar_volumes';
  end if;
end $$;

-- D4. Entradas invalidas em p1: nada muda.
do $$
declare
  v_antes jsonb;
  v_depois jsonb;
  v_p1 bigint := current_setting('teste.fc_p1')::bigint;
begin
  select volumes into v_antes from public.pedido_volumes where pedido_id = v_p1;

  -- Soma errada (Copo 7 em vez de 8).
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":7}]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: soma errada aceita';
  exception when sqlstate 'MD011' then
    null;
  end;

  -- Nome do pedido que falta nos volumes.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8}]}]'::jsonb);
    raise exception 'FALHA: volumes sem um produto do pedido aceitos';
  exception when sqlstate 'MD011' then
    null;
  end;

  -- Nome a mais nos volumes.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8}]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5},
                                               {"nome":"Produto de fora","quantidade":1}]}]'::jsonb);
    raise exception 'FALHA: volumes com produto que nao esta no pedido aceitos';
  exception when sqlstate 'MD011' then
    null;
  end;

  -- Volume vazio.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: volume vazio aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- Volume sem o campo itens.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo"}]'::jsonb);
    raise exception 'FALHA: volume sem itens aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- Quantidade 0.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8},
                                                {"nome":"Pudim teste","quantidade":0}]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: quantidade 0 aceita';
  exception when sqlstate '22023' then
    null;
  end;

  -- Quantidade negativa.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":-8}]}]'::jsonb);
    raise exception 'FALHA: quantidade negativa aceita';
  exception when sqlstate '22023' then
    null;
  end;

  -- Quantidade quebrada.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8.5}]}]'::jsonb);
    raise exception 'FALHA: quantidade quebrada aceita';
  exception when sqlstate '22023' then
    null;
  end;

  -- Quantidade em texto.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":"8"}]}]'::jsonb);
    raise exception 'FALHA: quantidade em texto aceita';
  exception when sqlstate '22023' then
    null;
  end;

  -- Tipo de volume desconhecido.
  begin
    perform public.pedido_salvar_volumes(v_p1, false,
      '[{"tipo":"palete","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8}]}]'::jsonb);
    raise exception 'FALHA: tipo de volume desconhecido aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- p_solto com 2 volumes.
  begin
    perform public.pedido_salvar_volumes(v_p1, true,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8}]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: p_solto com 2 volumes aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- p_solto com 1 volume que nao e avulso.
  begin
    perform public.pedido_salvar_volumes(v_p1, true,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8},
                                                {"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: p_solto com volume do tipo caixa aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- p_solto nulo.
  begin
    perform public.pedido_salvar_volumes(v_p1, null,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8},
                                               {"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: p_solto nulo aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- p_volumes vazio, nulo, objeto em vez de array.
  begin
    perform public.pedido_salvar_volumes(v_p1, false, '[]'::jsonb);
    raise exception 'FALHA: p_volumes vazio aceito';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(v_p1, false, null);
    raise exception 'FALHA: p_volumes nulo aceito';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(v_p1, false, '{"tipo":"avulso"}'::jsonb);
    raise exception 'FALHA: p_volumes que nao e array aceito';
  exception when sqlstate '22023' then
    null;
  end;

  -- Nada mudou em p1.
  select volumes into v_depois from public.pedido_volumes where pedido_id = v_p1;
  if v_depois is distinct from v_antes then
    raise exception 'FALHA: uma chamada recusada mudou os volumes de p1: %', v_depois;
  end if;
end $$;

-- D5. Pedido finalizado (p3) ou cancelado (p4): MD010, e nada e gravado.
--     Pedido que nao existe: P0002.
do $$
declare
  v_n   bigint;
  v_vol jsonb := '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Leite","quantidade":1}]}]'::jsonb;
begin
  begin
    perform public.pedido_salvar_volumes(current_setting('teste.fc_p3')::bigint, false, v_vol);
    raise exception 'FALHA: volumes de pedido finalizado aceitos';
  exception when sqlstate 'MD010' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(current_setting('teste.fc_p4')::bigint, false, v_vol);
    raise exception 'FALHA: volumes de pedido cancelado aceitos';
  exception when sqlstate 'MD010' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(-1, false, v_vol);
    raise exception 'FALHA: volumes de pedido inexistente aceitos';
  exception when sqlstate 'P0002' then
    null;
  end;

  select count(*) into v_n from public.pedido_volumes
   where pedido_id in (current_setting('teste.fc_p3')::bigint, current_setting('teste.fc_p4')::bigint);
  if v_n <> 0 then
    raise exception 'FALHA: % linha(s) gravada(s) para pedido finalizado/cancelado', v_n;
  end if;
end $$;

-- D6. Duas linhas do mesmo produto no pedido (p2): a soma e por nome.
do $$
declare
  v_r  record;
  v_p2 bigint := current_setting('teste.fc_p2')::bigint;
  v_n  bigint;
begin
  -- Copo 5 + 3 numa caixa so, mais o Pudim: passa.
  perform public.pedido_salvar_volumes(v_p2, false,
    '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":8}]},
      {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":2}]}]'::jsonb);

  -- Copo repartido em duas caixas (5 e 3), nome com espacos nas pontas
  -- (btrim): passa e troca a linha (upsert).
  perform public.pedido_salvar_volumes(v_p2, false,
    '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":" Copo teste 160g ","quantidade":5}]},
      {"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":3},
                                              {"nome":"Pudim teste","quantidade":2}]}]'::jsonb);
  select count(*) into v_n from public.pedido_volumes where pedido_id = v_p2;
  if v_n <> 1 then
    raise exception 'FALHA: % linhas de volumes para p2 (esperada 1, upsert)', v_n;
  end if;
  select * into v_r from public.pedido_volumes where pedido_id = v_p2;
  if jsonb_array_length(v_r.volumes) <> 2 or v_r.solto then
    raise exception 'FALHA: p2 nao guardou a ultima versao (solto %, volumes %)', v_r.solto, v_r.volumes;
  end if;

  -- Somar so uma das linhas (5, nao 8) nao basta.
  begin
    perform public.pedido_salvar_volumes(v_p2, false,
      '[{"tipo":"caixa","caixa":"Copo","itens":[{"nome":"Copo teste 160g","quantidade":5}]},
        {"tipo":"avulso","caixa":null,"itens":[{"nome":"Pudim teste","quantidade":2}]}]'::jsonb);
    raise exception 'FALHA: soma de so uma das linhas do mesmo produto aceita';
  exception when sqlstate 'MD011' then
    null;
  end;

  -- Pedido solto: um volume avulso com tudo.
  perform public.pedido_salvar_volumes(v_p2, true,
    '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8},
                                             {"nome":"Pudim teste","quantidade":2}]}]'::jsonb);
  select * into v_r from public.pedido_volumes where pedido_id = v_p2;
  if not v_r.solto or jsonb_array_length(v_r.volumes) <> 1 then
    raise exception 'FALHA: p2 solto: solto %, volumes %', v_r.solto, v_r.volumes;
  end if;
end $$;

-- D7. O admin tambem nao escreve direto em pedido_volumes (so pela RPC),
--     mas le; e mexe em tipos_caixa.
do $$
declare
  v_n bigint;
begin
  begin
    insert into public.pedido_volumes (pedido_id, solto, volumes, salvo_em)
    values (current_setting('teste.fc_p3')::bigint, false, '[]'::jsonb, now());
    raise exception 'FALHA: admin inseriu direto em pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    update public.pedido_volumes set solto = true;
    raise exception 'FALHA: admin alterou direto pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    delete from public.pedido_volumes;
    raise exception 'FALHA: admin apagou direto de pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;

  select count(*) into v_n from public.pedido_volumes
   where pedido_id in (current_setting('teste.fc_p1')::bigint, current_setting('teste.fc_p2')::bigint);
  if v_n <> 2 then
    raise exception 'FALHA: admin le % de 2 linhas de pedido_volumes', v_n;
  end if;

  -- tipos_caixa: admin cria, altera, e as regras valem.
  insert into public.tipos_caixa (nome, capacidade) values ('Teste caixa fc', 5);
  update public.tipos_caixa set capacidade = 6, mistura_sabores = false
   where nome = 'Teste caixa fc';
  select count(*) into v_n from public.tipos_caixa
   where nome = 'Teste caixa fc' and capacidade = 6 and not mistura_sabores and ativo;
  if v_n <> 1 then
    raise exception 'FALHA: admin nao criou/alterou tipo de caixa';
  end if;
  begin
    insert into public.tipos_caixa (nome, capacidade) values ('  TESTE CAIXA fc ', 7);
    raise exception 'FALHA: nome de tipo repetido (maiusculas/espacos) aceito';
  exception when sqlstate '23505' then
    null;
  end;
  begin
    insert into public.tipos_caixa (nome, capacidade) values ('Teste capacidade fc', 0);
    raise exception 'FALHA: capacidade 0 aceita';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    insert into public.tipos_caixa (nome, capacidade) values ('   ', 3);
    raise exception 'FALHA: nome so com espacos aceito';
  exception when sqlstate '23514' then
    null;
  end;

  -- Apagar o tipo em uso zera o tipo do produto (on delete set null).
  update public.produtos set tipo_caixa_id = (select id from public.tipos_caixa where nome = 'Teste caixa fc')
   where id = current_setting('teste.fc_prod_base')::bigint + 2;
  delete from public.tipos_caixa where nome = 'Teste caixa fc';
  select count(*) into v_n from public.produtos
   where id = current_setting('teste.fc_prod_base')::bigint + 2 and tipo_caixa_id is null;
  if v_n <> 1 then
    raise exception 'FALHA: apagar tipo de caixa nao zerou produtos.tipo_caixa_id';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- E. Vendedor comum (-920).
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fc_uid_vend'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_n   bigint;
  v_vol jsonb := '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8},
                                                         {"nome":"Pudim teste","quantidade":5}]}]'::jsonb;
begin
  if public.app_meu_codigo() is distinct from '-920' or public.app_is_admin() then
    raise exception 'FALHA: -920 nao e vendedor comum (codigo %)', public.app_meu_codigo();
  end if;

  -- A RPC: 42501 (antes de olhar se o pedido existe).
  begin
    perform public.pedido_salvar_volumes(current_setting('teste.fc_p1')::bigint, false, v_vol);
    raise exception 'FALHA: vendedor comum executou pedido_salvar_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(-1, false, v_vol);
    raise exception 'FALHA: vendedor comum executou pedido_salvar_volumes (pedido inexistente)';
  exception when sqlstate '42501' then
    null;
  end;

  -- Nao le pedido_volumes nem tipos_caixa: 0 linhas (existem 2 e 3).
  select count(*) into v_n from public.pedido_volumes;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum le % linha(s) de pedido_volumes', v_n;
  end if;
  select count(*) into v_n from public.tipos_caixa;
  if v_n <> 0 then
    raise exception 'FALHA: vendedor comum le % linha(s) de tipos_caixa', v_n;
  end if;

  -- Nao escreve direto.
  begin
    insert into public.pedido_volumes (pedido_id, solto, volumes, salvo_em)
    values (current_setting('teste.fc_p1')::bigint, false, '[]'::jsonb, now());
    raise exception 'FALHA: vendedor comum inseriu direto em pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.tipos_caixa (nome, capacidade) values ('Teste vendedor fc', 5);
    raise exception 'FALHA: vendedor comum inseriu em tipos_caixa';
  exception when sqlstate '42501' then
    null;
  end;

  -- produtos.tipo_caixa_id: todos leem (a politica de produtos nao mudou).
  select count(*) into v_n from public.produtos
   where id = current_setting('teste.fc_prod_base')::bigint + 1 and tipo_caixa_id is not null;
  if v_n <> 1 then
    raise exception 'FALHA: vendedor comum nao le produtos.tipo_caixa_id';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- F. Conta autenticada sem vendedor: 42501 na RPC e 0 linhas nas tabelas.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('teste.fc_uid_sem'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare
  v_n bigint;
begin
  begin
    perform public.pedido_salvar_volumes(current_setting('teste.fc_p1')::bigint, false,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8},
                                               {"nome":"Pudim teste","quantidade":5}]}]'::jsonb);
    raise exception 'FALHA: conta sem vendedor executou pedido_salvar_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  select count(*) into v_n from public.pedido_volumes;
  if v_n <> 0 then
    raise exception 'FALHA: conta sem vendedor le % linha(s) de pedido_volumes', v_n;
  end if;
  select count(*) into v_n from public.tipos_caixa;
  if v_n <> 0 then
    raise exception 'FALHA: conta sem vendedor le % linha(s) de tipos_caixa', v_n;
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- G1. anon: sem acesso a nada.
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_n bigint;
begin
  begin
    select count(*) into v_n from public.tipos_caixa;
    raise exception 'FALHA: anon leu tipos_caixa';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    select count(*) into v_n from public.pedido_volumes;
    raise exception 'FALHA: anon leu pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    insert into public.pedido_volumes (pedido_id, solto, volumes, salvo_em)
    values (current_setting('teste.fc_p1')::bigint, false, '[]'::jsonb, now());
    raise exception 'FALHA: anon inseriu em pedido_volumes';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.pedido_salvar_volumes(current_setting('teste.fc_p1')::bigint, false,
      '[{"tipo":"avulso","caixa":null,"itens":[{"nome":"Copo teste 160g","quantidade":8}]}]'::jsonb);
    raise exception 'FALHA: anon executou pedido_salvar_volumes';
  exception when sqlstate '42501' then
    null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims', '', true);

-- G2. Sem JWT: os pedidos nao mudaram, estrutura e permissoes.
do $$
declare
  v_n  bigint;
  v_s  numeric;
  v_fn regprocedure := 'public.pedido_salvar_volumes(bigint, boolean, jsonb)'::regprocedure;
begin
  if current_user <> 'postgres' then
    raise exception 'FALHA: teste precisa rodar como postgres (roda como %)', current_user;
  end if;

  -- Pedidos: mesma contagem e mesma soma de antes das chamadas da RPC.
  select count(*), coalesce(sum(total), 0) into v_n, v_s from public.pedidos;
  if v_n <> current_setting('teste.fc_ped_n')::bigint
     or v_s <> current_setting('teste.fc_ped_soma')::numeric then
    raise exception 'FALHA: pedidos mudaram (count % -> %, soma % -> %)',
      current_setting('teste.fc_ped_n'), v_n, current_setting('teste.fc_ped_soma'), v_s;
  end if;

  -- RLS ligada nas duas tabelas.
  select count(*) into v_n from pg_class
   where oid in ('public.tipos_caixa'::regclass, 'public.pedido_volumes'::regclass)
     and relrowsecurity;
  if v_n <> 2 then
    raise exception 'FALHA: RLS ligada em % de 2 tabelas novas', v_n;
  end if;

  -- Privilegios das tabelas.
  if has_table_privilege('anon', 'public.tipos_caixa', 'select')
     or has_table_privilege('anon', 'public.pedido_volumes', 'select') then
    raise exception 'FALHA: anon com select nas tabelas novas';
  end if;
  if not has_table_privilege('authenticated', 'public.pedido_volumes', 'select') then
    raise exception 'FALHA: authenticated sem select em pedido_volumes';
  end if;
  if has_table_privilege('authenticated', 'public.pedido_volumes', 'insert')
     or has_table_privilege('authenticated', 'public.pedido_volumes', 'update')
     or has_table_privilege('authenticated', 'public.pedido_volumes', 'delete') then
    raise exception 'FALHA: authenticated escreve direto em pedido_volumes';
  end if;
  if not (has_table_privilege('authenticated', 'public.tipos_caixa', 'select')
          and has_table_privilege('authenticated', 'public.tipos_caixa', 'insert')
          and has_table_privilege('authenticated', 'public.tipos_caixa', 'update')
          and has_table_privilege('authenticated', 'public.tipos_caixa', 'delete')) then
    raise exception 'FALHA: authenticated sem acesso completo a tipos_caixa (a RLS limita a admin)';
  end if;

  -- Politicas: tipos_caixa so a de admin; pedido_volumes so a de leitura.
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'tipos_caixa';
  if v_n <> 1 then
    raise exception 'FALHA: % politicas em tipos_caixa (esperada 1)', v_n;
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'pedido_volumes' and cmd = 'SELECT';
  if v_n <> 1 then
    raise exception 'FALHA: % politicas de select em pedido_volumes (esperada 1)', v_n;
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'pedido_volumes' and cmd <> 'SELECT';
  if v_n <> 0 then
    raise exception 'FALHA: pedido_volumes com % politica(s) de escrita', v_n;
  end if;

  -- produtos.tipo_caixa_id: bigint, nulo, apaga-vira-nulo.
  select count(*) into v_n from information_schema.columns
   where table_schema = 'public' and table_name = 'produtos'
     and column_name = 'tipo_caixa_id' and data_type = 'bigint' and is_nullable = 'YES';
  if v_n <> 1 then
    raise exception 'FALHA: coluna produtos.tipo_caixa_id fora do esperado';
  end if;
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.produtos'::regclass and contype = 'f'
     and confrelid = 'public.tipos_caixa'::regclass and confdeltype = 'n';
  if v_n <> 1 then
    raise exception 'FALHA: FK de produtos.tipo_caixa_id para tipos_caixa com on delete set null';
  end if;

  -- RPC: uma versao so, security definer com search_path vazio; authenticated
  -- executa, anon e PUBLIC nao.
  select count(*) into v_n from pg_proc
   where proname = 'pedido_salvar_volumes' and pronamespace = 'public'::regnamespace;
  if v_n <> 1 then
    raise exception 'FALHA: % versoes de pedido_salvar_volumes (esperada 1)', v_n;
  end if;
  select count(*) into v_n from pg_proc
   where oid = v_fn and prosecdef and proconfig @> array['search_path=""'];
  if v_n <> 1 then
    raise exception 'FALHA: pedido_salvar_volumes sem security definer / search_path vazio';
  end if;
  if not has_function_privilege('authenticated', v_fn::oid, 'execute') then
    raise exception 'FALHA: authenticated sem EXECUTE em pedido_salvar_volumes';
  end if;
  if has_function_privilege('anon', v_fn::oid, 'execute') then
    raise exception 'FALHA: anon executa pedido_salvar_volumes';
  end if;
  select count(*) into v_n
    from pg_proc p, aclexplode(p.proacl) a
   where p.oid = v_fn and a.grantee = 0 and a.privilege_type = 'EXECUTE';
  if v_n <> 0 then
    raise exception 'FALHA: PUBLIC executa pedido_salvar_volumes';
  end if;

  if coalesce(current_setting('milkdim.acao_controle', true), '') = '1' then
    raise exception 'FALHA: milkdim.acao_controle ligada no fim do teste';
  end if;
end $$;

select 'etiqueta_caixas_test: OK' as resultado;
