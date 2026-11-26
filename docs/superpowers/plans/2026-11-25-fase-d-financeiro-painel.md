# Painel do financeiro em abas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganizar a aba Financeiro do Controle em quatro abas (Resumo, Vendas, Saídas e Ano), com comparação, histórico de 12 meses, destaques e gráficos.

**Architecture:**
- **Contas:** ficam em funções puras novas, em `admin/lib/financeiro/painel_financeiro.dart`.
- **Carga:** a tela busca 12 meses de uma vez pela `FonteFinanceiro`, que não muda. O mês escolhido é filtrado em memória.
- **Telas:** cada aba é um widget próprio que só recebe dados.
- **Gráficos:** usam `fl_chart`.

**Tech Stack:** Flutter 3.41 / Dart 3.11 (Windows), `fl_chart`, `intl` e `milkdim_ui`.

**Spec:** `docs/superpowers/specs/2026-11-25-fase-d-financeiro-painel-design.md`, que complementa `docs/superpowers/specs/2026-11-25-fase-d-financeiro-design.md`.

## Global Constraints

- **Regras herdadas:**
  - venda = pedido com `status = 'finalizado'`, no mês de `finalizado_em` em hora local;
  - saída conta no mês da `data`;
  - somas em centavos inteiros, com `centavos()`;
  - erro de carga mostra "Tentar de novo", nunca zeros.
- **Aviso de histórico:** "Até 23/11/2026, a data é a do pedido." continua aparecendo nos meses até nov/2026.
- **Banco e celulares:** a fase não mexe no banco nem no app dos celulares. A `FonteFinanceiro` não muda de interface.
- **Abas e seletor:** as abas se chamam exatamente "Resumo", "Vendas", "Saídas" e "Ano". O seletor de mês e o botão Atualizar continuam no cabeçalho, acima das abas.
- **Período de comparação:**
  - **mês encerrado ou futuro:** o mês anterior inteiro;
  - **mês atual (pedidos):** do dia 1 do mês anterior até `inicioMesAnterior + (agora − inicioMesAtual)`, limitado ao início do mês atual;
  - **mês atual (saídas):** só os dias ≤ `agora.day`, nos dois meses.
- **Cartão Saídas:** mostra sempre o total do mês inteiro. Só a variação usa o recorte.
- **Variação:** `(atual − anterior) × 100 ÷ |anterior|`, arredondada.
  - Com anterior = 0, a variação não aparece.
  - No resultado, quando o sinal troca, aparece "virou positivo" (melhora) ou "virou negativo" (piora), sem %.
  - Vendas e resultado que sobem = melhora (verde). Saída que sobe = piora (vermelho). Igual = neutro (sem cor).
- **Ticket médio:** vendas ÷ pedidos. Sem pedidos, mostra "—".
- **Margem:** resultado ÷ vendas, em %. Sem vendas, mostra "—".
- **% do total:** inteiro arredondado.
- **Destaques:**
  - produto campeão = o maior em R$ (nome, unidades, % das vendas);
  - vendedor do mês = o maior em R$ (% das vendas);
  - maior gasto = a maior categoria (% das saídas);
  - sem dado, o cartão mostra "—".
- **Melhores clientes:**
  - os 10 maiores em R$, agrupados por `clienteId`;
  - sem `clienteId`, agrupa pelo nome exibido (fantasia, senão nome);
  - o rótulo é o nome do pedido mais recente;
  - vazio vira "Sem nome";
  - a quantidade é o número de pedidos.
- **Vendedor vazio:** vendedor sem nome e sem código vira "Sem vendedor". Isso também corrige `resumirMes`.
- **Ano:**
  - os 12 meses que terminam no mês escolhido, do mais antigo para o mais novo;
  - mês sem pedido entregue e sem saída = sem dado: aparece como "—" na tabela, sem barra no gráfico e como buraco na curva;
  - o total soma só os meses com dado.
- **A receber:** só no mês atual, como hoje.
- **Cores:** vendas e resultado em laranja (a cor primária de `milkdim_ui`), saídas em cinza neutro. O verde e o vermelho só aparecem nas setas e nos textos de variação.
- **Tela estreita:** nada estoura em 360 px de largura.
- **Visual:** componentes e tokens de `packages/milkdim_ui`.

## Review Focus

1. **Virada de mês no mês atual:**
   - em 31/03, o período de comparação termina no fim de fevereiro;
   - em 01/12 à 00:10, o mês anterior conta de 01/11 00:00 até 01/11 00:10.
   - Testado na Tarefa 1.
2. **Resultado negativo ou com troca de sinal:**
   - de −1000 para −500 = ▲ 50%, melhora;
   - de 500 para −200 = "virou negativo";
   - de 0 para qualquer valor = sem variação.
   - Testado na Tarefa 1.
3. **Janela de 12 meses que cruza o ano e começa antes de ago/2025:** os meses vazios ficam "sem dado", não zero. Testado nas Tarefas 1 e 3.
4. **Troca de aba depois de um erro de carga:** todas as abas mostram o erro e "Tentar de novo", nunca zeros. Testado na Tarefa 2.
5. **360 px de largura em cada aba**, incluindo a tabela do Ano: sem exceção de overflow. Testado nas Tarefas 2 e 3.

---

### Task 1: Contas do painel (Dart puro)

**Files:**
- Create: `admin/lib/financeiro/painel_financeiro.dart`
- Modify: `admin/lib/financeiro/resumo_financeiro.dart` (rótulo "Sem vendedor")
- Test: `admin/test/financeiro_painel_test.dart`

**Interfaces:**
- Consumes:
  - `Pedido` (`status`, `total`, `finalizadoEm`, `clienteId`, `clienteNome`, `clienteNomeFantasia`);
  - `Saida` (`data`, `valorCentavos`);
  - `centavos`, `LinhaValor`, `resumirMes`.
- Produces:
  - `({DateTime inicio, DateTime fim}) periodoComparacaoPedidos({required int ano, required int mes, required DateTime agora})`
  - `int? diaLimiteSaidas({required int ano, required int mes, required DateTime agora})`: devolve `agora.day` no mês atual e `null` nos outros.
  - `class Variacao { final int? pct; final String? texto; final int sentido; }`
    - `sentido`: 1 = melhora, −1 = piora, 0 = neutro.
    - `texto` só existe na troca de sinal.
  - `Variacao? calcularVariacao(int atual, int anterior, {bool maiorEhMelhor = true, bool trocaDeSinal = false})`
  - `class ComparacaoMes { final Variacao? vendas; final Variacao? saidas; final Variacao? resultado; }`
  - `ComparacaoMes compararMes({required int ano, required int mes, required DateTime agora, required List<Pedido> entregues, required List<Saida> saidas})`
    - As listas cobrem pelo menos o mês e o mês anterior. A função filtra sozinha.
  - `class MesSerie { final int ano; final int mes; final int vendasCentavos; final int saidasCentavos; final int pedidos; bool get temDado; int get resultadoCentavos; int? get margemPct; }`
  - `List<MesSerie> serieDozeMeses({required int ano, required int mes, required List<Pedido> entregues, required List<Saida> saidas})`: devolve 12 itens, do mais antigo para o mais novo.
  - `List<LinhaValor> melhoresClientes(List<Pedido> entregues, {int limite = 10})`
  - `int? pctDe(int parte, int total)`: devolve `null` com total 0.
- **Filtros:** em todas as funções, pedido conta só com `status == 'finalizado'` e `finalizadoEm != null`, usando `finalizadoEm!.toLocal()`.

- [ ] **Step 1: Testes que falham.** Os nomes e as asserções são obrigatórios. Use `DateTime` local nos dados.

```dart
test('período de comparação: mês encerrado = mês anterior inteiro', () {
  final p = periodoComparacaoPedidos(ano: 2026, mes: 10, agora: DateTime(2026, 11, 25, 10));
  expect(p.inicio, DateTime(2026, 9, 1)); expect(p.fim, DateTime(2026, 10, 1));
});
test('período de comparação: mês atual = mesmos dias do mês anterior', () {
  final p = periodoComparacaoPedidos(ano: 2026, mes: 11, agora: DateTime(2026, 11, 25, 10));
  expect(p.inicio, DateTime(2026, 10, 1)); expect(p.fim, DateTime(2026, 10, 25, 10));
});
test('período de comparação: 31/03 para no fim de fevereiro', () {
  final p = periodoComparacaoPedidos(ano: 2027, mes: 3, agora: DateTime(2027, 3, 31, 12));
  expect(p.fim, DateTime(2027, 3, 1));
});
test('período de comparação: virada de ano no mês atual', () {
  final p = periodoComparacaoPedidos(ano: 2027, mes: 1, agora: DateTime(2027, 1, 1, 0, 10));
  expect(p.inicio, DateTime(2026, 12, 1)); expect(p.fim, DateTime(2026, 12, 1, 0, 10));
});
test('diaLimiteSaidas só no mês atual', () {
  expect(diaLimiteSaidas(ano: 2026, mes: 11, agora: DateTime(2026, 11, 25)), 25);
  expect(diaLimiteSaidas(ano: 2026, mes: 10, agora: DateTime(2026, 11, 25)), isNull);
});
test('calcularVariacao', () {
  expect(calcularVariacao(110, 100)!.pct, 10); expect(calcularVariacao(110, 100)!.sentido, 1);
  expect(calcularVariacao(110, 100, maiorEhMelhor: false)!.sentido, -1);
  expect(calcularVariacao(100, 100)!.sentido, 0);
  expect(calcularVariacao(50, 0), isNull);
  final neg = calcularVariacao(-500, -1000, trocaDeSinal: true)!;
  expect(neg.pct, 50); expect(neg.sentido, 1);
  final virou = calcularVariacao(-200, 500, trocaDeSinal: true)!;
  expect(virou.pct, isNull); expect(virou.texto, 'virou negativo'); expect(virou.sentido, -1);
  expect(calcularVariacao(300, -100, trocaDeSinal: true)!.texto, 'virou positivo');
});
test('compararMes no mês atual usa o recorte nos dois lados', () { /* agora 25/11/2026 10:00.
  Entregues: out/10 R$100, out/28 R$900 (fora do recorte), nov/05 R$150. Saídas: out/20 R$40, out/27 R$500 (fora), nov/10 R$60, nov/30 R$999 (data futura, fora do recorte).
  Esperado: vendas.pct == 50 (150 vs 100); saidas.pct == 50 (60 vs 40), sentido -1;
  resultado: atual 150-60=90 vs anterior 100-40=60 -> pct 50, sentido 1. */ });
test('compararMes em mês encerrado usa os meses inteiros', () { /* mes 10 com agora em novembro: inclui out/28 e set inteiro */ });
test('serieDozeMeses cruza o ano e marca meses sem dado', () { /* ano 2025 mes 9 -> meses out/2024..set/2025;
  pedidos só em ago e set/2025 -> só os dois últimos temDado; os 10 primeiros temDado == false;
  margemPct de mês com vendas 1000 e saídas 250 == 75; margemPct de mês sem vendas == null */ });
test('melhoresClientes agrupa por id, usa o nome mais recente e limita a 10', () { /* cliente 7 com nome antigo 'A' e recente 'A Ltda' -> rótulo 'A Ltda', quantidade 2;
  pedido sem id e sem nome -> 'Sem nome'; 12 clientes -> 10 itens, ordenados por R$ desc */ });
test('pctDe', () { expect(pctDe(1, 3), 33); expect(pctDe(5, 0), isNull); });
test('resumirMes: vendedor sem nome e sem código vira Sem vendedor', () { /* ... */ });
```

O corpo dos testes marcados com `/* */` é escrito por quem implementa, com os valores do comentário.

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_painel_test.dart`. Esperado: FAIL na compilação.
- [ ] **Step 3: Implementar.** As funções seguem as regras das Global Constraints. Use `DateTime(ano, mes + k, 1)` para andar de mês em mês.
- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test test/financeiro_painel_test.dart test/financeiro_resumo_test.dart`. Esperado: PASS.
- [ ] **Step 5: Commit**
```bash
git add admin/lib/financeiro admin/test/financeiro_painel_test.dart
git commit -m "feat(financeiro): contas do painel (comparação, 12 meses, clientes)"
```

### Task 2: Abas Resumo, Vendas, Saídas e Ano (sem gráficos)

**Files:**
- Create:
  - `admin/lib/financeiro/abas/aba_resumo.dart`
  - `admin/lib/financeiro/abas/aba_vendas.dart`
  - `admin/lib/financeiro/abas/aba_saidas.dart`
  - `admin/lib/financeiro/abas/aba_ano.dart`
  - `admin/lib/financeiro/abas/barras_horizontais.dart`
- Modify: `admin/lib/tabs/financeiro_tab.dart` (carga de 12 meses, `TabBar`/`TabBarView`, os quadros atuais vão para as abas)
- Test:
  - `admin/test/financeiro_tab_test.dart` e `admin/test/financeiro_saida_test.dart`: ajustar para tocar na aba certa antes de procurar textos;
  - `admin/test/financeiro_abas_test.dart`: novo.

**Interfaces:**
- Consumes:
  - da Tarefa 1: tudo;
  - `resumirMes`, `ResumoMes`, `LinhaValor`, `fmtCentavos`, `FonteFinanceiro`.
- Produces:
  - `BarrasHorizontais({required List<LinhaValor> linhas, required Color cor, String Function(LinhaValor)? detalhe, int? totalCentavos})`
    - cada barra tem largura proporcional ao maior valor;
    - mostra o rótulo, o detalhe opcional (por exemplo "201 un"), o R$ e, se `totalCentavos` vier, o "N%".
  - `AbaResumo({required ResumoMes resumo, required ComparacaoMes comparacao, required List<MesSerie> serie, required bool mesAtual})`
    - Nesta tarefa, o lugar da curva fica com um `SizedBox` reservado (key `ValueKey('curva-resultado')`). A Tarefa 3 coloca o gráfico.
  - `AbaVendas({required ResumoMes resumo, required List<LinhaValor> clientes})`
  - `AbaSaidas({required ResumoMes resumo, required List<Saida> saidasDoMes, required Map<int, String> nomesCategorias, required VoidCallback onLancar, required VoidCallback onCategorias, required void Function(Saida) onEditar, required void Function(Saida) onApagar})`
  - `AbaAno({required List<MesSerie> serie})`
    - Nesta tarefa, o lugar do gráfico fica reservado (key `ValueKey('grafico-ano')`).
    - A tabela tem as colunas "Mês", "Vendas", "Saídas", "Resultado", "Margem", "Pedidos" e a linha "Total".
- **Carga e cabeçalho em `FinanceiroTab`:**
  - **intervalo da carga:** de `DateTime(ano, mes - 11, 1)` até `DateTime(ano, mes + 1, 1)`, usando `pedidosEntregues`, `saidasEntre`, `categorias` e `pedidosProntos` (este só no mês atual);
  - **mês escolhido:** filtrado em memória para `resumirMes` e para a lista de saídas;
  - **mudanças no cabeçalho:** os botões "Lançar saída" e "Categorias" saem do cabeçalho e vão para a AbaSaidas. O cabeçalho fica com ◀ mês ▶ e Atualizar;
  - **mantido:** o aviso de histórico, o recarregar ao abrir, o `_geracao` e os SnackBars.

- [ ] **Step 1: Testes que falham** em `financeiro_abas_test.dart`, com a fonte falsa dos testes atuais.

```dart
testWidgets('mostra as quatro abas e abre no Resumo', (t) async { /* find.text('Resumo'), 'Vendas', 'Saídas', 'Ano' findsOneWidget; 'Resultado do mês' visível */ });
testWidgets('Resumo mostra variação e ticket médio', (t) async { /* agora 25/11/2026; out/10 R$100, nov/05 R$150 -> find.textContaining('50%') ; find.textContaining('ticket médio R\$ 150,00') */ });
testWidgets('Resumo: destaques com — quando não há saídas', (t) async { /* sem saídas -> cartão 'Maior gasto' mostra '—' */ });
testWidgets('Vendas mostra melhores clientes', (t) async { /* toca 'Vendas' -> 'Melhores clientes' e o nome do cliente */ });
testWidgets('Saídas tem Lançar saída e Categorias', (t) async { /* toca 'Saídas' -> find.text('Lançar saída'), find.byTooltip('Categorias') */ });
testWidgets('Ano mostra 12 meses, — nos meses sem dado e Total', (t) async { /* mês escolhido set/2025 com dados só em ago e set -> 10 linhas com '—'; find.text('Total') */ });
testWidgets('erro de carga: todas as abas mostram Tentar de novo', (t) async { /* fonte lança -> 'Tentar de novo' e nenhum 'R\$ 0,00' */ });
testWidgets('360 px: nenhuma aba estoura', (t) async { /* largura 360; para cada aba: tocar e expect(t.takeException(), isNull) */ });
testWidgets('carga busca 12 meses', (t) async { /* fonte.inicios.last == DateTime(2025, 12, 1) para nov/2026 */ });
```

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_abas_test.dart`. Esperado: FAIL.
- [ ] **Step 3: Implementar e ajustar os testes antigos** (`financeiro_tab_test.dart`, `financeiro_saida_test.dart`) à navegação por abas, sem enfraquecer as asserções.
- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test test/financeiro_abas_test.dart test/financeiro_tab_test.dart test/financeiro_saida_test.dart` e depois `flutter test`. Esperado: tudo PASS.
- [ ] **Step 5: Commit**
```bash
git add admin/lib admin/test
git commit -m "feat(financeiro): painel em abas Resumo, Vendas, Saídas e Ano"
```

### Task 3: Gráficos (curva do resultado e vendas × saídas)

**Files:**
- Modify: `admin/pubspec.yaml` (com `flutter pub add fl_chart`, na versão que resolver com o SDK do projeto)
- Create: `admin/lib/financeiro/abas/graficos_financeiro.dart`
- Modify: `admin/lib/financeiro/abas/aba_resumo.dart` e `admin/lib/financeiro/abas/aba_ano.dart` (trocar os espaços reservados)
- Test: `admin/test/financeiro_graficos_test.dart`

**Interfaces:**
- Consumes: `MesSerie` (Tarefa 1) e as keys reservadas da Tarefa 2.
- Produces:
  - `CurvaResultado({required List<MesSerie> serie})`
    - `LineChart`;
    - mês sem dado vira `FlSpot.nullSpot`, ou seja, buraco;
    - linha zero visível;
    - rótulos dos meses com 3 letras ("Dez", "Jan" …).
  - `BarrasVendasSaidas({required List<MesSerie> serie})`
    - `BarChart` com duas barras por mês: vendas em laranja, saídas em cinza;
    - mês sem dado fica sem barras;
    - legenda acima com "Vendas" e "Saídas".
  - `List<FlSpot> pontosResultado(List<MesSerie> serie)`: pública, para teste. O x é o índice e o y o resultado em reais.

- [ ] **Step 1: Testes que falham**

```dart
test('pontosResultado: mês sem dado vira nullSpot', () { /* serie com 12 meses, só os 2 últimos com dado -> 10 nullSpot, últimos com y == resultado/100 */ });
testWidgets('CurvaResultado e BarrasVendasSaidas renderizam sem exceção', (t) async { /* pump em 360 e em 1000 px; takeException null; find.text('Vendas') e find.text('Saídas') na legenda */ });
```

- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/financeiro_graficos_test.dart`. Esperado: FAIL.
- [ ] **Step 3: Implementar.** Adicione a dependência, crie os dois gráficos e coloque cada um no seu espaço reservado. As keys `curva-resultado` e `grafico-ano` continuam no widget que envolve o gráfico.
- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test`. Esperado: a suíte inteira passa.
- [ ] **Step 5: Commit**
```bash
git add admin/pubspec.yaml admin/pubspec.lock admin/lib admin/test
git commit -m "feat(financeiro): gráficos do resultado e de vendas x saídas"
```

### Task 4: Roteiro de implantação

**Files:**
- Modify: `docs/implantacao-fase-d.md`

- [ ] **Step 1: Atualizar o roteiro**, conferindo cada texto da tela no código:
  - a seção de teste passa a percorrer as quatro abas;
  - explica a comparação ("no mês atual, compara com os mesmos dias do mês anterior");
  - explica o "—" nos meses sem dado;
  - "Lançar saída" e "Categorias" agora ficam na aba Saídas;
  - o build passa a ser `MilkDim_Controle_Windows_<data>_faseD_painel`.
- [ ] **Step 2: Commit**
```bash
git add docs/implantacao-fase-d.md
git commit -m "docs: roteiro da Fase D com o painel em abas"
```
