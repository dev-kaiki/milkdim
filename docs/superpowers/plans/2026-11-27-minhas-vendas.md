# Minhas vendas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O vendedor vê quanto vendeu no mês, com comparação com o mês anterior, o que ainda falta entregar, as vendas por produto e os melhores clientes, usando os dados do aparelho.

**Architecture:** Funções puras calculam o resumo de um mês a partir dos pedidos locais. Uma consulta local traz só as colunas necessárias. Uma tela nova e um item na tela inicial mostram o resultado.

**Tech Stack:** Flutter 3.41 / Dart 3.11, sqflite, `intl` (já no app), `milkdim_ui`.

**Spec:** `docs/superpowers/specs/2026-11-27-minhas-vendas-design.md`

## Global Constraints

- Só `app/` muda. Nada em `admin/`, `supabase/` nem no esquema do SQLite. A tela só lê.
- **Venda:** `status` igual a `finalizado` (com `trim` e sem diferença de maiúsculas), do mesmo `vendedor_codigo` e sem os apagados no Controle (`apagadoNoControle`). O mês é o de `finalizado_em` convertido para a hora local. Pedido com `finalizado_em` ilegível fica fora.
- **A entregar:** status `salvo` ou `pronto`, deste vendedor e sem os apagados. Aparece só no mês atual.
- **Por produto:** soma por nome (com `trim` e sem diferença de maiúsculas). O nome mostrado é o primeiro que aparece. As unidades vêm de `quantidade` e o valor de `subtotal`; sem `subtotal`, usa `preco × quantidade`. A ordem é pelo maior R$.
- **Melhores clientes:** agrupados por `cliente_id`; sem `cliente_id`, pelo nome exibido. São os 5 com mais R$, e o nome vem de `nomeExibicao` sobre o cliente do pedido mais recente.
- **Comparação:** `((atual − anterior) / anterior × 100)` arredondado. Mostra "▲ N%" quando sobe, "▼ N%" quando cai e "= 0%" quando é igual. Com o anterior em zero, não mostra nada.
- **Textos exatos:**
  - item da tela inicial: "Minhas vendas", com o subtítulo "{R$} em {mês}" (mês em minúsculas, pt_BR) ou, sem dado, "Quanto você vendeu no mês";
  - números: "Vendido", "Pedidos entregues", "Ticket médio" ("—" quando não há pedido);
  - seções: "A entregar", "Por produto", "Melhores clientes";
  - título do mês: "{mês} de {ano}";
  - mês sem venda: "Nenhuma venda entregue em {mês}.".
- **Mês:** não avança além do mês atual.

## Review Focus

1. **Entregue às 23h30 do dia 30/11 em hora local** (já 01/12 em UTC): conta em novembro. Teste na Tarefa 1.
2. **Pedido de outro vendedor ou apagado no Controle:** não conta. Teste na Tarefa 1.
3. **Mês anterior zero:** sem comparação e sem divisão por zero. Teste na Tarefa 1.
4. **Item com `subtotal` ausente ou em texto** ("12,50"): usa `preco × quantidade` ou converte o texto. Teste na Tarefa 1.
5. **Avançar o mês na tela:** o botão "›" fica desligado no mês atual. Teste na Tarefa 2.

---

### Task 1: Resumo do mês (funções puras e consulta)

**Files:**
- Create: `app/lib/utils/minhas_vendas.dart`
- Modify: `app/lib/utils/db.dart` (nova consulta)
- Test: `app/test/minhas_vendas_test.dart`

**Interfaces:**
- Produces:
  - `class VendaProduto { final String nome; final int unidades; final double valor; }`
  - `class VendaCliente { final String nome; final int pedidos; final double valor; }`
  - `class ResumoVendas { final double vendido; final int pedidos; final double? ticketMedio; final double aEntregarValor; final int aEntregarPedidos; final List<VendaProduto> porProduto; final List<VendaCliente> melhoresClientes; }`
  - `ResumoVendas resumoDoMes(List<Map<String, dynamic>> pedidos, {required String vendedorCodigo, required int ano, required int mes})`. O "a entregar" é sempre calculado; quem decide mostrá-lo só no mês atual é a tela.
  - `String? textoVariacao(double atual, double anterior)`: devolve "▲ N%", "▼ N%", "= 0%" ou `null`.
  - Em `db.dart`: `Future<List<Map<String, dynamic>>> listarPedidosParaVendas(String vendedorCodigo)`. Traz as colunas `id, numero, status, vendedor_codigo, finalizado_em, total, produtos, erro_envio, cliente_id, cliente_nome, cliente_nome_fantasia, datahora` com `WHERE vendedor_codigo = ?`.
- [ ] **Step 1: Testes que falham**, cobrindo cada item da Review Focus 1–4.
  - Por produto: soma e ordem.
  - Os 5 melhores clientes, com agrupamento sem `cliente_id`.
  - Ticket médio `null` quando não há pedido.
  - A entregar: `salvo` e `pronto` sim, `cancelado` não.
  - `textoVariacao` nos quatro casos.
  - Consulta com banco ffi em memória: só vêm pedidos do vendedor pedido.
- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/minhas_vendas_test.dart`
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test` e `flutter analyze`.
- [ ] **Step 5: Commit.** `feat(vendas): resumo do mês do vendedor`

---

### Task 2: Tela "Minhas vendas" e item na tela inicial

**Files:**
- Create: `app/lib/pages/minhas_vendas_page.dart`
- Modify: `app/lib/pages/home_page.dart`
- Test: `app/test/telas_minhas_vendas_test.dart`

**Interfaces:**
- Consumes: tudo o que a Tarefa 1 produz; `formatarReais`; `DateFormat` do `intl` com locale `pt_BR`.
- Produces: `MinhasVendasPage({required Map<String, dynamic> vendedor, DateTime Function()? relogio, Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)? carregarPedidos})`.
- [ ] **Step 1: Testes que falham.**
  - Mostra os três números, as comparações e as seções com os textos exatos.
  - "‹" troca para o mês anterior; "›" fica desligado no mês atual.
  - "A entregar" só aparece no mês atual.
  - Mês sem venda mostra a mensagem.
  - Item da tela inicial: com `vendasParaCaptura`, segue o padrão de `sumidosParaCaptura`; sem dado, mostra o texto neutro.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
  - O item entra depois de "Clientes sumidos".
  - O subtítulo é atualizado junto com `_atualizarSumidos`/`_atualizarProntos`, usando `listarPedidosParaVendas` e `resumoDoMes` do mês atual.
  - Se `initializeDateFormatting('pt_BR')` for necessário, chamar onde o app já faz isso (procurar no `main.dart`); se o app não faz, chamar uma vez na tela.
- [ ] **Step 4: Rodar e ver passar.** `flutter test`, `flutter analyze` e `flutter test test/visual`.
- [ ] **Step 5: Commit.** `feat(vendas): tela minhas vendas e item na tela inicial`
