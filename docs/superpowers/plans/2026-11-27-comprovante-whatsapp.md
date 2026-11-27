# Comprovante para o cliente Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Logo depois de registrar a entrega, o vendedor manda o comprovante em PDF (com as duas assinaturas) ao cliente pelo compartilhar do Android. Os pedidos entregues em Meus pedidos ganham o botão "Comprovante".

**Architecture:** A geração e o compartilhamento que hoje vivem em `PedidosPage._compartilharPdf` vão para uma função compartilhada. A `PedidoPageEdit` oferece o comprovante depois de uma entrega gravada com sucesso, antes de fechar.

**Tech Stack:** Flutter 3.41 / Dart 3.11, `pdf`/`printing` já usados em `pdf_utils.dart`, `share_plus`, sqflite.

**Spec:** `docs/superpowers/specs/2026-11-27-comprovante-whatsapp-design.md`

## Global Constraints

- Só `app/` muda. Nada em `admin/`, `supabase/` nem no esquema do SQLite.
- O fluxo de entrega e o que ele grava não mudam: o comprovante só lê.
- **Textos exatos:**
  - pergunta: "Entrega registrada. Enviar comprovante ao cliente?";
  - botões: "Enviar comprovante" e "Agora não";
  - texto do compartilhar: "Comprovante do pedido nº {n} – MilkDim. Obrigado pela preferência!", com travessão "–" (U+2013);
  - falha: "Não foi possível gerar o comprovante.";
  - botão em Meus pedidos para entregues: "Comprovante".
- **Entregue** quer dizer status `finalizado`. Em pedido cancelado, o botão continua "PDF", com o comportamento de hoje.

## Review Focus

1. **Entrega gravada, mas o envio ao servidor ficou pendente** (sem internet): a pergunta aparece igual, porque o pedido está gravado no aparelho. Teste na Tarefa 2.
2. **Falha ao gerar o PDF:** aparece o aviso e a tela fecha com o mesmo resultado de hoje (`Navigator.pop(context, situacao)`). Teste na Tarefa 2.
3. **Outras gravações da tela de editar** ("Salvar", "Enviar"…): não perguntam nada. Teste na Tarefa 2.
4. **Pedido entregue sem a assinatura do pedido** (pedido antigo): o PDF sai assim mesmo, porque a lógica de "Não assinada" do `pdf_utils` já cuida disso. Teste na Tarefa 1.
5. **Número vazio:** o texto sai como "Comprovante do pedido nº s/n – MilkDim. Obrigado pela preferência!". Teste na Tarefa 1.

---

### Task 1: Função de comprovante e botão em Meus pedidos

**Files:**
- Create: `app/lib/utils/comprovante.dart`
- Modify: `app/lib/pages/pedidos_page.dart` (mover para lá `_compartilharPdf` e os auxiliares de assinatura `_assinaturaAsBytes` e `_assinaturaPedidoAsBytes`; trocar o rótulo nos entregues)
- Test: `app/test/comprovante_test.dart`

**Interfaces:**
- Produces:
  - `String textoComprovante(Object? numero)`: com número vazio ou nulo, usa "s/n".
  - `Future<Uint8List> pdfDoComprovante(Map<String, dynamic> pedido)`: as mesmas assinaturas e a mesma chamada a `gerarPdfPedido` que existem hoje.
  - `Future<void> compartilharComprovante(Map<String, dynamic> pedido, {Future<void> Function(List<XFile> arquivos, String texto)? compartilhar})`: grava o PDF num arquivo temporário e chama `Share.shareXFiles` com `text` e `subject` iguais a `textoComprovante`. Erros sobem para quem chamou.
- [ ] **Step 1: Testes que falham.**
  - `textoComprovante` com número e sem número.
  - `pdfDoComprovante` com pedido sem a assinatura do pedido devolve bytes que começam com `%PDF`.
  - Em Meus pedidos, com `pedidosParaCaptura`: um pedido `finalizado` mostra "Comprovante" e não "PDF"; um `cancelado` continua mostrando "PDF".
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.** Em Meus pedidos, o botão dos dois casos chama `compartilharComprovante`. Nos cancelados, o texto continua o de hoje ("Pedido #n (PDF)"). Para isso, `compartilharComprovante` aceita um parâmetro opcional `String? texto`.
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test`, `flutter analyze` e `flutter test test/visual`.
- [ ] **Step 5: Commit.** `feat(comprovante): função única de comprovante e botão nos entregues`

---

### Task 2: Oferecer o comprovante depois de registrar a entrega

**Files:**
- Modify: `app/lib/pages/pedido_edit_page.dart` (`_registrarEntrega` e `_gravar`, perto da linha 569)
- Test: `app/test/telas_comprovante_test.dart`

**Interfaces:**
- Consumes: `compartilharComprovante` e `textoComprovante` (Tarefa 1); `buscarPedidoLocalPorId(int id)` (db.dart, do branch de entregas).
- Produces: `PedidoPageEdit({..., Future<void> Function(Map<String, dynamic> pedido)? enviarComprovante, Future<Map<String, dynamic>?> Function(int id)? lerPedidoGravado})`. São ganchos para os testes; quando nulos, a tela usa as funções reais.
- [ ] **Step 1: Testes que falham**, usando os ganchos `gravar`, `pedirAssinatura` e `lerSituacaoGravada` que a tela já tem (veja `test/telas_pronto_assinaturas_test.dart`).
  - Registrar entrega com sucesso mostra a pergunta. "Enviar comprovante" chama `enviarComprovante` com o pedido relido e depois fecha a tela com a situação.
  - "Agora não" fecha a tela sem chamar.
  - Falha em `enviarComprovante` mostra "Não foi possível gerar o comprovante." e a tela fecha assim mesmo.
  - Entrega gravada só no aparelho (`ResultadoGravacao` de envio pendente): a pergunta aparece.
  - "Salvar" e as outras gravações não mostram a pergunta.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
  - `_gravar` ganha um parâmetro opcional `Future<void> Function(Map<String, dynamic> gravado)? antesDeFechar`, chamado depois da mensagem de gravação e antes do `Navigator.pop`, só quando a gravação não lançou erro. Só `_registrarEntrega` passa esse parâmetro.
  - A pergunta usa `showDialog`.
  - Se o pedido relido por id não existir, usa o mapa que acabou de ser gravado.
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test` e `flutter analyze`.
- [ ] **Step 5: Commit.** `feat(comprovante): oferecer o comprovante logo após registrar a entrega`
