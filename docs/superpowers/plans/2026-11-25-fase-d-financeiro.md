# Fase D (parte 1): Plano de implementação do financeiro

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar uma aba Financeiro no Controle que mostra vendas, saídas e resultado de cada mês, e permite lançar saídas por categoria.

**Architecture:**
- **Banco:** ganha só `categorias_saida` e `saidas`, com RLS só para administrador e auditoria preenchida por gatilho.
- **Controle:** baixa os pedidos entregues do mês, os prontos e as saídas, e faz as contas numa função pura em Dart. As somas são feitas em centavos inteiros.
- **Tela:** recebe uma `FonteFinanceiro`, que nos testes é trocada por uma falsa.

**Tech Stack:** Flutter 3.41 / Dart 3.11 (Windows), supabase_flutter, intl, Postgres no Supabase.

**Spec:** `docs/superpowers/specs/2026-11-25-fase-d-financeiro-design.md`

## Global Constraints

- **Repositório público:** nenhuma senha, chave, URL ou ref do projeto Supabase em arquivo versionado.
- **Banco de produção:** nenhuma migração é aplicada sem mostrar o SQL ao Kaiki e receber OK no chat. O teste SQL roda antes em `begin … rollback`.
- **Pedidos:** a fase só **lê** pedidos e não altera nenhum.
- **Quando a venda conta:**
  - venda = pedido com `status = 'finalizado'`, no mês de `finalizado_em`;
  - `cancelado` e `salvo` ficam fora;
  - `pronto` entra só em "A receber", e só no mês atual.
- **Mês local:** o mês é contado na hora local, de `DateTime(ano, mes, 1)` (inclusive) até `DateTime(ano, mes + 1, 1)` (exclusive). As duas bordas vão para o banco em UTC (`toUtc()`).
- **Dinheiro:** as somas são em centavos inteiros: `centavos(v) = (v * 100).round()`.
- **Agrupamentos:**
  - vendas por produto agrupam pelo `nome` do item, sem espaços nas pontas;
  - vendas por vendedor agrupam pelo `vendedorNome` (sem espaços nas pontas) ou, se ele estiver vazio, pelo `vendedorCodigo`;
  - cada lista vem do maior valor para o menor e, no empate, pelo rótulo.
- **Categorias iniciais**, nesta ordem (`ordem` de 1 a 8): Matéria-prima, Embalagens, Combustível/entrega, Salários, Aluguel/contas (água, luz, gás), Impostos, Manutenção, Outros.
- **Categoria com saídas** não é apagada, só desativada (`ativa = false`). Desativada, ela some do lançamento mas aparece nos meses antigos.
- **Auditoria:**
  - `criado_por` e `alterado_por` vêm de `public.app_autor_pedido()`, num gatilho `security definer` com `set search_path = ''`;
  - o cliente não consegue forjar esses campos;
  - sem JWT (SQL Editor), o autor fica NULL.
- **Visual:** a tela usa os componentes e tokens de `packages/milkdim_ui`, como as outras abas do Controle. Não cria tema próprio.
- **Textos fixos da tela:**
  - "Financeiro", "Vendas", "Saídas", "Resultado do mês", "A receber";
  - "Lançar saída", "Até 23/11/2026, a data é a do pedido.", "Tentar de novo".

## Review Focus

1. **Pedido entregue perto da virada do mês na hora local:**
   - entregue em 30/11 às 23:30 (02:30 UTC de 01/12) conta em novembro;
   - entregue em 01/12 à 00:10 local conta em dezembro.
   - Testado na Tarefa 2 (`intervaloDoMes`) e na Tarefa 3 (borda nos parâmetros).
2. **Valor digitado em formato brasileiro:**
   - "1.234,56", "480,5" e "R$ 480,00" funcionam;
   - "0", "-5", "abc", "" e "12,345" são recusados com mensagem, sem gravar.
   - Testado na Tarefa 2 (`parseValorCentavos`).
3. **Falha de rede ao abrir a aba:** mostra erro com "Tentar de novo", nunca zeros. Testado na Tarefa 4.
4. **Categoria desativada:**
   - não aparece no diálogo de lançar;
   - a saída antiga dela continua aparecendo com o nome no mês antigo.
   - Testado nas Tarefas 4 e 5.
5. **Mês sem venda nenhuma, ou com resultado negativo:**
   - o mês vazio mostra R$ 0,00 e não quebra;
   - o resultado negativo mostra "-R$ …" em destaque.
   - Testado nas Tarefas 2 e 4.

---

### Task 1: Migração das saídas e teste SQL

**Files:**
- Create: `supabase/migrations/20261125000001_fase_d_saidas.sql`
- Create: `supabase/tests/fase_d_test.sql`

**Interfaces:**
- Produces:
  - **`public.categorias_saida`:**
    - `id bigint generated always as identity primary key`;
    - `nome text not null`, com um índice único em `lower(btrim(nome))`;
    - `ativa boolean not null default true`;
    - `ordem int not null default 100`.
  - **`public.saidas`:**
    - `id bigint generated always as identity primary key`;
    - `data date not null`;
    - `categoria_id bigint not null references public.categorias_saida(id) on delete restrict`;
    - `descricao text not null default ''`;
    - `valor numeric(12,2) not null check (valor > 0)`;
    - `criado_em timestamptz`, `criado_por text`, `alterado_em timestamptz`, `alterado_por text`;
    - índice `saidas_data_idx` em `(data)`.
  - **Gatilho `saidas_auditoria`** (`before insert or update`, função `public.saidas_auditoria()` `security definer`, `set search_path = ''`):
    - no insert grava `criado_em = now()` e `criado_por = public.app_autor_pedido()`, e copia os mesmos dois valores para `alterado_*`;
    - no update mantém `criado_*` do `old` e grava `alterado_*` com `now()` e o autor.
  - **Permissões:**
    - RLS ligada nas duas tabelas;
    - uma política `for all to authenticated using (public.app_is_admin()) with check (public.app_is_admin())` por tabela;
    - `revoke all … from anon`;
    - `grant select, insert, update, delete … to authenticated`.
  - **Dados iniciais:** as 8 categorias iniciais com `ordem` de 1 a 8, inseridas só se não existirem (idempotente, como `on conflict do nothing` sobre o índice).
  - **Formato do arquivo:** segue o estilo das migrações anteriores, com `begin;` e `commit;` de fora, comentários em português e sem acentos.

- [ ] **Step 1: Escrever `supabase/tests/fase_d_test.sql`**

  No estilo de `supabase/tests/fase_b_test.sql`: sem abrir nem fechar a transação, cada bloco dá `raise exception 'FALHA: …'` quando a verificação falha. Quem roda é `begin; <migração>; <teste>; rollback;`.

  **Personagens:**
  - vendedor comum `-910`;
  - admin `-911`, com `is_admin = true`;
  - `sem`, uma conta autenticada sem linha em `vendedores`;
  - todos criados com `app_criar_usuario_auth` e senha aleatória, como no bloco 0 da fase B.

  **Verificações:**
  1. Existem exatamente as 8 categorias iniciais, com `ordem` de 1 a 8 e todas ativas.
  2. Como admin `-911`:
     - um `insert` em `saidas` mandando `criado_por = 'forjado'` e `criado_em = '2000-01-01'` grava `criado_por = '-911'` e `criado_em = now()`;
     - um `update` do valor grava `alterado_por = '-911'` e mantém `criado_por`.
  3. Como admin: `valor = 0` dá SQLSTATE `23514`.
  4. Como admin:
     - criar a categoria `' matéria-PRIMA '` dá `23505`;
     - apagar uma categoria com saída dá `23503`.
  5. Como vendedor `-910`:
     - `select count(*) from saidas` devolve 0 linhas, embora exista uma;
     - um `insert` dá `42501`;
     - `select` em `categorias_saida` devolve 0 linhas.
  6. Como `sem` (autenticado e sem vendedor): `select` devolve 0 linhas.
  7. Como `anon`: `select` em `saidas` dá `42501`.
  8. Nenhum pedido mudou: `count(*)` e `sum(total)` de `pedidos` são iguais antes e depois do teste.

- [ ] **Step 2: Escrever a migração** com as interfaces acima.

- [ ] **Step 3: Verificar a sintaxe localmente**

  Não há Postgres local. O controlador roda `begin; <migração>; <teste>; rollback;` contra a produção pelo MCP `execute_sql`, e o resultado esperado é terminar sem exceção.

  Quem implementa só confere que o arquivo não tem `commit` nem `rollback`. O passo de rodar fica com o controlador.

- [ ] **Step 4: Commit**
```bash
git add supabase/migrations/20261125000001_fase_d_saidas.sql supabase/tests/fase_d_test.sql
git commit -m "feat(fase-d): tabelas de saídas e categorias com RLS de admin"
```

### Task 2: Modelos e contas do mês (Dart puro)

**Files:**
- Create: `admin/lib/financeiro/modelos_financeiro.dart`
- Create: `admin/lib/financeiro/resumo_financeiro.dart`
- Test: `admin/test/financeiro_resumo_test.dart`

**Interfaces:**
- Consumes:
  - `Pedido` (`admin/lib/models/pedido.dart`): `total`, `status`, `vendedorNome`, `vendedorCodigo`, `finalizadoEm`, `itens`;
  - `PedidoItem`: `nome`, `quantidade`, `subtotal`.
- Produces:
  - `class CategoriaSaida { final int id; final String nome; final bool ativa; final int ordem; factory CategoriaSaida.fromMap(Map<String, dynamic>) }`
  - `class Saida { final int? id; final DateTime data; final int categoriaId; final String descricao; final int valorCentavos; final String? criadoPor; final DateTime? criadoEm; factory Saida.fromMap(Map<String, dynamic>); Map<String, dynamic> toGravar() }`
    - `toGravar()` traz só `data` (`'yyyy-MM-dd'`), `categoria_id`, `descricao` e `valor` (número com 2 casas). Nunca traz `id` nem campos de auditoria.
  - `int centavos(num v)`
  - `int? parseValorCentavos(String texto)`
  - `String fmtCentavos(int c)`:
    - usa o formato pt_BR com separador de milhar e `R$`;
    - troca o espaço não separável por espaço comum;
    - negativo sai como `-R$ 3.290,00`.
  - `({DateTime inicio, DateTime fim}) intervaloDoMes(int ano, int mes)`, com as duas datas locais.
  - `class LinhaValor { final String rotulo; final int centavos; final int quantidade; }`
  - `class ResumoMes { final int vendasCentavos; final int pedidos; final int saidasCentavos; int get resultadoCentavos; final List<LinhaValor> porVendedor; final List<LinhaValor> porProduto; final List<LinhaValor> porCategoria; final int aReceberPedidos; final int aReceberCentavos; }`
    - Em `porProduto`, `quantidade` é o total de unidades.
    - Em `porVendedor`, `quantidade` é o número de pedidos.
  - `ResumoMes resumirMes({required List<Pedido> entregues, required List<Pedido> prontos, required List<Saida> saidas, required Map<int, String> nomesCategorias})`
    - Ignora em `entregues` o que não tiver `status == 'finalizado'`.
    - Uma categoria ausente do mapa vira `'Sem categoria'`.

- [ ] **Step 1: Testes que falham** (os nomes e as asserções são obrigatórios)

```dart
test('parseValorCentavos aceita formato brasileiro', () {
  expect(parseValorCentavos('1.234,56'), 123456);
  expect(parseValorCentavos('480,5'), 48050);
  expect(parseValorCentavos('R\$ 480,00'), 48000);
  expect(parseValorCentavos(' 75 '), 7500);
});
test('parseValorCentavos recusa inválidos', () {
  for (final t in ['0', '-5', 'abc', '', '12,345', '0,00']) {
    expect(parseValorCentavos(t), isNull, reason: t);
  }
});
test('fmtCentavos', () {
  expect(fmtCentavos(842000), 'R\$ 8.420,00');
  expect(fmtCentavos(0), 'R\$ 0,00');
  expect(fmtCentavos(-329000), '-R\$ 3.290,00');
});
test('intervaloDoMes usa a hora local e vira o ano', () {
  final n = intervaloDoMes(2026, 11);
  expect(n.inicio, DateTime(2026, 11, 1));
  expect(n.fim, DateTime(2026, 12, 1));
  expect(intervaloDoMes(2026, 12).fim, DateTime(2027, 1, 1));
});
test('resumirMes soma em centavos, agrupa e ordena', () { /* 3 pedidos finalizados de 0,10 + 0,20 (sem erro de float: vendas == 30 centavos por pedido),
  dois vendedores (um sem nome -> código), item com o mesmo nome com espaço nas pontas agrupado,
  um pedido 'cancelado' na lista de entregues ignorado, 2 saídas em 2 categorias, 1 pronto de 15,00.
  Esperado: pedidos == 3; porVendedor ordenado por centavos desc; porProduto com unidades somadas;
  saidasCentavos e porCategoria corretos; resultadoCentavos == vendas - saídas; aReceberPedidos == 1, aReceberCentavos == 1500. */ });
test('mês vazio dá zeros e listas vazias', () { /* tudo vazio -> 0, 0, [], resultado 0 */ });
test('resultado negativo', () { /* saídas > vendas -> resultadoCentavos < 0 */ });
test('Saida.toGravar não leva id nem auditoria', () { /* chaves == {data, categoria_id, descricao, valor}; data '2026-11-05' */ });
test('Saida.fromMap lê valor numeric como texto ou número', () { /* valor '480.00' e 480 -> 48000 */ });
```

  O corpo dos testes marcados com `/* */` é escrito por quem implementa, com os valores descritos no comentário.

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_resumo_test.dart`. Esperado: FAIL na compilação, porque os arquivos ainda não existem.

- [ ] **Step 3: Implementar os dois arquivos.** Use `NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')` do `intl`.

- [ ] **Step 4: Rodar e ver passar.** Mesmo comando. Esperado: tudo PASS.

- [ ] **Step 5: Commit**
```bash
git add admin/lib/financeiro admin/test/financeiro_resumo_test.dart
git commit -m "feat(financeiro): modelos, valor em centavos e resumo do mês"
```

### Task 3: Serviço do financeiro

**Files:**
- Create: `admin/lib/services/financeiro_service.dart`
- Test: `admin/test/financeiro_service_test.dart`

**Interfaces:**
- Consumes:
  - da Tarefa 2: `Saida`, `CategoriaSaida`;
  - `colunasPedidoSemAssinatura` e a conversão de linha para `Pedido` já usadas em `supabase_service.dart`. Reaproveite a função de conversão existente, deixando-a pública se for privada, sem duplicar o mapeamento;
  - `RepoFailure`.
- Produces:
  - `abstract class FonteFinanceiro`, com os métodos:
    - `Future<List<Pedido>> pedidosEntregues(DateTime inicioLocal, DateTime fimLocal)`
    - `Future<List<Pedido>> pedidosProntos()`
    - `Future<List<Saida>> saidasEntre(DateTime inicioLocal, DateTime fimLocal)`
    - `Future<List<CategoriaSaida>> categorias()`
    - `Future<void> inserirSaida(Saida s)`
    - `Future<void> alterarSaida(Saida s)`
    - `Future<void> apagarSaida(int id)`
    - `Future<void> criarCategoria(String nome)`
    - `Future<void> renomearCategoria(int id, String nome)`
    - `Future<void> definirCategoriaAtiva(int id, bool ativa)`
  - `class FinanceiroService implements FonteFinanceiro`, com o construtor `FinanceiroService([SupabaseClient? injected])`.
    - Os erros saem como `RepoFailure` com mensagem em português.
    - `23505` vira "Já existe uma categoria com esse nome.".
    - `23503` vira "Essa categoria tem saídas; desative em vez de apagar.".
  - Funções estáticas testáveis:
    - `static ({String de, String ate}) filtroEntregues(DateTime inicioLocal, DateTime fimLocal)`: os textos ISO em UTC para `gte('finalizado_em', de)` e `lt('finalizado_em', ate)`;
    - `static ({String de, String ate}) filtroSaidas(DateTime inicioLocal, DateTime fimLocal)`: `'yyyy-MM-dd'` para `gte('data', de)` e `lt('data', ate)`.
  - **Comportamento das buscas:**
    - `pedidosEntregues` filtra `status = 'finalizado'` e pagina com `.range` em blocos de 1000 até vir um bloco menor;
    - `pedidosProntos` filtra `status = 'pronto'`;
    - `categorias()` traz todas, ativas e inativas, ordenadas por `ordem` e depois `nome`.

- [ ] **Step 1: Testes que falham**

```dart
test('filtroEntregues converte as bordas locais para UTC', () {
  final f = FinanceiroService.filtroEntregues(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
  expect(DateTime.parse(f.de), DateTime(2026, 11, 1).toUtc());
  expect(DateTime.parse(f.ate), DateTime(2026, 12, 1).toUtc());
  expect(f.de.endsWith('Z'), isTrue);
});
test('entregue 30/11 23:30 local cai dentro de novembro', () {
  final f = FinanceiroService.filtroEntregues(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
  final t = DateTime(2026, 11, 30, 23, 30).toUtc();
  expect(!t.isBefore(DateTime.parse(f.de)) && t.isBefore(DateTime.parse(f.ate)), isTrue);
});
test('filtroSaidas usa datas', () {
  final f = FinanceiroService.filtroSaidas(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
  expect(f.de, '2026-11-01');
  expect(f.ate, '2026-12-01');
});
```

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_service_test.dart`. Esperado: FAIL na compilação.

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test test/financeiro_service_test.dart test/supabase_service_test.dart`. Esperado: PASS.

- [ ] **Step 5: Commit**
```bash
git add admin/lib/services admin/test/financeiro_service_test.dart
git commit -m "feat(financeiro): serviço de pedidos do mês, saídas e categorias"
```

### Task 4: Aba Financeiro (resumo do mês)

**Files:**
- Create: `admin/lib/tabs/financeiro_tab.dart`
- Modify: `admin/lib/pages/home_page.dart` (6ª aba)
- Test: `admin/test/financeiro_tab_test.dart`

**Interfaces:**
- Consumes:
  - da Tarefa 2: `resumirMes`, `fmtCentavos`, `intervaloDoMes`;
  - da Tarefa 3: `FonteFinanceiro` e `FinanceiroService`.
- Produces:
  - `class FinanceiroTab extends StatefulWidget { const FinanceiroTab({super.key, this.fonte, this.agora}); final FonteFinanceiro? fonte; final DateTime Function()? agora; }`
    - Com `fonte` nula, usa `FinanceiroService()`.
    - Com `agora` nulo, usa `DateTime.now`.
  - Em `home_page.dart`:
    - `_tabs` ganha `const FinanceiroTab()`;
    - `_titles` ganha `'Financeiro'`;
    - `_tabIcons` ganha `Icons.account_balance_wallet_rounded`.
  - **Layout da tela:**
    - **Cabeçalho do mês:** "◀ Novembro 2026 ▶", com o nome do mês em pt_BR e a inicial maiúscula; abre no mês de `agora()`.
    - **Resumo:** três números, "Vendas" (com "(N pedidos)"), "Saídas" e "Resultado do mês". O resultado negativo usa a cor de erro do tema.
    - **Quadros:** "Vendas por vendedor", "Vendas por produto" (unidades e R$), "Saídas por categoria" e "A receber". O "A receber" só aparece no mês de `agora()`.
    - **Aviso de histórico:** a linha "Até 23/11/2026, a data é a do pedido." aparece nos meses até novembro de 2026, inclusive.
  - **Carga e estados:**
    - carrega ao abrir, ao trocar de mês e no `IconButton` "Atualizar";
    - o erro mostra a mensagem e "Tentar de novo";
    - durante a carga aparece um `CircularProgressIndicator`.
  - **Lista e botão:**
    - a lista das saídas do mês mostra data, categoria, descrição e valor;
    - o botão "Lançar saída" fica no topo, e a ação dele vem na Tarefa 5.
    - Por enquanto, o botão chama `_lancarSaida()`, que a Tarefa 5 completa.

- [ ] **Step 1: Testes de widget que falham.** Use uma `_FonteFalsa implements FonteFinanceiro` com listas em memória e um contador de chamadas.

```dart
testWidgets('mostra vendas, saídas e resultado do mês atual', (t) async { /* agora 25/11/2026; 2 entregues (R$ 100 + R$ 50), 1 saída R$ 30 ->
  find.text('R\$ 150,00'), find.text('R\$ 30,00'), find.text('R\$ 120,00'), find.text('A receber') existem */ });
testWidgets('mês anterior não mostra A receber e mostra o aviso de histórico', (t) async { /* toca ◀ -> outubro: find.text('A receber') findsNothing;
  find.text('Até 23/11/2026, a data é a do pedido.') findsOneWidget; fonte recebeu inicio=DateTime(2026,10,1) */ });
testWidgets('dezembro de 2026 não mostra o aviso', (t) async { /* agora 10/12/2026 -> aviso findsNothing */ });
testWidgets('erro de rede mostra Tentar de novo e não zeros', (t) async { /* fonte lança RepoFailure -> find.text('Tentar de novo') findsOneWidget,
  find.text('R\$ 0,00') findsNothing; tocar repete a carga (contador == 2) */ });
testWidgets('resultado negativo aparece com sinal', (t) async { /* vendas 10, saídas 50 -> find.text('-R\$ 40,00') */ });
testWidgets('saída de categoria desativada aparece com o nome', (t) async { /* categoria ativa:false com saída no mês -> nome aparece em "Saídas por categoria" */ });
```

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_tab_test.dart`. Esperado: FAIL.

- [ ] **Step 3: Implementar a aba e registrá-la no `home_page.dart`.**

- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test test/financeiro_tab_test.dart` e depois `flutter test` (a suíte inteira, porque os testes de `home_page` e os visuais contam as abas). Esperado: PASS. Se um teste existente conta 5 abas, atualize para 6.

- [ ] **Step 5: Commit**
```bash
git add admin/lib/tabs/financeiro_tab.dart admin/lib/pages/home_page.dart admin/test
git commit -m "feat(financeiro): aba Financeiro com resultado do mês"
```

### Task 5: Lançar, editar e apagar saídas; gerenciar categorias

**Files:**
- Create: `admin/lib/financeiro/dialogo_saida.dart`
- Create: `admin/lib/financeiro/dialogo_categorias.dart`
- Modify: `admin/lib/tabs/financeiro_tab.dart`
- Test: `admin/test/financeiro_saida_test.dart`

**Interfaces:**
- Consumes:
  - da Tarefa 2: `Saida`, `CategoriaSaida`, `parseValorCentavos`, `fmtCentavos`;
  - da Tarefa 3: `FonteFinanceiro`.
- Produces:
  - `Future<Saida?> mostrarDialogoSaida(BuildContext context, {required List<CategoriaSaida> categorias, Saida? editar, required DateTime hoje})`
    - Devolve a saída preenchida, ou `null` se cancelado.
    - **Categorias:** o seletor mostra só as ativas. Ao editar uma saída de categoria desativada, ela aparece selecionada mesmo assim.
    - **Data:** o padrão é `hoje`. Data depois de `hoje + 365 dias` é recusada com "Data muito no futuro.".
    - **Valor:** inválido mostra "Valor inválido." e não fecha.
    - **Categoria:** ausente mostra "Escolha a categoria.".
  - `Future<void> mostrarDialogoCategorias(BuildContext context, FonteFinanceiro fonte)`
    - Lista todas as categorias, com as inativas marcadas "(desativada)".
    - Tem ações para criar, renomear e desativar ou reativar.
    - O erro do serviço aparece em SnackBar.
  - **Na aba:**
    - "Lançar saída" abre o diálogo e chama `inserirSaida`;
    - tocar numa saída abre o diálogo em modo edição e chama `alterarSaida`;
    - o ícone de lixeira pede a confirmação "Apagar esta saída?" e chama `apagarSaida`;
    - o `IconButton` "Categorias" abre o gerenciamento;
    - depois de gravar, recarrega o mês.

- [ ] **Step 1: Testes de widget que falham**

```dart
testWidgets('lançar saída válida chama inserirSaida com centavos', (t) async { /* escolhe "Matéria-prima", valor '1.234,56', descrição 'Leite' ->
  fonte.inseridas.single.valorCentavos == 123456, categoriaId certo, data == hoje */ });
testWidgets('valor inválido não grava', (t) async { /* '0' -> find.text('Valor inválido.'), fonte.inseridas isEmpty */ });
testWidgets('categoria desativada não aparece para lançar', (t) async { /* abre dropdown -> nome desativado findsNothing */ });
testWidgets('apagar pede confirmação', (t) async { /* lixeira -> 'Apagar esta saída?' -> Cancelar -> apagadas isEmpty; de novo -> Apagar -> apagadas == [id] */ });
testWidgets('editar mantém o id e chama alterarSaida', (t) async { /* toca na saída, muda valor para '50' -> alteradas.single.id == id, valorCentavos == 5000 */ });
testWidgets('categoria duplicada mostra a mensagem do serviço', (t) async { /* fonte.criarCategoria lança RepoFailure('Já existe uma categoria com esse nome.') -> SnackBar com o texto */ });
```

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_saida_test.dart`. Esperado: FAIL.

- [ ] **Step 3: Implementar.**

- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test`. Esperado: a suíte inteira passa.

- [ ] **Step 5: Commit**
```bash
git add admin/lib/financeiro admin/lib/tabs/financeiro_tab.dart admin/test/financeiro_saida_test.dart
git commit -m "feat(financeiro): lançar, editar e apagar saídas; categorias"
```

### Task 6: Roteiro de implantação

**Files:**
- Create: `docs/implantacao-fase-d.md`

**Interfaces:**
- Consumes: os nomes da migração (Tarefa 1) e os textos da tela (Tarefas 4 e 5).

- [ ] **Step 1: Escrever o roteiro.** Use o mesmo formato de `docs/implantacao-fase-b.md`, em português claro, sem ref do projeto e sem nomes de clientes.
  1. **Ordem:** aplicar o SQL (com OK do Kaiki) e depois instalar o Controle novo. O app dos celulares não muda.
  2. **Conferência depois do SQL:** existem 8 categorias, e um vendedor comum não vê a tabela `saidas`.
  3. **Teste no Controle:**
     - abrir Financeiro e conferir o mês atual;
     - voltar para um mês de 2025 e ver o aviso de histórico;
     - lançar uma saída de teste, editar, apagar;
     - criar uma categoria e desativá-la.
  4. **Mensagens que podem aparecer e o que fazer:** "Valor inválido.", "Escolha a categoria.", "Data muito no futuro.", "Já existe uma categoria com esse nome.", "Essa categoria tem saídas; desative em vez de apagar.".
  5. **Problemas comuns:** se a aba mostrar erro e "Tentar de novo", provavelmente o SQL ainda não foi aplicado.

- [ ] **Step 2: Commit**
```bash
git add docs/implantacao-fase-d.md
git commit -m "docs: roteiro de implantação da Fase D (financeiro)"
```
