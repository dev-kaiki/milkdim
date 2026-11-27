# Repetir pedido Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O vendedor parte de um dos 5 últimos pedidos do cliente: pelo quadro na tela de novo pedido (A) ou pela ação "Repetir" na lista de Pedidos (B).

**Architecture:**
- **Lógica:** uma função pura casa os itens do pedido antigo (guardados só por nome) com os produtos de hoje.
- **Dados:** uma consulta local busca os pedidos do cliente no SQLite do aparelho.
- **Telas:** a `PedidoPage` ganha o quadro e um parâmetro de partida, e a `PedidosPage` ganha o botão. Nada no servidor muda.

**Tech Stack:** Flutter 3.41 / Dart 3.11, sqflite (testes com sqflite_common_ffi, como os testes existentes), `milkdim_ui`.

**Spec:** `docs/superpowers/specs/2026-11-27-repetir-pedido-design.md`

## Global Constraints

- Só `app/` muda. Nada em `admin/`, `supabase/` nem no esquema do SQLite (sem migração).
- **Pedidos listados:** os do aparelho, do mesmo `cliente_id`, de qualquer status **menos `cancelado`**, do mais novo para o mais velho, no máximo **5**.
- **Casamento:** pelo nome, com `trim()` e sem diferença de maiúsculas. O preço é sempre o de hoje (`Produto.preco`).
- **Textos exatos:**
  - título do quadro: "Partir de um pedido anterior";
  - botão: "Usar";
  - confirmação: "Trocar as quantidades da tela pelas deste pedido?", com os botões "Trocar" e "Cancelar";
  - aviso de produto fora: "Ficaram de fora (não estão mais à venda): " seguido dos nomes separados por ", ";
  - ação na lista: "Repetir";
  - cliente apagado: "Este cliente não está mais cadastrado".
- Nenhuma assinatura é copiada. A tela de editar (`pedido_edit_page.dart`) não muda.
- Nenhum pedido local é apagado ou alterado por estas funções: elas só leem.

## Review Focus

1. **Nome com caixa ou espaço diferente** ("pote 160g " × "Pote 160g") casa. Teste na Tarefa 1.
2. **Mesmo produto duas vezes** no pedido antigo: as quantidades somam. Teste na Tarefa 1.
3. **`quantidade` gravada como `"40"`, `40.0` ou `0`:** as duas primeiras viram 40, e o 0 é ignorado. Teste na Tarefa 1.
4. **`produtos` corrompido** (JSON inválido, `null` ou não-lista): não quebra, preenche nada e o resumo diz "Sem itens". Teste na Tarefa 1.
5. **Trocar de cliente** depois de escolher outro: o quadro mostra os pedidos do cliente novo, não os do anterior. Teste na Tarefa 2.

---

### Task 1: Lógica de repetição e consulta local

**Files:**
- Create: `app/lib/utils/repetir_pedido.dart`
- Modify: `app/lib/utils/db.dart` (nova função perto de `getUltimoPedidoCliente`, ~linha 922)
- Test: `app/test/repetir_pedido_test.dart`

**Interfaces:**
- Produces:
  - `class Preenchimento { final Map<Produto, int> quantidades; final List<String> foraDoPedido; }`
    - `quantidades` só tem produtos com quantidade > 0.
    - `foraDoPedido` são os nomes como estavam no pedido antigo, sem repetição, na ordem em que aparecem.
  - `Preenchimento preencherDePedido(Object? produtosDoPedido, List<Produto> produtosDeHoje)`: aceita `List` ou `String` JSON. Itens inválidos ou com quantidade ≤ 0 são ignorados.
  - `String resumoItens(Object? produtosDoPedido, {int max = 3})`: dá, por exemplo, "Pote 160g ×40, Copo ×20 …". O "…" só aparece quando há mais de `max` itens, e o texto é "Sem itens" quando não há nenhum.
  - `List<Map<String, dynamic>> pedidosParaRepetir(List<Map<String, dynamic>> pedidos)`:
    - tira os `cancelado`;
    - ordena por `datahora` (ISO) do mais novo para o mais velho, com as datas que não dão para ler no fim;
    - devolve no máximo 5.
  - Em `db.dart`: `Future<List<Map<String, dynamic>>> listarPedidosDoCliente(int clienteId)`. Devolve as linhas da tabela `pedidos` com esse `cliente_id`, já passadas por `pedidosParaRepetir`.

- [ ] **Step 1: Escrever os testes que falham.** Use um catálogo `[Produto(id:1,nome:'Pote 160g',preco:5), Produto(id:2,nome:'Copo',preco:3)]`.
  - `casa por nome sem caixa e espaços`: o pedido `[{'nome':' pote 160G ','quantidade':40}]` dá `quantidades == {Pote 160g: 40}`.
  - `soma o mesmo produto repetido`: dois itens "Copo" com 2 e 3 dão `{Copo: 5}`.
  - `aceita quantidade string e double, ignora zero`: `'40'` dá 40, `20.0` dá 20, e `0` não entra.
  - `produto que sumiu vai para foraDoPedido`: `[{'nome':'Geladinho','quantidade':10}]` dá `quantidades` vazio e `foraDoPedido == ['Geladinho']`.
  - `json corrompido não quebra`: `'{x'`, `null` e `42` dão `quantidades` vazio, e `resumoItens` de cada um dá `'Sem itens'`.
  - `aceita String JSON`: `jsonEncode([...])` dá o mesmo resultado da `List`.
  - `resumo com reticências`: 4 itens com `max: 3` dão `'A ×1, B ×2, C ×3 …'`.
  - `pedidosParaRepetir`: com 7 pedidos (um `cancelado`, um com `datahora` inválida), sai sem o cancelado, o de data inválida fica por último, e saem no máximo 5.
  - `listarPedidosDoCliente`, com banco ffi em memória como em `test/apagado_no_controle_test.dart`: grava pedidos dos clientes 7 e 8 e confere que só vêm os do 7.

- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/repetir_pedido_test.dart`. Esperado: FAIL, porque o arquivo `repetir_pedido.dart` ainda não existe.

- [ ] **Step 3: Implementar** as funções acima em `repetir_pedido.dart` e `listarPedidosDoCliente` em `db.dart`. A consulta é `SELECT * FROM pedidos WHERE cliente_id = ?`, e o filtro e a ordem ficam no Dart, com `pedidosParaRepetir`.

- [ ] **Step 4: Rodar e ver passar.** Mesmo comando. Esperado: PASS. Depois, `flutter analyze` sem aviso novo.

- [ ] **Step 5: Commit.** `git add app/lib/utils/repetir_pedido.dart app/lib/utils/db.dart app/test/repetir_pedido_test.dart && git commit -m "feat(repetir): casar itens do pedido antigo com os produtos de hoje"`

---

### Task 2: Quadro "Partir de um pedido anterior" na tela de novo pedido (A)

**Files:**
- Create: `app/lib/widgets/pedidos_anteriores.dart`
- Modify: `app/lib/pages/pedido_page.dart`
- Test: `app/test/telas_repetir_pedido_test.dart`

**Interfaces:**
- Consumes: `preencherDePedido`, `resumoItens`, `listarPedidosDoCliente` (Tarefa 1); `formatarReais` (`utils/moeda.dart`).
- Produces:
  - `class QuadroPedidosAnteriores extends StatelessWidget`, com `pedidos: List<Map<String, dynamic>>` e `onUsar: void Function(Map<String, dynamic> pedido)`. Mostra `SizedBox.shrink()` quando a lista é vazia. Cada linha tem a data `dd/MM` (hora local), `formatarReais(total)`, `resumoItens(produtos)` e o botão "Usar".
  - Na `PedidoPage`:
    - parâmetro opcional `Future<List<Map<String, dynamic>>> Function(int clienteId)? carregarPedidosDoCliente`. Quando é nulo, usa `listarPedidosDoCliente`. Os testes injetam um falso.
    - métodos privados `Future<void> _aplicarCliente(Map<String, dynamic> cli)` e `void _aplicarPreenchimento(Preenchimento p)`, que a Tarefa 3 reaproveita.

- [ ] **Step 1: Escrever os testes que falham**, no estilo de `test/telas_pronto_assinaturas_test.dart`, com `dadosParaCaptura` e `carregarPedidosDoCliente` falso.
  - `quadro aparece depois de escolher o cliente`: escolhe o cliente 7 pela busca. Esperado: o texto "Partir de um pedido anterior" e uma linha por pedido devolvido.
  - `cliente sem pedidos não mostra o quadro`.
  - `Usar com a tela vazia preenche sem perguntar`: os campos de quantidade mostram "40" e "20", e não aparece o diálogo.
  - `Usar com quantidades na tela pergunta antes`:
    - "Cancelar" mantém as quantidades digitadas;
    - "Trocar" aplica as do pedido e zera os produtos que não estão nele.
  - `produto que sumiu mostra o aviso`: aparece um SnackBar com "Ficaram de fora (não estão mais à venda): Geladinho".
  - `trocar de cliente atualiza o quadro` (Review Focus 5): o cliente 7 tem o pedido A, e o 8 tem o pedido B. Depois de trocar para o 8, aparece só o B.

- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/telas_repetir_pedido_test.dart`. Esperado: FAIL.

- [ ] **Step 3: Implementar.**
  - Extrair para `_aplicarCliente` o bloco do `.then` de `_autoPreencherClientePorNome` (linhas ~260-276). Esse bloco preenche os campos e chama `_recarregarUltimoPedido`, e agora também carrega `_anteriores` com `carregarPedidosDoCliente`.
  - `_aplicarPreenchimento` põe em cada produto de `carrinho` a quantidade do preenchimento, ou 0, e atualiza o texto dos `_qtdControllers` (vazio quando é 0). Se `foraDoPedido` não estiver vazio, mostra o aviso.
  - O quadro entra logo depois do `MdCard` de "Dados do Cliente". A confirmação usa `showDialog` com os textos exatos das Global Constraints.

- [ ] **Step 4: Rodar e ver passar.** Rodar o teste novo e depois `flutter test`, a suíte inteira do app. Esperado: tudo PASS. Depois, `flutter analyze` sem aviso novo.

- [ ] **Step 5: Commit.** `git commit -m "feat(repetir): quadro dos pedidos anteriores na tela de novo pedido"`, com os arquivos da tarefa.

---

### Task 3: Ação "Repetir" na lista de Pedidos (B)

**Files:**
- Modify: `app/lib/pages/pedido_page.dart`, `app/lib/pages/pedidos_page.dart`, `app/lib/pages/home_page.dart:335`
- Test: `app/test/telas_repetir_pedido_test.dart` (mesmo arquivo da Tarefa 2)

**Interfaces:**
- Consumes: `_aplicarCliente` e `_aplicarPreenchimento` (Tarefa 2); `preencherDePedido` (Tarefa 1).
- Produces:
  - `PedidoPage({..., Map<String, dynamic>? partirDe})`: quando os clientes e os produtos terminam de carregar (inclusive pelo `dadosParaCaptura`), acha o cliente de `partirDe['cliente_id']` em `clientes`, chama `_aplicarCliente` e depois `_aplicarPreenchimento(preencherDePedido(partirDe['produtos'], produtos))`. Sem perguntar, porque a tela está vazia. O número do pedido continua sendo o próximo, nunca o do pedido de partida.
  - `PedidosPage({..., Map<String, dynamic>? vendedor, Future<List<Map<String, dynamic>>> Function() listarClientesDoAparelho = listarClientes})`.
    - A `home_page.dart` passa `vendedor: widget.vendedor`.
    - Quando `vendedor` é nulo, usa `{'codigo': p['vendedor_codigo'], 'nome': p['vendedor_nome']}` do pedido.

- [ ] **Step 1: Escrever os testes que falham.**
  - `Repetir aparece em pedido com cliente`: aparece nas abas Em aberto e Entregues, e não aparece em pedido sem `cliente_id` nem em pedido apagado no Controle.
  - `Repetir com cliente apagado avisa e não abre`: com `listarClientesDoAparelho` sem o cliente, aparece o SnackBar "Este cliente não está mais cadastrado" e a tela continua na lista.
  - `PedidoPage com partirDe abre preenchida`: com `dadosParaCaptura` e `partirDe`, o campo Nome mostra o cliente, as quantidades aparecem e não há diálogo de confirmação.

- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/telas_repetir_pedido_test.dart`. Esperado: FAIL nos três testes novos.

- [ ] **Step 3: Implementar.**
  - O `_acao(label: 'Repetir', icon: Icons.replay, ...)` entra como último botão nas duas listas de `_pedidoTile`, a de somente leitura e a de em aberto. Não entra no ramo `apagado` e só aparece quando `p['cliente_id'] != null`.
  - Ao tocar, procura o cliente em `listarClientesDoAparelho()` e, se achar, faz `Navigator.push` da `PedidoPage(vendedor: ..., partirDe: p)`.
  - Na volta, chama `_carregar()`, como `_editar` já faz.

- [ ] **Step 4: Rodar e ver passar.** `flutter test`, a suíte inteira do app, e `flutter analyze`. Esperado: tudo PASS, sem aviso novo. Depois, conferir a captura visual da lista com `flutter test test/visual` e ver se os botões cabem num celular de 360 de largura.

- [ ] **Step 5: Commit.** `git commit -m "feat(repetir): ação Repetir na lista de pedidos"`, com os arquivos da tarefa.
