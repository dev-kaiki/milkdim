# Entregas do dia Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O vendedor vê os pedidos prontos agrupados por cidade e, em cada um, abre o mapa, avisa o cliente pelo WhatsApp ou registra a entrega.

**Architecture:** Funções puras montam os grupos e os links a partir dos pedidos locais. Uma tela nova, aberta pela tela inicial, baixa os pedidos do servidor ao abrir e reaproveita o fluxo de entrega que já existe (`PedidoPageEdit`).

**Tech Stack:** Flutter 3.41 / Dart 3.11, sqflite, `url_launcher` (já é dependência direta), `milkdim_ui`.

**Spec:** `docs/superpowers/specs/2026-11-27-entregas-do-dia-design.md`

## Global Constraints

- Só `app/` muda. Nada em `admin/`, `supabase/` nem no esquema do SQLite. Esta tela não grava nenhum pedido.
- **Pedidos que entram:** `status == 'pronto'`, com `vendedor_codigo` igual ao do vendedor e sem os apagados no Controle (`apagadoNoControle`).
- **Grupos:** por cidade, com `trim` e sem diferença de maiúsculas para agrupar. O título do grupo é a cidade como está no primeiro pedido do grupo. A cidade vazia vira "Sem cidade" e fica por último. Os grupos vêm em ordem alfabética. Dentro de cada grupo, a ordem é pelo `nomeExibicao`, e em caso de empate pelo número do pedido.
- **Textos exatos:**
  - item da tela inicial: "Entregas do dia", com o subtítulo "{N} prontos para entregar" ou, sem contagem, "Pedidos prontos para entregar";
  - cartão: "Pedido nº {n}" e "Pronto desde dd/MM HH:mm" (hora local; sem `pronto_em` legível, a linha não aparece);
  - botões: "Mapa", "Avisar", "Registrar entrega";
  - lista vazia: "Nenhum pedido pronto para entregar.";
  - mensagem: "Olá! Aqui é o {vendedor} da MilkDim. Seu pedido nº {n} está pronto, passo aí hoje." e, sem nome do vendedor, "Olá! Aqui é da MilkDim. Seu pedido nº {n} está pronto, passo aí hoje.";
  - falhas: "Não foi possível abrir o mapa." e "Não foi possível abrir o WhatsApp."
- **Mapa:** `https://www.google.com/maps/search/?api=1&query=<endereço, cidade, CEP>`. As partes vazias ficam de fora, e o texto é codificado com `Uri.encodeComponent`. Sem endereço, o link é `null`.
- **WhatsApp:** usa `linkWhatsApp` de `clientes_sumidos.dart` sobre o cliente do pedido. Os campos do pedido viram as chaves do cliente: `cliente_whatsapp` vira `whatsapp`, `cliente_telefone` vira `telefone`, `cliente_nome` vira `nome`, `cliente_nome_fantasia` vira `nome_fantasia` e `cliente_cidade` vira `cidade`.

## Review Focus

1. **Pedido pronto de outro vendedor** no mesmo aparelho: não aparece. Teste na Tarefa 1.
2. **Cidade "franca" e "Franca "**: caem no mesmo grupo. Teste na Tarefa 1.
3. **Sem internet ao abrir:** a lista local aparece, e nenhum erro bloqueia a tela. Teste na Tarefa 2.
4. **Voltar de "Registrar entrega":** a lista recarrega, e o pedido entregue some dela. Teste na Tarefa 2.
5. **Endereço com acento e vírgula:** o link do mapa sai codificado, sem "+". Teste na Tarefa 1.

---

### Task 1: Grupos de entrega, link do mapa e mensagem

**Files:**
- Create: `app/lib/utils/entregas.dart`
- Test: `app/test/entregas_test.dart`

**Interfaces:**
- Produces:
  - `class GrupoEntrega { final String cidade; final List<Map<String, dynamic>> pedidos; }`
  - `List<GrupoEntrega> entregasProntas(List<Map<String, dynamic>> pedidos, {required String vendedorCodigo})`
  - `Map<String, dynamic> clienteDoPedido(Map<String, dynamic> pedido)`: faz a troca de chaves das Global Constraints.
  - `Uri? linkMapa(Map<String, dynamic> pedido)`, a partir de `cliente_endereco`, `cliente_cidade` e `cliente_cep`.
  - `String mensagemPronto(String nomeVendedor, String numero)`
  - `int contarProntos(List<Map<String, dynamic>> pedidos, {required String vendedorCodigo})`
- [ ] **Step 1: Testes que falham.**
  - Filtro: só pedidos `pronto` deste vendedor, sem apagados.
  - Agrupamento sem diferença de caixa ou espaço.
  - "Sem cidade" por último, e a ordem dentro do grupo.
  - `clienteDoPedido` faz a troca de chaves.
  - `linkMapa`: as partes vazias ficam de fora; endereço com acento e vírgula sai com `%20` e sem `+`; sem endereço dá `null`.
  - `mensagemPronto` com e sem nome do vendedor.
  - `contarProntos` bate com a soma dos grupos.
- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/entregas_test.dart`
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test` e `flutter analyze`. Os 2 casos de `trava_pedidos_test` são instabilidade conhecida que já existia.
- [ ] **Step 5: Commit.** `feat(entregas): grupos de entrega, mapa e mensagem`

---

### Task 2: Tela "Entregas do dia" e item na tela inicial

**Files:**
- Create: `app/lib/pages/entregas_page.dart`
- Modify: `app/lib/pages/home_page.dart`
- Test: `app/test/telas_entregas_test.dart`

**Interfaces:**
- Consumes: tudo o que a Tarefa 1 produz; `listarPedidosLocaisPorVendedor` ou o equivalente que existir em `db.dart`; `sincronizarPedidos(vendedorCodigo:)`; `resumoItens` (`repetir_pedido.dart`); `formatarReais`; `PedidoPageEdit(pedido:)`.
- Produces: `EntregasPage({required Map<String, dynamic> vendedor, ...})`.
  - Parâmetros opcionais para os testes: `baixarPedidos`, `carregarPedidos`, `abrirLink` e `paginaEntrega`.
  - Quando são nulos, a tela usa o Supabase, o SQLite, o `launchUrl` com `LaunchMode.externalApplication` e a `PedidoPageEdit`.
- [ ] **Step 1: Testes que falham.**
  - Mostra os grupos e os cartões com os textos exatos.
  - Lista vazia.
  - Falha ao baixar ainda mostra a lista local.
  - "Mapa" e "Avisar" chamam `abrirLink` com os links certos e ficam desligados sem dado.
  - Falha ao abrir o link mostra o aviso.
  - Voltar de "Registrar entrega" recarrega a lista (`carregarPedidos` é chamado de novo).
  - O item da tela inicial mostra a contagem, ou o texto neutro, seguindo o padrão `sumidosParaCaptura` com um `prontosParaCaptura`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
  - O item na tela inicial entra logo depois de "Novo pedido", porque é a ação do dia a dia.
  - A contagem é atualizada junto com `_atualizarPendentes`/`_atualizarSumidos`.
  - O baixar ao abrir roda com o mesmo tratamento de erro de `PedidosPage._atualizarDoServidor`.
- [ ] **Step 4: Rodar e ver passar.** `flutter test`, `flutter analyze` e `flutter test test/visual`.
- [ ] **Step 5: Commit.** `feat(entregas): tela de entregas do dia com mapa, aviso e registrar entrega`
