# Clientes sumidos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O vendedor vê os clientes dele que não compram há 30, 60 ou 90 dias e chama pelo WhatsApp, pelo telefone, ou abre um pedido novo.

**Architecture:**
- **Funções puras:** uma monta a lista a partir dos clientes e dos pedidos locais, e outra gera os links de WhatsApp e de telefone.
- **Telas:** uma tela nova com acesso pela tela inicial. A `PedidoPage` ganha um parâmetro para abrir com o cliente já escolhido.
- **Servidor e banco:** nada muda no servidor nem no esquema do SQLite.

**Tech Stack:** Flutter 3.41 / Dart 3.11, sqflite (testes com sqflite_common_ffi), `url_launcher` (já resolvido 6.3.2 como transitivo; vira direto), `milkdim_ui`.

**Spec:** `docs/superpowers/specs/2026-11-27-clientes-sumidos-design.md`

## Global Constraints

- Só `app/` muda. Nada em `admin/`, `supabase/` nem no esquema do SQLite.
- **Quem conta:** pedidos do aparelho **deste vendedor** (`vendedor_codigo`), sem `cancelado` e sem os apagados no Controle (`apagadoNoControle` de `regras_pedido.dart`). Cliente sumido é aquele cujo último pedido tem `>=` prazo dias.
- **Prazos:** 30, 60 e 90 dias; o padrão é 30. A lista vai do menos dias para o mais dias.
- **Telefone:** só dígitos. Com 10 ou 11 dígitos, recebe "55" na frente. Com 12 ou 13 dígitos começando com "55", fica como está. Qualquer outro caso é inválido. Links: `https://wa.me/<num>?text=<mensagem codificada>` e `tel:<num>`.
- **Textos exatos:**
  - item da tela inicial: "Clientes sumidos", com o subtítulo "{N} sem comprar há 30 dias ou mais";
  - linha da lista: "Última compra dd/MM · há N dias" e "N pedidos" ("1 pedido" no singular);
  - lista vazia: "Nenhum cliente sumido há {N} dias ou mais.";
  - botões: "WhatsApp", "Ligar", "Novo pedido";
  - mensagem: "Olá! Aqui é o {nome do vendedor} da MilkDim. Faz um tempinho que a gente não se fala, posso passar aí essa semana?"
- Nenhum pedido local é alterado: tudo só lê.

## Review Focus

1. **Cliente com pedidos de dois vendedores no mesmo aparelho:** só conta o deste vendedor. Teste na Tarefa 1.
2. **Telefone com máscara** ("(16) 99999-1234") ou com "+55": é normalizado. Telefone curto ou vazio fica inválido e desliga o botão. Testes nas Tarefas 1 e 2.
3. **Limite exato do prazo:** com 30 dias certos entra; com 29 não entra. A conta é por dia de calendário local, não por horas. Teste na Tarefa 1.
4. **`datahora` ilegível** num pedido: é ignorado, sem quebrar a lista. Teste na Tarefa 1.
5. **Cliente sem WhatsApp mas com telefone:** "WhatsApp" usa o telefone, e "Ligar" usa o telefone. Teste na Tarefa 1.

---

### Task 1: Lista de sumidos e links (funções puras + consulta)

**Files:**
- Create: `app/lib/utils/clientes_sumidos.dart`
- Modify: `app/lib/utils/db.dart` (nova consulta)
- Test: `app/test/clientes_sumidos_test.dart`

**Interfaces:**
- Produces:
  - `class ClienteSumido { final Map<String, dynamic> cliente; final DateTime ultimaCompra; final int dias; final int pedidos; }`
  - `List<ClienteSumido> clientesSumidos({required List<Map<String, dynamic>> clientes, required List<Map<String, dynamic>> pedidos, required String vendedorCodigo, required DateTime agora, int prazoDias = 30})`
    - Agrupa os `pedidos` válidos (as regras de "Quem conta") por `cliente_id`.
    - `dias` é a diferença em dias de calendário local entre `agora` e a última compra.
    - Só entram clientes que estão em `clientes` e têm `dias >= prazoDias`.
    - A ordem é por `dias` crescente.
  - `String? normalizarTelefone(String? bruto)`
  - `Uri? linkWhatsApp(Map<String, dynamic> cliente, String mensagem)`: usa `whatsapp`; se ele for inválido, usa `telefone`.
  - `Uri? linkLigar(Map<String, dynamic> cliente)`: usa `telefone`; se ele for inválido, usa `whatsapp`.
  - `String mensagemSumido(String nomeVendedor)`: devolve a mensagem exata das Global Constraints.
  - Em `db.dart`: `Future<List<Map<String, dynamic>>> listarPedidosParaSumidos(String vendedorCodigo)`, com `SELECT cliente_id, datahora, status, erro_envio, vendedor_codigo FROM pedidos WHERE cliente_id IS NOT NULL AND vendedor_codigo = ?`.

- [ ] **Step 1: Testes que falham** em `app/test/clientes_sumidos_test.dart`, com `agora = DateTime(2026, 11, 27, 10)`.
  - `30 dias certos entra, 29 não`.
  - `só pedidos deste vendedor`: o cliente 7 tem um pedido de "0002" de 40 dias atrás e um de "0003" de 2 dias atrás. Para "0002" ele está sumido há 40 dias; para "0003", não.
  - `ignora cancelado e apagado no Controle`: o último pedido válido é que define a data.
  - `datahora ilegível é ignorada`.
  - `ordem por dias crescente` e `pedidos conta só os válidos`.
  - `cliente fora da lista de clientes não aparece`.
  - `normalizarTelefone`:
    - `'(16) 99999-1234'` dá `'5516999991234'`;
    - `'+55 16 3333-4444'` dá `'551633334444'`;
    - `'1234'`, `''` e `null` dão `null`.
  - `linkWhatsApp` sem whatsapp usa o telefone; o texto codificado contém "MilkDim".
  - `linkLigar` sem telefone usa o whatsapp; tudo inválido dá `null`.
  - `listarPedidosParaSumidos` (ffi em memória, como em `test/repetir_pedido_test.dart`): só vêm os pedidos do vendedor pedido.
- [ ] **Step 2: Rodar e ver falhar.** `cd app && flutter test test/clientes_sumidos_test.dart`. Esperado: FAIL, porque o arquivo ainda não existe.
- [ ] **Step 3: Implementar** as funções acima.
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test` e `flutter analyze` sem aviso novo.
- [ ] **Step 5: Commit.** `feat(sumidos): lista de clientes sumidos e links de contato`

---

### Task 2: Tela "Clientes sumidos", item na tela inicial e pedido com cliente escolhido

**Files:**
- Create: `app/lib/pages/clientes_sumidos_page.dart`
- Modify: `app/pubspec.yaml` (`url_launcher: ^6.3.2` em dependencies), `app/android/app/src/main/AndroidManifest.xml` (`<queries>`: VIEW com scheme `https` e VIEW com scheme `tel`), `app/lib/pages/home_page.dart`, `app/lib/pages/pedido_page.dart`
- Test: `app/test/telas_clientes_sumidos_test.dart`

**Interfaces:**
- Consumes: tudo o que a Tarefa 1 produz; `listarClientes()` (db.dart).
- Produces:
  - `ClientesSumidosPage({required Map<String, dynamic> vendedor, DateTime Function()? relogio, Future<List<Map<String, dynamic>>> Function()? carregarClientes, Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)? carregarPedidos, Future<bool> Function(Uri)? abrirLink, ...})`. Os parâmetros opcionais existem para os testes; quando são nulos, a tela usa o relógio, o banco e o `launchUrl` com `LaunchMode.externalApplication`.
  - `PedidoPage({..., int? clienteInicialId})`: aplica `_aplicarCliente` uma única vez, quando clientes e produtos estiverem prontos, como `_tentarPartirDe` já faz. Se `partirDe` também vier, `partirDe` tem prioridade.

- [ ] **Step 1: Testes que falham**, com fakes injetados e o relógio fixo em 27/11/2026.
  - `mostra os sumidos com data, dias e pedidos`: os textos aparecem exatamente como nas Global Constraints.
  - `trocar para 60 dias esconde quem tem 45`.
  - `lista vazia mostra a mensagem`.
  - `WhatsApp chama abrirLink com wa.me e o nome do vendedor`: o vendedor é `{'codigo':'0002','nome':'Carlos'}`.
  - `sem telefone válido, WhatsApp e Ligar ficam desligados`.
  - `Novo pedido abre PedidoPage com clienteInicialId`: o teste confere o widget empurrado, ou o tipo da rota.
  - `PedidoPage com clienteInicialId preenche o Nome`: usa `dadosParaCaptura`.
  - Na tela inicial: `item Clientes sumidos mostra a contagem`. Se a `HomePage` não for testável sem banco, troque por um teste do texto do subtítulo numa função pura `subtituloSumidos(int n)` e explique no relatório.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
  - A tela usa os componentes de `milkdim_ui` (MdCard, MdSpace…) e escolhas de prazo (`ChoiceChip`, ou o equivalente de `milkdim_ui`).
  - Na tela inicial, o item entra depois de "Meus pedidos". A contagem é calculada ao abrir a tela inicial e ao voltar de qualquer tela, junto com `_atualizarPendentes`.
- [ ] **Step 4: Rodar e ver passar.** `flutter test`, `flutter analyze`, e `flutter test test/visual` se a tela inicial tiver captura (conferir se nada quebrou).
- [ ] **Step 5: Commit.** `feat(sumidos): tela de clientes sumidos com WhatsApp, ligar e novo pedido`
