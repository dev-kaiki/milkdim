# Fase A.2 — Pronto para entrega e duas assinaturas: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separar "produção concluída" de "entregue" e exigir duas assinaturas do cliente: a do pedido, para enviá-lo à fábrica, e a da entrega, para finalizar.

**Architecture:** A tabela `pedidos` continua única.
- **Banco:** ganha a situação `pronto`, a coluna `assinatura_pedido` e `pronto_em`/`pronto_por`. Uma segunda migração muda o gatilho da Fase A e as RPCs.
- **App:** a assinatura do pedido segue o mesmo caminho da de entrega (bytes no mapa, `\x`+hex no envio, decodificação na volta), em colunas próprias.
- **Controle:** a Produção ganha a lista "Prontos para entrega".

**Tech Stack:** Flutter 3.41.1 / Dart 3.11, `supabase_flutter`, `sqflite`, Supabase Postgres 17. A migração é aplicada pelo MCP `execute_sql`.

**Spec:** `docs/superpowers/specs/2026-11-23-fase-a-fluxo-do-pedido-design.md`. A seção "Revisão aprovada em 23/11/2026" vale mais que o resto do documento.

**Base:** branch `feat/fase-a-fluxo-pedido` (PR dev-kaiki/milkdim#3, ainda não mesclado). A migração `20261123000001` já está aplicada em produção.

## Global Constraints

- **Credenciais:** nenhuma senha, chave, URL ou ref do Supabase em arquivo versionado. O repositório é público.
- **Banco real:** nada é aplicado sem mostrar o SQL ao Kaiki e receber OK. O teste roda em `begin … rollback`.
- **Pedidos:** nunca são perdidos, duplicados, ressuscitados ou rotulados errado. O pedido local nunca é apagado por sincronização, cancelamento ou ação do Controle.
- **Situações e textos de tela:**
  - `salvo` = "Em aberto"
  - `pronto` = "Pronto para entrega" (selo curto "Pronto")
  - `finalizado` = "Entregue". O valor gravado continua `finalizado`.
  - `cancelado` = "Cancelado"
- **Textos fixos, exatamente assim:**
  - botões: "Salvar rascunho", "Enviar pedido", "Salvar alterações", "Registrar entrega", "Produção concluída", "Marcar como entregue", "Prontos para entrega"
  - selo: "alterado depois de pronto"
  - rótulos do PDF: "Assinatura do pedido" e "Assinatura da entrega"
  - avisos: "O cliente precisa assinar o pedido." e "O cliente precisa assinar o pedido de novo, porque os itens mudaram."
- **Textos da Fase A que continuam valendo:**
  - "Pedido enviado para produção."
  - "Pedido salvo. Será enviado quando houver internet."
  - "Este pedido já foi finalizado no Controle."
  - "Este pedido foi cancelado no Controle."
  - "Número já usado; troque o número"
  - "Não enviado"
- **A fabricar:** conta só `salvo`.
- **Visual:** só componentes e tokens do `milkdim_ui`. Os dados de teste e de captura são falsos.
- **Commits:** locais no branch, com o trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push só no fim, com o PR.
- **Qualidade:** os testes que já existem continuam passando (app 159, admin 64, ui 25), e o `flutter analyze` não ganha avisos novos.

## Review Focus

1. **Celular desatualizado:** um celular com cópia velha `salvo` de um pedido que a fábrica já marcou `pronto` reenvia sem mudar os itens. O pedido continua `pronto` (teste no Task 1, e no Task 2 do lado do eco).
2. **Rascunho antigo, sem assinatura do pedido:** o vendedor toca "Salvar alterações" num rascunho antigo (`so_local`). O app exige a assinatura do pedido antes de enviar (teste no Task 3).
3. **Entrega de pedido sem assinatura do pedido:** um pedido criado antes desta versão chega em Registrar entrega. O vendedor consegue registrar a entrega só com a assinatura da entrega (teste no Task 3).
4. **"Marcar como entregue" num pedido `pronto`, seguido de entrega assinada do vendedor:** vale a do vendedor (teste no Task 1).
5. **PDF de pedido com uma só assinatura:** ele é gerado sem quebrar e mostra só o rótulo da assinatura que existe (teste no Task 3).

---

### Task 1: Migração 2 do banco (pronto, assinatura do pedido, RPCs)

**Files:**
- Create: `supabase/migrations/20261123000002_fase_a2_pronto_assinaturas.sql`
- Create: `supabase/tests/fase_a2_test.sql`

**Interfaces:**
- Produces:
  - **Colunas:** `pedidos.assinatura_pedido bytea`, `pronto_em timestamptz`, `pronto_por text`.
  - **Constraint:** `pedidos_status_check` com `('salvo','pronto','finalizado','cancelado')`.
  - **RPC nova:** `public.pedido_marcar_pronto(p_id bigint) returns void`. Só admin (`42501`); só `salvo` (`55000`); id inexistente → `P0002`. Grava `pronto_em = now()` e `pronto_por = app_autor_pedido()`.
  - **RPCs existentes:**
    - `pedido_finalizar_manual` passa a aceitar `salvo` ou `pronto`.
    - `pedido_cancelar` passa a aceitar `salvo` ou `pronto`.
  - **Gatilho `pedidos_antes_inserir`:** força `pronto_em`/`pronto_por` nulos. Insert com `status='pronto'` vira `salvo`.
  - **Gatilho `pedidos_antes_alterar`:** a regra da Fase A mais o seguinte:

    ```
    (antes do ramo de pedido fechado) assinatura_pedido: aceita a nova se não nula; nula não apaga (coalesce(new, old))
    pronto_em/pronto_por: sempre os de OLD (só a RPC muda)
    se OLD.status = 'salvo' e NEW.status = 'pronto': NEW.status := 'salvo'
    se OLD.status = 'pronto':
      se NEW.status = 'finalizado' (com ou sem assinatura): segue a regra de finalização da Fase A
      se NEW.status = 'cancelado': segue a regra de cancelamento da Fase A
      senão (salvo/pronto): se produtos, cliente_id ou cliente_nome mudaram → NEW.status := 'salvo',
         alterado_em := now(); senão → NEW.status := 'pronto', alterado_em := OLD.alterado_em
    a regra "entrega assinada vence" continua usando NEW.assinatura (a da entrega)
    ```

  - **"Pronto" volta para "Em aberto":** quando uma alteração devolve o pedido, `pronto_em`/`pronto_por` ficam guardados. O Controle mostra "alterado depois de pronto" quando `status='salvo'`, `pronto_em is not null` e `alterado_em > pronto_em`.

- [ ] **Step 1: Escrever `fase_a2_test.sql`**, no estilo do `fase_a_test.sql`. Ele roda depois das duas migrações, dentro da mesma transação. Blocos:

  **Pronto e as RPCs:**
  - Um vendedor não consegue gravar `pronto`: um update `status='pronto'` deixa `salvo`.
  - Um insert `pronto` vira `salvo`.
  - Admin chama `pedido_marcar_pronto` num `salvo`:
    - o pedido fica `pronto`;
    - `pronto_em = now()`;
    - `pronto_por` = código do admin.
  - `pedido_marcar_pronto` num pedido `pronto` ou `finalizado` dá `55000`. Para um vendedor dá `42501`.

  **Celular reenviando um pedido pronto:**
  - Reenvio do vendedor com os mesmos itens e `status='salvo'`: continua `pronto` (Review Focus 1).
  - Vendedor muda a quantidade:
    - vira `salvo`;
    - `alterado_em = now()`;
    - `pronto_em` continua preenchido.

  **Entrega:**
  - Vendedor finaliza um `pronto` com `assinatura`: fica `finalizado` e `finalizado_por` = vendedor.
  - `pedido_finalizar_manual` num `pronto`: o pedido fica `finalizado` com `finalizado_manual`. Depois, a entrega assinada do vendedor vence (Review Focus 4).

  **Cancelamento e assinatura do pedido:**
  - `pedido_cancelar` num `pronto`: o pedido fica `cancelado`.
  - `assinatura_pedido`: insert com ela guarda. Um update sem ela (nula) não apaga. Um update com outra substitui.

  **Constraint:**
  - Insert com `status='rascunho'` continua violando a constraint.

- [ ] **Step 2: Escrever a migração.**
  - Idempotente, no mesmo estilo do `20261123000001`.
  - `create or replace` das duas funções de gatilho e das duas RPCs alteradas, mais a RPC nova.
  - Permissões: `revoke`/`grant` iguais aos da Fase A.

- [ ] **Step 3: Controlador.** Ele mostra o SQL ao Kaiki e roda `begin; <migração 1 já aplicada não entra>; <migração 2>; <fase_a_test.sql>; <fase_a2_test.sql>; rollback;`. O `fase_a_test.sql` continua passando, exceto onde a mudança de regra é intencional. Se algum bloco do `fase_a_test.sql` passar a falhar por causa dela, o implementador ajusta esse bloco no mesmo commit e diz qual e por quê. Depois o controlador aplica com `commit`.

- [ ] **Step 4: Commit:** `feat(db): fase A.2 — pronto para entrega, assinatura do pedido e RPC pedido_marcar_pronto`

---

### Task 2: Dados do app (SQLite v18, envio, eco, sincronização)

**Files:**
- Modify:
  - `app/lib/utils/db.dart`: versão 18 e colunas `assinatura_pedido TEXT`, `assinatura_pedido_path TEXT`, `pronto_em TEXT`, `pronto_por TEXT`
  - `app/lib/utils/supabase_helper.dart`: `montarPayloadPedido` (~752), `_camposDoServidor` (~285), `_comAssinaturaDoArquivo`, `decidirEco`
  - `app/lib/utils/pedido_da_tela.dart`
  - `app/lib/utils/regras_pedido.dart`
- Test: `app/test/fluxo_pronto_assinaturas_test.dart`

**Interfaces:**
- Consumes: Task 1 (colunas e regras do servidor).
- Produces:
  - **`pedidoDaTela`:** ganha o parâmetro `Uint8List? assinaturaPedido`, gravado em `assinatura_pedido`.
  - **Payload:** envia `assinatura_pedido` como `\x`+hex via `assinaturaParaBytea`. Se só houver `assinatura_pedido_path`, lê o arquivo, como já faz com a de entrega.
  - **Eco e sincronização:** gravam `assinatura_pedido` (hex `0x…` local), `pronto_em` e `pronto_por`.
  - **`decidirEco`:** o remoto `pronto` **não** é "fechado". Tratá-lo como `salvo` em aberto, aplicar o eco e nunca mandar para descartados por isso.
  - **`regras_pedido.dart`:**
    - `bool estaPronto(Map p)`: `status == 'pronto'`;
    - `acaoRemover` trata `pronto` como `salvo` (→ `cancelar`);
    - `numeroEditavel` não muda;
    - `bool itensOuClienteMudaram(Map antes, Map depois)` compara `produtos` normalizados (nome, quantidade, preço), `cliente_id` e `cliente_nome`;
    - `bool precisaAssinaturaDoPedido({required Map original, required Map editado})` → true se `so_local == 1`, se o original não tem `assinatura_pedido` nem `assinatura_pedido_path`, ou se `itensOuClienteMudaram`.
  - **Abas de Meus pedidos:** a aba "Em aberto" lista `salvo` **e** `pronto`.

- [ ] **Step 1: Testes em `fluxo_pronto_assinaturas_test.dart`:**

  **Envio:**
  - `payload leva assinatura_pedido em \x hex`
  - `payload sem assinatura_pedido nao manda a chave`
  - `pedido salvo so com assinatura_pedido_path le o arquivo no envio`

  **Eco e sincronização:**
  - `eco pronto nao e servidorFechou e grava pronto_em`
  - `sync traz assinatura_pedido e pronto`
  - `copia velha salvo de pedido pronto: eco devolve pronto e a linha local fica pronto` (Review Focus 1, lado do app)

  **Regras:**
  - `precisaAssinaturaDoPedido`: so_local → true; sem assinatura do pedido → true; com assinatura e itens iguais → false; quantidade mudou → true; cliente mudou → true.
  - `acaoRemover(pronto)` → `cancelar`.

- [ ] **Step 2: Rodar e ver falhar.**

  Run: `cd app && flutter test test/fluxo_pronto_assinaturas_test.dart`

  Expected: FAIL.

- [ ] **Step 3: Implementar.** A migração SQLite v18 só adiciona colunas.

- [ ] **Step 4: Verificar.**

  Run: `cd app && flutter test && flutter analyze`

  Expected: tudo passa e o analyze não ganha avisos novos.

- [ ] **Step 5: Commit:** `feat(app): assinatura do pedido e situacao pronto nos dados do app (SQLite v18)`

---

### Task 3: Telas do vendedor e PDF

**Files:**
- Modify:
  - `app/lib/pages/pedido_page.dart`
  - `app/lib/pages/pedido_edit_page.dart`
  - `app/lib/widgets/pedido_ui.dart` (botões ~330-360)
  - `app/lib/pages/pedidos_page.dart`
  - `app/lib/utils/pdf_utils.dart`
- Test: `app/test/telas_pronto_assinaturas_test.dart`; `app/test/visual/telas_test.dart`

**Interfaces:**
- Consumes: Task 2 (`pedidoDaTela(assinaturaPedido:)`, `precisaAssinaturaDoPedido`, `estaPronto`).
- **Pedido novo (`pedido_page`):**
  - **"Salvar rascunho":** grava com `so_local: 1` e `status: 'salvo'`, sem enviar.
  - **"Enviar pedido":** sem assinatura do pedido, abre a `AssinaturaPage` com o aviso "O cliente precisa assinar o pedido.". Com assinatura, grava `status: 'salvo'`, `so_local: 0` e `assinatura_pedido`, e envia.
  - Não existe mais "Finalizar" no pedido novo.
- **Pedido aberto ou pronto (`pedido_edit_page`):**
  - **"Salvar alterações":** se `precisaAssinaturaDoPedido`, abre a `AssinaturaPage` com o aviso "O cliente precisa assinar o pedido de novo, porque os itens mudaram." ou "O cliente precisa assinar o pedido." (rascunho ou pedido sem assinatura), e só salva com a nova assinatura. Se o vendedor desiste da assinatura, nada é gravado e o formulário continua.
  - **"Registrar entrega":** abre a `AssinaturaPage` da entrega e grava `status: 'finalizado'` com `assinatura` (a da entrega). Não exige assinatura do pedido (Review Focus 3).
  - O status mandado preserva `pronto` quando o original é `pronto`. Quem decide voltar para `salvo` é o servidor.
- **Meus pedidos:**
  - os pedidos `pronto` aparecem em "Em aberto" com o `MdStatusChip` "Pronto" (tipo sucesso);
  - a aba "Finalizados" passa a se chamar "Entregues".
- **PDF:** `gerarPdfPedido` passa a aceitar `assinaturaPedidoBytes` além da de entrega. Cada imagem sai com o seu rótulo: "Assinatura do pedido" / "Assinatura da entrega". Se só houver uma, aparece só ela (Review Focus 5).

- [ ] **Step 1: Testes.**
  - **Pedido novo:** `Enviar pedido sem assinatura abre a tela de assinatura e nao grava`, com seam/injeção da navegação de assinatura.
  - **Salvar alterações:** `Salvar alteracoes com itens mudados exige nova assinatura`; `Salvar alteracoes sem mudar itens nao pede assinatura`.
  - **Entrega:** `Registrar entrega so pede a assinatura da entrega` (Review Focus 3).
  - **PDF:** `pdf com uma assinatura so mostra o rotulo dela`, testando a função que monta os dados do PDF.
  - **Capturas:** `pedido_novo_botoes.png`, `meus_pedidos_pronto.png`.

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Verificar.**

  Run: `cd app && flutter test && flutter test --tags visual && flutter analyze`

- [ ] **Step 5: Commit:** `feat(app): enviar pedido com assinatura, salvar alteracoes, registrar entrega e PDF com duas assinaturas`

---

### Task 4: Controle (Produção com prontos, filtro, detalhe)

**Files:**
- Modify:
  - `admin/lib/models/pedido.dart`: `prontoEm`, `prontoPor`, `assinaturaPedidoBytes`, `situacaoTexto` com "Pronto para entrega" e "Entregue"
  - `admin/lib/services/supabase_service.dart`
  - `admin/lib/tabs/producao_tab.dart`
  - `admin/lib/tabs/pedidos_tab.dart`
  - `admin/lib/widgets/detalhe_pedido.dart`
  - `admin/lib/models/producao.dart`, se preciso
- Test: `admin/test/producao_tab_test.dart`, `admin/test/producao_test.dart`, `admin/test/visual/telas_test.dart`

**Interfaces:**
- Consumes: Task 1 (`pedido_marcar_pronto`, status `pronto`, colunas).
- Produces:
  - **Serviço:**
    - `SupabaseService.marcarPronto(int id)`;
    - `buscarPedidosEmAberto()` passa a trazer `salvo` e `pronto`, e a tela separa os dois;
    - `mensagemErroRpcPedido` com 55000 → "Esse pedido não está mais em aberto." Continua o mesmo texto.
  - **Modelo:**
    - `bool get alteradoDepoisDePronto`: `status=='salvo'`, `prontoEm != null` e `alteradoEm` depois de `prontoEm`;
    - `totaisAFabricar` continua só `salvo`.
- **Aba Produção:**
  - **Seção "Pedidos em aberto":** os cartões têm o botão **"Produção concluída"** (sem a confirmação longa; confirmação curta "Marcar como pronto para entrega?") e **Cancelar**. O selo "alterado depois de pronto" tem prioridade sobre "alterado às".
  - **Seção nova "Prontos para entrega":** os cartões têm **"Marcar como entregue"** (com o texto de confirmação da Fase A) e **Cancelar**.
  - **Estado vazio de cada seção:** "Nenhum pedido em aberto" / "Nenhum pedido pronto".
  - **Snacks de sucesso:**
    - "Pedido pronto para entrega."
    - "Pedido marcado como entregue."
    - "Pedido cancelado."
  - **Toques e atualização:** o guarda de toque duplo e a recarga depois da ação, como na Fase A.
- **Aba Pedidos:**
  - **Filtro:** Todos / Em aberto / Prontos / Entregues / Cancelados. Os quatro primeiros cabem em 412 px sem corte. Se não couberem os cinco, usar `Wrap` de chips.
  - **Selo de situação:** pronto = sucesso, entregue = sucesso, aberto = info, cancelado = neutro.
- **Detalhe do pedido:** mostra "Pronto em / por" e as duas assinaturas como imagem: "Assinatura do pedido" e "Assinatura da entrega". Se faltar uma, aparece "—".

- [ ] **Step 1: Testes.**
  - **Totais e seções:** `pronto nao entra em A fabricar`; `secao Prontos lista so pronto`.
  - **Ações:** `Producao concluida chama marcarPronto uma vez e recarrega`; `Marcar como entregue chama finalizarManual`.
  - **Selo:** `selo alterado depois de pronto`.
  - **Filtro:** `filtro Prontos`.
  - **Capturas:** `producao_com_prontos_estreita.png`, `producao_com_prontos_larga.png`, `detalhe_duas_assinaturas.png`.

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Verificar.**

  Run: `cd admin && flutter test && flutter test --tags visual && flutter analyze`

- [ ] **Step 5: Commit:** `feat(admin): producao concluida, prontos para entrega e duas assinaturas no detalhe`

---

### Task 5: Roteiro, builds e verificação

**Files:**
- Modify: `docs/implantacao-fase-a.md`

**Itens:**
- **Roteiro:**
  - marcar a migração 2 como aplicada, com a data;
  - atualizar "o que o vendedor nota" e "o que a fábrica nota" com as duas assinaturas, o Pronto e Registrar entrega;
  - reescrever o teste de ponta a ponta: enviar com assinatura → Produção concluída → aparece em Prontos e o vendedor vê "Pronto" → alterar itens (pede assinatura de novo e volta para Em aberto com "alterado depois de pronto") → Produção concluída de novo → Registrar entrega com assinatura → Marcar como entregue manual + entrega assinada vence → Cancelar.
- **Builds:** os mesmos três nomes `*_2026-11-23_faseA*`, sobrescrevendo os anteriores.
- **Verificação final:** em app, admin e milkdim_ui, `flutter analyze` e `flutter test`.
- **Commit:** `docs: roteiro da fase A com pronto para entrega e duas assinaturas`
