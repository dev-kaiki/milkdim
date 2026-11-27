# Relatório do mês em PDF (Controle)

## Por quê

O contador precisa dos números do mês, e hoje eles só aparecem na tela do Controle.
Funcionalidade 10 de 11; aprovada pelo Kaiki em 27/11 (as outras do bloco do Controle
esperam respostas do dono).

## O que faz

- **Botão "Relatório (PDF)"** no cabeçalho do Financeiro, ao lado da navegação de mês. Gera o
  relatório do mês que está na tela, com os dados já carregados (nenhuma busca nova). Fica
  desligado enquanto carrega ou com erro.
- **Saída:** a janela de impressão do Windows (`Printing.layoutPdf`), onde dá para imprimir ou
  salvar como PDF; nome sugerido `Relatorio_MilkDim_AAAA-MM.pdf`. Folha A4.
- **Conteúdo, nesta ordem:**
  1. Cabeçalho "MilkDim · Relatório de {mês} de {ano}" e "Gerado em dd/MM/aaaa HH:mm".
  2. Resumo: Vendas, Pedidos entregues, Saídas, Resultado e Margem, com a variação do mês
     anterior como a tela mostra (mesma regra e mesmos textos: "▲ N%", "▼ N%", "virou
     positivo/negativo"; sem variação quando não há).
  3. Vendas por vendedor (pedidos e R$) e por produto (unidades e R$).
  4. Saídas por categoria e a lista de saídas (data, categoria, descrição, valor), por data.
  5. Pedidos entregues: nº, data da entrega (dd/MM), cliente (nome fantasia, senão nome) e
     total, por data da entrega.
  6. A receber (só no mês atual): quantidade e R$.
  7. Nos meses até novembro de 2026, o aviso "Até 23/11/2026, a data é a do pedido."
- **Mês vazio:** sai assim mesmo, com zeros e "Nenhum lançamento." nas listas.
- Acentos com a fonte NotoSans do `milkdim_ui`, como a etiqueta.

## Fora do escopo

- E-mail direto ao contador; planilha (Excel/CSV).
- Nada no banco nem no app do vendedor. Nenhuma conta nova: o relatório usa o que a tela já
  calculou (`ResumoMes`, `ComparacaoMes`, saídas, pedidos entregues).

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **PDF pela janela de impressão (escolhido)** | Funciona em qualquer Windows, imprime ou salva. |
| Salvar arquivo direto numa pasta | Precisa de seletor de arquivo novo. |
| Planilha | Útil ao contador, mas outro formato; fica para depois. |
