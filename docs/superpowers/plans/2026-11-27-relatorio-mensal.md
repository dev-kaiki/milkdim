# Relatório do mês em PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um botão no Financeiro do Controle gera o relatório do mês em PDF (A4), pronto para imprimir ou salvar e mandar ao contador.

**Architecture:**
- **Modelo do relatório:** uma função pura monta as seções e as linhas a partir do que a tela já calculou. É ela que os testes cobrem.
- **PDF:** uma segunda função desenha esse modelo com o pacote `pdf`, usando a fonte NotoSans.
- **Tela:** o `FinanceiroTab` ganha o botão e chama `Printing.layoutPdf`.

**Tech Stack:** Flutter 3.41 (Windows), `pdf` e `printing` (já usados em `admin/lib/etiqueta/`), `intl`.

**Spec:** `docs/superpowers/specs/2026-11-27-relatorio-mensal-design.md`

## Global Constraints

- Só `admin/` muda. Nada no banco, no app do vendedor nem em `packages/`.
- **Sem conta nova:** o relatório usa `ResumoMes`, `ComparacaoMes`, as saídas, os nomes das categorias e os pedidos entregues do mês que o `FinanceiroTab` já carregou. A variação, a margem (`pctDe`) e os textos são os mesmos da tela.
- **Textos exatos:**
  - botão: "Relatório (PDF)";
  - título: "MilkDim · Relatório de {mês} de {ano}" (mês em minúsculas, como "novembro");
  - "Gerado em dd/MM/aaaa HH:mm";
  - seções: "Resumo", "Vendas por vendedor", "Vendas por produto", "Saídas por categoria", "Saídas do mês", "Pedidos entregues", "A receber";
  - lista vazia: "Nenhum lançamento.";
  - aviso histórico: "Até 23/11/2026, a data é a do pedido." (meses até novembro de 2026, inclusive);
  - nome do arquivo: `Relatorio_MilkDim_AAAA-MM.pdf`.
- **Valores:** em reais com `NumberFormat.currency(locale: 'pt_BR', symbol: 'R$')`, a partir dos centavos.
- **Fonte:** NotoSans do `milkdim_ui`, carregada como em `etiqueta_pdf.dart` (`_carregarFonte`), com Helvetica de reserva.

## Review Focus

1. **Mês sem vendas e sem saídas:** o PDF é gerado, os totais aparecem como R$ 0,00 e as listas mostram "Nenhum lançamento.". Teste na Tarefa 1.
2. **Muitas saídas ou muitos pedidos** (mais de uma página): o PDF quebra a página, usando `pw.MultiPage` e tabelas que podem continuar na página seguinte. Teste na Tarefa 1 com 150 pedidos.
3. **Pedido sem cliente ou sem `finalizadoEm`:** mostra "—", sem quebrar. Teste na Tarefa 1.
4. **Botão durante o carregamento ou com erro:** fica desligado. Teste na Tarefa 2.
5. **Mês atual × mês passado:** "A receber" só aparece no mês atual. Teste na Tarefa 1.

---

### Task 1: Modelo do relatório e PDF

**Files:**
- Create: `admin/lib/financeiro/relatorio_mes.dart`
- Test: `admin/test/relatorio_mes_test.dart`

**Interfaces:**
- Consumes: `ResumoMes`, `LinhaValor` (`resumo_financeiro.dart`); `ComparacaoMes`, `Variacao`, `pctDe` (`painel_financeiro.dart`); `Saida` (`modelos_financeiro.dart`); `Pedido` (`models/pedido.dart`).
- Produces:
  - `class RelatorioMes`, com `titulo`, `geradoEm` (texto), `resumo` (lista de `(rotulo, valor, variacao?)`), `porVendedor`, `porProduto`, `porCategoria`, `saidas`, `entregues`, `aReceber` (nulo fora do mês atual) e `aviso` (nulo depois de novembro de 2026). As linhas já vêm em texto pronto para o PDF.
  - `RelatorioMes montarRelatorio({required int ano, required int mes, required DateTime geradoEm, required bool mesAtual, required ResumoMes resumo, ComparacaoMes? comparacao, required List<Saida> saidas, required Map<int, String> nomesCategorias, required List<Pedido> entregues})`
  - `Future<Uint8List> pdfDoRelatorio(RelatorioMes r)`
  - `String nomeArquivoRelatorio(int ano, int mes)`
- [ ] **Step 1: Testes que falham.**
  - O título, o "Gerado em" e o nome do arquivo saem exatos (por exemplo, 2026 e 3 dão `Relatorio_MilkDim_2026-03.pdf`).
  - O resumo traz Vendas, Pedidos entregues, Saídas, Resultado e Margem, com os textos de variação da tela.
  - Saídas e entregues em ordem de data.
  - Pedido sem cliente ou sem `finalizadoEm` mostra "—".
  - Mês vazio: listas vazias, mas `pdfDoRelatorio` funciona.
  - "A receber" só aparece com `mesAtual`; o aviso só aparece até novembro de 2026.
  - `pdfDoRelatorio` com 150 pedidos devolve bytes que começam com `%PDF` e contêm mais de uma página (conte as ocorrências de `/Type /Page`, sem o `s`).
- [ ] **Step 2: Rodar e ver falhar.** `cd admin && flutter test test/relatorio_mes_test.dart`
- [ ] **Step 3: Implementar.** Use `pw.MultiPage` com tabelas (`pw.TableHelper.fromTextArray` ou `pw.Table`). Carregue a fonte NotoSans como em `etiqueta_pdf.dart`. Se as funções de fonte de lá forem privadas, torne-as públicas, sem copiar o código.
- [ ] **Step 4: Rodar e ver passar.** Depois, `flutter test` e `flutter analyze` em `admin/`.
- [ ] **Step 5: Commit.** `feat(relatorio): modelo e PDF do relatório do mês`

---

### Task 2: Botão "Relatório (PDF)" no Financeiro

**Files:**
- Modify: `admin/lib/tabs/financeiro_tab.dart`
- Test: `admin/test/financeiro_relatorio_test.dart`, ou o arquivo de testes do `FinanceiroTab` que já existir

**Interfaces:**
- Consumes: tudo o que a Tarefa 1 produz.
- Produces: `FinanceiroTab({..., Future<void> Function(Uint8List pdf, String nome)? imprimirRelatorio})`. O padrão é `Printing.layoutPdf(name: nome, format: PdfPageFormat.a4, onLayout: (_) async => pdf)`.
- [ ] **Step 1: Testes que falham**, com a `fonte` falsa que os testes do `FinanceiroTab` já usam.
  - O botão "Relatório (PDF)" fica desligado enquanto carrega e com erro, e ligado depois de carregar.
  - Tocar no botão chama `imprimirRelatorio` com bytes `%PDF` e o nome `Relatorio_MilkDim_AAAA-MM.pdf` do mês na tela.
  - Uma falha ao imprimir mostra o aviso "Não foi possível gerar o relatório." e não quebra a tela.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar.**
  - Guarde no estado a lista `entregues` do mês, que hoje é variável local de `_carregar`.
  - Ponha o botão (um `OutlinedButton.icon` com `Icons.picture_as_pdf_outlined`) no `_cabecalho`, no grupo de ações.
  - Use uma trava para impedir dois cliques seguidos.
- [ ] **Step 4: Rodar e ver passar.** Em `admin/`, `flutter test`, `flutter analyze` e as capturas visuais, se houver alguma do Financeiro.
- [ ] **Step 5: Commit.** `feat(relatorio): botão Relatório (PDF) no Financeiro`
