# Fase A — Fluxo do pedido: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hoje o pedido só aparece no Controle depois de assinado e finalizado. Com esta fase,
o pedido salvo sem assinatura passa a ir para o servidor como "em aberto". O Controle ganha a
aba Produção, com os totais por produto e a finalização manual, e o vendedor passa a poder
cancelar pedidos.

**Architecture:**
- **Tabela:** continua uma só, `pedidos`, com a situação `salvo` (em aberto), `finalizado` ou
  `cancelado`.
- **Servidor:** dois gatilhos no Postgres preenchem as datas e os autores e protegem os
  pedidos fechados. O Controle muda a situação só por RPCs.
- **App do vendedor:** reaproveita o envio que já existe (upsert por número e vendedor, eco do
  servidor gravado no SQLite e `pendente_envio`) e passa a usá-lo para pedidos de qualquer
  situação.
- **Identidade do pedido:** cada pedido recebe o identificador `id_aparelho`, gerado no
  celular, para distinguir "o mesmo pedido reenviado" de "outro pedido com o mesmo número".

**Tech Stack:**
- Flutter 3.41.1 / Dart 3.11, `supabase_flutter`, `sqflite`
- testes com `sqflite_common_ffi` e `flutter_test`
- Supabase Postgres 17, acessado pelo MCP `execute_sql` (testes em `begin … rollback`)

**Spec:** `docs/superpowers/specs/2026-11-23-fase-a-fluxo-do-pedido-design.md`

## Global Constraints

- **Credenciais:** nenhuma senha, chave, URL ou ref do projeto Supabase entra em arquivo
  versionado. O repositório é público.
- **Banco real:** nada é aplicado sem mostrar o SQL ao Kaiki e receber OK no chat. Os testes
  em `begin … rollback` também esperam esse OK.
- **Pedido local:** nunca é apagado por login, logout, sessão vencida, sincronização,
  cancelamento ou finalização no Controle.
- **Textos fixos, exatamente assim:**
  - "Pedido enviado para produção."
  - "Pedido salvo. Será enviado quando houver internet." (o texto atual, sem mudança)
  - "Este pedido já foi finalizado no Controle."
  - "Número já usado; troque o número"
  - "Não enviado"
  - "Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale a dele."
  - "Nenhum pedido em aberto"
- **Situações na tela:** "Em aberto" (`salvo`), "Finalizado" (`finalizado`) e "Cancelado"
  (`cancelado`).
- **Atualização da Produção:** a cada 30 s.
- **Visual:** tudo usa os componentes e tokens do `packages/milkdim_ui`. Nada de cor escrita
  à mão.
- **Commits:** só quando o Kaiki pedir. Ao final de cada tarefa, deixe o commit preparado
  (arquivos e mensagem) e pergunte. A mensagem termina com
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Testes que já existem:** continuam passando (app 56, admin 30, pacote 25), e
  `flutter analyze` não pode ganhar avisos novos.

## Review Focus

1. **Admin no app do vendedor.** O 0002 é admin e também vendedor no app. Uma edição velha
   enviada pelo celular dele não pode reabrir nem sobrescrever um pedido fechado. Por isso a
   proteção não pode depender de `app_is_admin()`, e sim de a mudança vir por RPC do Controle
   (teste no Task 1).
2. **Eco perdido.** O envio chegou ao servidor, mas a resposta se perdeu, e o celular
   reenvia. O reenvio não pode virar "Número já usado" (teste no Task 3).
3. **Dois aparelhos com o mesmo código, sem internet**, e o mesmo número de pedido. O segundo
   pedido não pode sobrescrever o primeiro no servidor (teste no Task 3).
4. **Eco do servidor.** O pedido aberto que o vendedor acabou de enviar não pode ser duplicado
   pela sincronização, nem realocado para um id local (teste no Task 3).
5. **APK antigo depois da migração.** O insert de um pedido finalizado sem `id_aparelho`
   continua funcionando e preenche `finalizado_em` (teste no Task 1).

---

### Task 1: Migração do banco (colunas, gatilhos, RPCs)

**Files:**
- Create: `supabase/migrations/20261123000001_fase_a_fluxo_pedido.sql`
- Create: `supabase/tests/fase_a_test.sql`

**Interfaces:**
- Produces:
  - **Colunas em `pedidos`:**
    - `id_aparelho uuid null`, com índice único parcial `where id_aparelho is not null`;
    - `enviado_em timestamptz not null default now()`;
    - `alterado_em timestamptz`;
    - `finalizado_em timestamptz`, `finalizado_por text`,
      `finalizado_manual boolean not null default false`;
    - `cancelado_em timestamptz`, `cancelado_por text`.
  - **Constraint:** `pedidos_status_check check (status in ('salvo','finalizado','cancelado'))`.
  - **RPCs** (`security definer`, `set search_path = ''`, só admin, erro `42501` para os
    outros):
    - `public.pedido_finalizar_manual(p_id bigint) returns void`
    - `public.pedido_cancelar(p_id bigint) returns void`
  - **O vendedor cancela** com um UPDATE comum (`status = 'cancelado'`), coberto pela RLS que
    já existe.

- [ ] **Step 1: Conferir os dados atuais (só leitura)**

  Run (MCP `execute_sql`):
  `select status, count(*) from pedidos group by 1;`

  Expected: só `finalizado`. Se aparecer outro valor, pare e mostre ao Kaiki antes de seguir.

- [ ] **Step 2: Escrever `fase_a_test.sql`.** Cada bloco termina em `assert`/`raise exception`
  se falhar, no mesmo estilo do `supabase/tests/fase3_test.sql`. Os vendedores de teste são
  criados dentro da transação.

  **Inserção:**
  - Um vendedor (não admin) insere `salvo` com `id_aparelho`. Resultado: `enviado_em`
    preenchido, `finalizado_em` nulo.
  - Insert `finalizado` sem `id_aparelho` (caso do APK antigo). Resultado: `finalizado_em`
    não nulo e `finalizado_por` = código do vendedor.

  **`alterado_em`:**
  - O vendedor muda a `quantidade` em `produtos` de um `salvo`: `alterado_em` passa a ter
    valor.
  - Mudar só `datahora`: `alterado_em` não muda.

  **Pedido fechado contra edição do celular:**
  - Depois de `pedido_finalizar_manual`, o vendedor dá UPDATE com `status = 'salvo'`:
    continua `finalizado` e `finalizado_manual = true`.
  - O mesmo vale para o admin 0002, agindo como vendedor por UPDATE direto: continua
    `finalizado`.

  **Entrega assinada vence:**
  - Depois de `pedido_finalizar_manual`, o vendedor envia `finalizado` com `assinatura` e
    quantidade diferente. Resultado:
    - a quantidade nova fica;
    - `finalizado_manual = false`;
    - `finalizado_por` = código do vendedor.
  - Depois de `pedido_cancelar`, o vendedor envia `finalizado` com `assinatura`. Resultado:
    - fica `finalizado`;
    - `cancelado_em` continua preenchido.

  **Pedido já assinado não é substituído:**
  - Um pedido `finalizado` com assinatura recebe um envio `finalizado` com outra assinatura:
    nada muda.

  **Datas e autores não vêm do cliente:**
  - O vendedor manda `finalizado_por = 'X'`: o valor é ignorado.

  **Permissões das RPCs:**
  - Um vendedor não admin chama `pedido_finalizar_manual`: erro `42501`.
  - `pedido_cancelar` num pedido `finalizado`: erro.

  **Constraint:**
  - Insert com `status = 'rascunho'`: viola `pedidos_status_check`.

- [ ] **Step 3: Rodar o teste sem a migração, para ver falhar**

  Antes, mostre o teste ao Kaiki e peça OK.

  Run (MCP): `begin;` + `fase_a_test.sql` + `rollback;`

  Expected: falha por coluna inexistente (`id_aparelho`).

- [ ] **Step 4: Escrever a migração**
  - **Colunas e constraint:** as do Interfaces.
  - **Backfill:** `enviado_em = datahora`; para os `finalizado`, `finalizado_em = datahora` e
    `finalizado_por = vendedor_codigo`.
  - **`pedidos_antes_inserir` (BEFORE INSERT):**
    - `enviado_em := now()`;
    - zera `alterado_em`, `cancelado_*` e `finalizado_manual`;
    - se `status = 'finalizado'`: `finalizado_em := now()` e
      `finalizado_por := app_meu_codigo()`; senão, ambos nulos.
  - **`pedidos_antes_alterar` (BEFORE UPDATE):** os dois gatilhos são `security definer`.
    Regra, nesta ordem:

    ```
    se current_setting('milkdim.acao_controle', true) = '1': aceita NEW como veio (as RPCs
      já gravaram os campos de auditoria); retorna NEW.
    NEW.enviado_em := OLD.enviado_em; NEW.id_aparelho := coalesce(OLD.id_aparelho, NEW.id_aparelho)
    se OLD.status in ('finalizado','cancelado'):
      se NEW.status = 'finalizado' e NEW.assinatura is not null e
         (OLD.status = 'cancelado' ou OLD.finalizado_manual):
           finalizado_em := now(); finalizado_por := app_meu_codigo(); finalizado_manual := false
           mantém cancelado_em/cancelado_por de OLD; retorna NEW
      senão: retorna OLD   -- ignora em silêncio; o eco devolve a versão do servidor
    -- OLD.status = 'salvo'
    se NEW.produtos, NEW.cliente_id ou NEW.cliente_nome distintos de OLD (is distinct from):
      alterado_em := now()  senão alterado_em := OLD.alterado_em
    se NEW.status = 'finalizado': finalizado_em := now(); finalizado_por := app_meu_codigo();
      finalizado_manual := false
    se NEW.status = 'cancelado': cancelado_em := now(); cancelado_por := app_meu_codigo()
    senão: copia finalizado_*/cancelado_* de OLD
    ```

  - **RPCs:** ambas aceitam só `status = 'salvo'`; qualquer outro levanta erro.
    - Cada uma checa `app_is_admin()`.
    - Liga `set_config('milkdim.acao_controle','1', true)`.
    - Faz o UPDATE gravando:
      - finalizar: `finalizado_*`, com `finalizado_manual = true`;
      - cancelar: `cancelado_*`.
  - **Permissões:** `revoke execute … from public, anon` e
    `grant execute … to authenticated`.
  - **Gatilhos de último pedido:** os que já existem ficam como estão.

- [ ] **Step 5: Rodar migração + teste em transação**

  Run (MCP): `begin;` + migração + `fase_a_test.sql` + `rollback;`

  Expected: termina sem exceção.

- [ ] **Step 6: Mostrar a migração ao Kaiki e aplicar com OK**

  Run (MCP): `begin;` + migração + `commit;`

  Expected:
  - `select count(*) from pedidos where finalizado_em is null and status='finalizado'` = 0;
  - o APK atual continua salvando (repita o insert do teste do APK antigo em
    `begin … rollback`).

- [ ] **Step 7: Commit preparado**: `feat(db): fase A — situacoes do pedido, auditoria e protecao de pedido fechado`

---

### Task 2: Banco local do app (SQLite v17)

**Files:**
- Modify: `app/lib/utils/db.dart` (versão, `onUpgrade`, `salvarPedidoLocal`,
  `atualizarPedidoLocal`, listagens)
- Create: `app/lib/utils/id_aparelho.dart`
- Test: `app/test/fluxo_pedido_local_test.dart`

**Interfaces:**
- Produces:
  - **`_dbVersion = 17`.**
  - **Colunas locais em `pedidos`:**
    - `id_aparelho TEXT`;
    - `so_local INTEGER NOT NULL DEFAULT 0`;
    - `erro_envio TEXT`;
    - `enviado_em`, `alterado_em`, `finalizado_em`, `finalizado_por`, `finalizado_manual`,
      `cancelado_em` e `cancelado_por`, todas `TEXT`, cópia do servidor.
  - **Tabela local `pedidos_descartados`:** `id INTEGER PK AUTOINCREMENT`,
    `descartado_em TEXT`, `motivo TEXT`, `pedido_json TEXT`.
  - **Funções:**
    - `String novoIdAparelho()`: UUID v4 com `Random.secure()`, sem pacote novo.
    - `Future<void> guardarVersaoDescartada(Map<String, dynamic> pedido, String motivo)`
    - `bool jaChegouAoServidor(Map<String, dynamic> pedido)`: `id < kLocalIdBase`.
    - `Future<List<Map<String, dynamic>>> listarPedidosLocaisPorStatus(String vendedorCodigo, String status)`
  - **Regras de `pendente_envio`** (em `salvarPedidoLocal` e `atualizarPedidoLocal`):
    - passa a ser `1` para qualquer situação;
    - exceção: `so_local = 1` faz `pendente_envio = 0`.
  - **`id_aparelho`:** vem do mapa ou é gerado com `novoIdAparelho()` na primeira gravação, e
    nunca é trocado depois.

- [ ] **Step 1: Escrever os testes**

  **Pendente para qualquer situação:**
  - `salvo novo vira pendente e ganha id_aparelho`: depois de
    `salvarPedidoLocal({status:'salvo', numero:'7', vendedor_codigo:'0003'})`, a linha tem
    `pendente_envio == 1` e `id_aparelho` com 36 caracteres.
  - `id_aparelho nao muda ao regravar`: depois de `atualizarPedidoLocal` do mesmo pedido, o
    `id_aparelho` é igual ao anterior.
  - `cancelado tambem fica pendente`: depois de `atualizarPedidoLocal` com
    `status:'cancelado'`, `pendente_envio == 1`.

  **Rascunhos antigos (upgrade v16 → v17):**
  - `v16 para v17 marca rascunhos antigos como so_local`. Arrange: crie o banco na versão 16
    com `openDatabase(version: 16)`, usando o esquema real via o `onCreate` atual com a
    versão forçada. Insira `salvo` com id ≥ `kLocalIdBase` e `pendente_envio = 0`, e um
    `finalizado` com `pendente_envio = 1`. Resultado depois de abrir com `getDb()`:
    - o rascunho tem `so_local == 1` e `pendente_envio == 0`;
    - o finalizado continua `so_local == 0` e `pendente_envio == 1`.
  - `salvar um so_local tira a marca e envia`: `atualizarPedidoLocal` de um `so_local` com
    `so_local: 0` deixa `pendente_envio == 1`.

  **Outros:**
  - `guardarVersaoDescartada grava json`: depois da chamada, 1 linha em
    `pedidos_descartados` cujo `pedido_json` decodificado tem o mesmo `numero`.
  - `jaChegouAoServidor`: `{id: 42}` é true; `{id: kLocalIdBase + 1}` e `{}` são false.

- [ ] **Step 2: Rodar e ver falhar**

  Run: `cd app && flutter test test/fluxo_pedido_local_test.dart`

  Expected: FAIL (colunas e funções inexistentes).

- [ ] **Step 3: Implementar em `db.dart` e `id_aparelho.dart`**

  O upgrade `oldV < 17`:
  - cria as colunas com `_ensureColumn`;
  - cria a tabela;
  - roda
    `UPDATE pedidos SET so_local = 1 WHERE status = 'salvo' AND id >= kLocalIdBase AND pendente_envio = 0`.

  O `onCreate` também cria tudo isso, para instalações novas.

- [ ] **Step 4: Rodar todos os testes do app**

  Run: `cd app && flutter test`

  Expected: PASS. A lógica nova não pode quebrar os 56 testes que já existem.

- [ ] **Step 5: Commit preparado**: `feat(app): SQLite v17 — pedido aberto pendente, id_aparelho e rascunhos antigos so_local`

---

### Task 3: Envio, eco e sincronização do app

**Files:**
- Modify: `app/lib/utils/supabase_helper.dart`
  - `aplicarPedidosRemotos` (linhas 263-349)
  - `_salvarPedidoSupabase` (496-596)
  - `aplicarEcoDoServidor` (615-680)
  - `ResultadoGravacao` / `gravarPedidoEEnviar` (682-715)
- Test: `app/test/fluxo_pedido_envio_test.dart`

**Interfaces:**
- Consumes: Task 2 (`id_aparelho`, `so_local`, `erro_envio`, `guardarVersaoDescartada`,
  `jaChegouAoServidor`).
- Produces:
  - **`enum ResultadoGravacao`:** `{ rascunho, enviado, pendente, fechadoNoControle, numeroEmUso }`.
    - `rascunho`: só para `so_local`.
    - `enviado`: vale para qualquer situação.
  - **`class NumeroEmUso implements Exception`:** lançada pelo envio quando o servidor tem o
    mesmo `(numero, vendedor_codigo)` com outro `id_aparelho` não nulo.
  - **`Future<bool> numeroLivreNoServidor(String numero, String vendedorCodigo)`:** devolve
    true se a consulta falhar por falta de rede.
  - **`ResultadoEco`:** `aplicarEcoDoServidor` passa a devolver
    `enum ResultadoEco { aplicado, edicaoLocalMaisNova, servidorFechou }`.
    - `servidorFechou`: o remoto está `finalizado` ou `cancelado` e diferente do que foi
      enviado. O local vai para `guardarVersaoDescartada(…, 'fechado no Controle')`, e o eco
      é aplicado.
  - **`gravarPedidoEEnviar`:** a assinatura não muda. O resultado agora:
    - `so_local = 1` → `rascunho`;
    - senão tenta enviar:
      - `NumeroEmUso` → grava `erro_envio = 'numero'`, mantém pendente e devolve
        `numeroEmUso`;
      - eco `servidorFechou` → `fechadoNoControle`;
      - falha de rede → `pendente`;
      - sucesso → `enviado`.
  - **Envio:** manda `id_aparelho` e também `status` `salvo` ou `cancelado`. Os campos
    `so_local`, `erro_envio` e os de auditoria não vão no payload; o servidor é quem os
    preenche. Antes do upsert, se o pedido ainda não chegou ao servidor
    (`!jaChegouAoServidor`), busca `id, id_aparelho` por `(numero, vendedor_codigo)`:
    - mesmo `id_aparelho`, ou remoto com `id_aparelho` nulo → segue como hoje;
    - outro `id_aparelho` → lança `NumeroEmUso`.
  - **`subirPedidosPendentes`:** pula as linhas com `erro_envio = 'numero'` (não conta como
    falha, só é contada à parte). Para isso o retorno ganha `numeroEmUso`:
    `({int enviados, int falhas, int numeroEmUso})`.
  - **`aplicarPedidosRemotos`:** um local `salvo` com o mesmo id do remoto **e** o mesmo
    `(numero, vendedor_codigo)` é o próprio pedido e não é realocado. Só realoca quando o
    `(numero, vendedor_codigo)` difere.

- [ ] **Step 1: Escrever os testes**

  Os testes usam um `enviar`/cliente falso: as funções recebem o envio por parâmetro, como
  já faz `envio_pendentes_test.dart`. Para `NumeroEmUso` e eco, extraia a decisão para
  funções puras testáveis:
  - `ResultadoEco decidirEco(Map local, Map enviado, Map remoto)`
  - `bool conflitoDeNumero(String? idAparelhoLocal, String? idAparelhoRemoto)`

  **Conflito de número:**
  - `conflitoDeNumero`:
    - `('a','a')` é false;
    - `('a', null)` é false;
    - `('a','b')` é true;
    - `(null,'b')` é false: o pedido local é legado e mantém o comportamento de hoje.
  - `eco perdido nao vira numero em uso`: o pedido local foi enviado (o servidor já tem
    `id_aparelho` igual), mas o eco não voltou e o local continua com id ≥ `kLocalIdBase`.
    No reenvio o resultado é `enviado`, não `numeroEmUso`.
  - `dois aparelhos mesmo numero`: o servidor tem `(numero '5', '0003', id_aparelho 'b')` e o
    local, `'a'`. Resultado:
    - `numeroEmUso`;
    - a linha local fica com `erro_envio = 'numero'` e `pendente_envio = 1`;
    - o servidor falso não recebeu update.

  **Eco do servidor:**
  - `decidirEco`:
    - o local enviado `salvo` volta `finalizado` manual → `servidorFechou`;
    - o enviado volta igual → `aplicado`;
    - o local mudou depois do envio → `edicaoLocalMaisNova`, como é hoje.
  - `servidor fechou guarda a versao local`: depois de
    `aplicarEcoDoServidor(... remoto finalizado ...)`:
    - `pedidos_descartados` tem 1 linha;
    - o SQLite mostra `finalizado`.

  **Sincronização:**
  - `sync nao duplica pedido aberto ja enviado`:
    - local `{id: 500, numero:'9', vendedor:'0003', status:'salvo', pendente_envio:0}`;
    - `aplicarPedidosRemotos([{id:500, numero:'9', vendedor_codigo:'0003', status:'salvo'}])`;
    - resultado: 1 linha com `numero = '9'` e `id = 500`.
  - `sync ainda protege rascunho de outro numero`: o teste que já existe em
    `rascunho_persistencia_test.dart` continua passando, sem alteração.

  **Envio e gravação:**
  - `subirPedidosPendentes pula numero em uso`: um pendente com `erro_envio = 'numero'` não
    é passado ao `enviar` e conta em `numeroEmUso`.
  - `gravarPedidoEEnviar salvo enviado`: com um `enviar` falso que dá certo e um pedido
    `salvo`, o resultado é `enviado`. Esse resultado é o que mostra "Pedido enviado para
    produção." no Task 4.

- [ ] **Step 2: Rodar e ver falhar**

  Run: `cd app && flutter test test/fluxo_pedido_envio_test.dart`

  Expected: FAIL.

- [ ] **Step 3: Implementar em `supabase_helper.dart`** as mudanças do Interfaces. Atualize
  os usos do retorno de `subirPedidosPendentes` em `home_page.dart`/`pedidos_page.dart`
  (procure por `.falhas`).

- [ ] **Step 4: Rodar todos os testes do app**

  Run: `cd app && flutter test`

  Expected: PASS.

- [ ] **Step 5: Commit preparado**: `feat(app): envio de pedido aberto e cancelado, conflito de numero por id_aparelho e eco de pedido fechado`

---

### Task 4: Telas do app do vendedor

**Files:**
- Modify:
  - `app/lib/pages/pedido_page.dart` (`_salvarPedido`, linhas ~265-340)
  - `app/lib/pages/pedido_edit_page.dart` (`_atualizarPedido` ~300-345, campo número ~66)
  - `app/lib/pages/pedidos_page.dart` (`_apagarPedidoSalvo` 137, abas 1108-1160, item 520-540)
  - `app/lib/widgets/pedido_ui.dart`
- Create: `app/lib/utils/regras_pedido.dart`
- Test: `app/test/regras_pedido_test.dart`; `app/test/visual/telas_test.dart` (capturas novas)

**Interfaces:**
- Consumes:
  - Task 2: `jaChegouAoServidor`, `so_local`, `erro_envio`;
  - Task 3: `ResultadoGravacao`, `numeroLivreNoServidor`.
- Produces, as funções puras de `regras_pedido.dart`:
  - `bool numeroEditavel(Map<String, dynamic> p)`: true se `!jaChegouAoServidor(p)` ou se
    `erro_envio == 'numero'`.
  - `enum AcaoRemover { cancelar, apagarDoAparelho, nenhuma }` e
    `AcaoRemover acaoRemover(Map<String, dynamic> p)`:
    - `salvo` com `so_local = 1` → `apagarDoAparelho`;
    - `salvo` que já chegou ao servidor ou está pendente → `cancelar`;
    - qualquer outro caso → `nenhuma`.
  - `String mensagemGravacao(ResultadoGravacao r)`:
    - `enviado` + `salvo` → "Pedido enviado para produção.";
    - `pendente` → "Pedido salvo. Será enviado quando houver internet.";
    - `fechadoNoControle` → "Este pedido já foi finalizado no Controle.";
    - `numeroEmUso` → "Número já usado; troque o número".

  O `enviado` de um `finalizado` mantém o comportamento atual (sem mensagem nova). Por isso
  a assinatura recebe o status: `String? mensagemGravacao(ResultadoGravacao r, String status)`.

- [ ] **Step 1: Testes de `regras_pedido_test.dart`** com os casos exatos do Interfaces: uma
  asserção para cada ramo das três funções, inclusive `mensagemGravacao(enviado,
  'finalizado') == null`.

- [ ] **Step 2: Rodar e ver falhar**

  Run: `cd app && flutter test test/regras_pedido_test.dart`

  Expected: FAIL.

- [ ] **Step 3: Implementar `regras_pedido.dart` e ligar nas telas**
  - **Pedido novo (`pedido_page`), ao salvar:**
    - com internet, chama `numeroLivreNoServidor`. Se o número estiver ocupado, mostra
      "Número já usado; troque o número" e preenche o campo com o próximo livre, usando a
      lógica de `buscarUltimoNumeroPedido` + 1 até achar um livre (máximo de 20 tentativas);
    - mostra `mensagemGravacao`.
  - **Edição (`pedido_edit_page`):** o campo número fica `readOnly` quando
    `!numeroEditavel(p)`.
  - **Meus pedidos (`pedidos_page`):**
    - **Abas:** passam a ser "Em aberto (n)", "Finalizados (n)" e "Cancelados (n)". A aba
      "Salvos" é a atual e só muda de nome.
    - **Botão do item:** segue `acaoRemover`. "Cancelar pedido" pede confirmação, grava
      `status: 'cancelado'` com `atualizarPedidoLocal` e chama `gravarPedidoEEnviar`.
    - **Selos:** `so_local` mostra `MdStatusChip` "Não enviado" (tipo aviso);
      `erro_envio = 'numero'` mostra o chip de erro "Número já usado; troque o número".
    - **Banner de pendentes:** passa a contar os abertos e os cancelados pendentes. A contagem
      já vem de `contarPedidosPendentesEnvio`, então nada muda nessa função.

- [ ] **Step 4: Capturas e testes**

  Run: `cd app && flutter test && flutter test --tags visual`

  Expected: PASS e PNGs novos em `app/build/visual/`:
  - `meus_pedidos_cancelados.png`
  - `pedido_nao_enviado.png`

  Os dados das capturas são falsos, sem nome de cliente real.

- [ ] **Step 5: Commit preparado**: `feat(app): pedido enviado para producao, cancelar pedido e numero travado apos envio`

---

### Task 5: Modelo e serviço do Controle

**Files:**
- Modify:
  - `admin/lib/models/pedido.dart` (campos e `fromMap`)
  - `admin/lib/services/supabase_service.dart`
- Create: `admin/lib/models/producao.dart`
- Test: `admin/test/producao_test.dart`

**Interfaces:**
- Produces:
  - **`Pedido` ganha campos:**
    - `DateTime? enviadoEm`, `DateTime? alteradoEm`, `DateTime? finalizadoEm`,
      `String? finalizadoPor`, `bool finalizadoManual`;
    - `DateTime? canceladoEm`, `String? canceladoPor`;
    - os getters `bool get alteradoDepoisDeEnviar` (`alteradoEm` depois de `enviadoEm`) e
      `String get situacaoTexto` ("Em aberto" / "Finalizado" / "Cancelado"; outro valor
      aparece cru).
  - **`producao.dart`:**
    - `class TotalProduto { final String nome; final int quantidade; }`
    - `List<TotalProduto> totaisAFabricar(Iterable<Pedido> pedidos)`: considera só
      `status == 'salvo'`, soma `quantidade` por `nome` (com `trim`; letras maiúsculas e
      minúsculas contam como diferentes), ordena pela quantidade decrescente e, no empate,
      pelo nome.
  - **`SupabaseService`:**
    - `Future<List<Pedido>> buscarPedidosEmAberto()`: `status = 'salvo'`, ordem `enviado_em`
      crescente, com as colunas novas no select;
    - `Future<void> finalizarManual(int id)`: `rpc('pedido_finalizar_manual', params: {'p_id': id})`;
    - `Future<void> cancelarPedido(int id)`: `rpc('pedido_cancelar', …)`;
    - `buscarPedidos`/`paginarPedidos` incluem as colunas novas.
  - **Constante:** `String filtroSituacao(String? s)`: `null`/'todos' → sem filtro; senão o
    próprio status. `paginarPedidos` já aceita `status`.

- [ ] **Step 1: Testes de `producao_test.dart`**
  - **`totaisAFabricar soma por produto so dos abertos`:**
    - pedido A `salvo` com `[Pudim tradicional x10, Leite ninho x4]`;
    - pedido B `salvo` com `[Pudim tradicional x5]`;
    - pedido C `finalizado` com `[Leite ninho x99]`;
    - resultado: `[('Pudim tradicional',15), ('Leite ninho',4)]`.
  - **`empate ordena por nome`.**
  - **`nome com espacos agrupa`:** `'Leite ninho '` e `'Leite ninho'` viram um só item.
  - **`situacaoTexto`:** `salvo` → "Em aberto", `cancelado` → "Cancelado".
  - **`alteradoDepoisDeEnviar`:** é true quando `alteradoEm` é posterior; false quando nulo.

- [ ] **Step 2: Rodar e ver falhar**

  Run: `cd admin && flutter test test/producao_test.dart`

  Expected: FAIL.

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Rodar todos os testes do Controle**

  Run: `cd admin && flutter test`

  Expected: PASS (30 + novos).

- [ ] **Step 5: Commit preparado**: `feat(admin): modelo do pedido com situacao e auditoria, totais a fabricar e RPCs`

---

### Task 6: Telas do Controle (Produção, filtro, detalhe)

**Files:**
- Create: `admin/lib/tabs/producao_tab.dart`
- Modify:
  - `admin/lib/pages/home_page.dart` (`_tabs`, `_titles`, `_tabIcons`: Produção entra como
    **primeira** aba, com `Icons.factory_rounded`)
  - `admin/lib/tabs/pedidos_tab.dart` (filtro e detalhe)
- Test: `admin/test/producao_tab_test.dart`; `admin/test/visual/telas_test.dart`

**Interfaces:**
- Consumes: Task 5 (`totaisAFabricar`, `buscarPedidosEmAberto`, `finalizarManual`,
  `cancelarPedido`, os campos de `Pedido`).
- Produces: `ProducaoTab({Future<List<Pedido>> Function()? carregar, Future<void> Function(int)? finalizar, Future<void> Function(int)? cancelar, Duration intervalo = const Duration(seconds: 30)})`.
  As funções são pontos de teste com padrão no `SupabaseService`, no mesmo padrão de
  `PedidosTab.carregar`.

- [ ] **Step 1: Widget tests em `producao_tab_test.dart`**
  - **Totais e lista:** com 2 pedidos falsos abertos, aparecem "Pudim tradicional" e "15" e
    os dois números de pedido.
  - **Selo de alteração:** um pedido com `alteradoEm` posterior mostra o texto "alterado às".
  - **Estado vazio:** lista vazia mostra "Nenhum pedido em aberto".
  - **Finalizar:**
    - tocar em Finalizar abre o diálogo com o texto exato "Use só se o pedido já foi
      entregue. Se o vendedor finalizar com assinatura depois, vale a dele.";
    - confirmar chama `finalizar(id)` uma vez e recarrega a lista.
  - **Atualização automática:** com `intervalo: Duration(seconds: 30)`, `tester.pump(Duration(seconds: 31))`
    chama `carregar` de novo (2 chamadas no total).
  - **Saída da tela:** o timer é cancelado no `dispose`, e não sobra nenhum pendente no fim
    do teste.

- [ ] **Step 2: Rodar e ver falhar**

  Run: `cd admin && flutter test test/producao_tab_test.dart`

  Expected: FAIL.

- [ ] **Step 3: Implementar**
  - **Layout de `producao_tab.dart`:** `MdSectionHeader("A fabricar")` com a lista
    `TotalProduto`, depois `MdSectionHeader("Pedidos em aberto")` com os cartões.
  - **Cartão do pedido:** número, vendedor, cliente, "há X" desde `enviadoEm`, itens
    resumidos, chip "alterado às HH:MM" e os botões Finalizar (`FilledButton`) e Cancelar
    (`OutlinedButton` em `danger`, com confirmação).
  - **Tela larga (≥ 900):** totais e lista lado a lado. Tela estreita: um embaixo do outro.
  - **Atualização:** o `Timer.periodic` só atualiza se o widget estiver montado. Há também um
    botão "Atualizar".
  - **`pedidos_tab.dart`:**
    - `SegmentedButton` com Todos, Em aberto, Finalizados e Cancelados, que filtra a lista
      já carregada;
    - o chip mostra `situacaoTexto`, com o tipo: aberto = info, finalizado = sucesso,
      cancelado = neutro;
    - o detalhe mostra enviado em, alterado em, finalizado em/por (com "(manual)") e
      cancelado em/por.
  - **`home_page.dart`:** a ordem das abas fica Produção, Vendedores, Produtos, Pedidos,
    Clientes. O `indiceInicial` padrão continua 0, então a Produção abre primeiro.

- [ ] **Step 4: Testes e capturas**

  Run: `cd admin && flutter test && flutter test --tags visual`

  Expected: PASS e PNGs novos:
  - `producao_estreita.png`
  - `producao_larga.png`
  - `pedidos_filtro.png`

- [ ] **Step 5: Commit preparado**: `feat(admin): aba Producao com totais a fabricar, finalizar manual e filtro por situacao`

---

### Task 7: Roteiro de instalação e builds

**Files:**
- Create: `docs/implantacao-fase-a.md`
- Builds fora do repo: `C:\Users\DELL\Downloads\GitHub\milkdim-builds`

- [ ] **Step 1: Escrever `docs/implantacao-fase-a.md`** no estilo do
  `docs/implantacao-auth.md`, com caixas de marcar:
  1. migração aplicada (Task 1, Step 6);
  2. Controle novo instalado (Windows e Android);
  3. APK novo nos vendedores (instalar por cima, sem desinstalar, porque desinstalar apaga
     os pedidos guardados no aparelho);
  4. teste de ponta a ponta. O vendedor salva um pedido sem assinatura e confere:
     - o pedido aparece na Produção em até 30 s;
     - o vendedor edita e aparece "alterado às";
     - o vendedor finaliza com assinatura e o pedido sai da Produção.

  Inclua:
  - o lembrete de que o APK antigo continua funcionando;
  - a pendência da conta admin da fábrica (código a definir com o dono).

- [ ] **Step 2: Gerar os builds**, com o mesmo keystore de debug de sempre
  (`%USERPROFILE%\.android\debug.keystore`).

  Run:
  - `cd app && flutter build apk --release --dart-define-from-file=../dart_defines.json`
  - `cd admin && flutter build apk --release --dart-define-from-file=../dart_defines.json`
  - `cd admin && flutter build windows --release --dart-define-from-file=../dart_defines.json`

  Copiar para `milkdim-builds` como:
  - `MilkDim_Funcionario_2026-11-XX_faseA.apk`
  - `MilkDim_Controle_2026-11-XX_faseA.apk`
  - `MilkDim_Controle_Windows_2026-11-XX_faseA\`

  Expected: os três builds terminam sem erro.

- [ ] **Step 3: Verificação final**

  Run, em cada um de `app`, `admin` e `packages/milkdim_ui`: `flutter analyze` e
  `flutter test`.

  Expected: nenhum aviso novo, e todos os testes passando.

- [ ] **Step 4: Commit preparado**: `docs: roteiro de implantacao da fase A`
