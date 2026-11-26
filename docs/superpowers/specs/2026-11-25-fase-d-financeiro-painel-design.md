# Fase D (parte 1b): Painel do financeiro em abas

Data: 25/11/2026. Aprovado na conversa com o Kaiki.

Complementa `2026-11-25-fase-d-financeiro-design.md`. Todas as regras de conta daquele
documento continuam valendo:

- venda = pedido `finalizado`, contado no mês de `finalizado_em`, na hora local;
- saída conta no mês da sua `data`;
- somas em centavos.

## Por quê

O Kaiki testou a aba Financeiro em 25/11 e achou tudo "muito simples":

- **No visual:** só números e listas.
- **No conteúdo:** falta comparação, histórico e destaques.

O pedido dele foi "algo completo, mas que não fique poluído". Comparamos três layouts (painel
único, abas e comparativo) e ele escolheu **abas**:

- um **Resumo** enxuto, que responde em poucos segundos se o mês foi bom;
- os detalhes nas outras abas.

## Objetivos

A aba Financeiro passa a ter quatro abas internas: **Resumo**, **Vendas**, **Saídas** e
**Ano**.

- **Cabeçalho:** o seletor de mês (◀ mês ▶) e o botão Atualizar continuam no cabeçalho.
  - O mês escolhido vale para Resumo, Vendas e Saídas.
  - A aba Ano mostra os **12 meses que terminam no mês escolhido**.
  - O aviso "Até 23/11/2026, a data é a do pedido." continua aparecendo nos meses até
    nov/2026.

### Resumo

1. **Três indicadores:**
   - **Vendas:** R$, com "N pedidos · ticket médio R$ X" embaixo.
   - **Saídas:** R$.
   - **Resultado:** R$, com "margem X%" embaixo.
2. **Comparação em cada indicador:** variação em % contra o período de comparação (ver
   regras), com seta ▲/▼.
   - Venda ou resultado que sobe = melhora (verde); saída que sobe = piora (vermelho).
   - Se o período de comparação tem valor zero, a variação não aparece. Não se mostra
     "∞%".
3. **Curva do resultado nos 12 meses** que terminam no mês escolhido: um gráfico de linha,
   com o resultado negativo abaixo do zero.
4. **Destaques do mês**, em três cartões:
   - **Produto campeão:** nome, unidades e % das vendas em R$.
   - **Vendedor do mês:** nome e % das vendas.
   - **Maior gasto:** categoria e % das saídas.
   - Um cartão sem dado (mês sem venda ou sem saída) mostra "—".
5. **A receber:** pedidos prontos e não entregues, com quantidade e R$. Aparece **só no mês
   atual**, como hoje.

### Vendas

- **Por produto:** barras horizontais proporcionais com unidades e R$, do maior para o
  menor.
- **Por vendedor:** barras com R$ e % do total.
- **Melhores clientes:** os 10 maiores, com número de pedidos e R$.
  - **Agrupamento:** por `cliente_id`. Pedido sem `cliente_id` agrupa pelo nome exibido
    (nome fantasia, ou o nome).
  - **Nome exibido:** o nome do pedido mais recente daquele cliente.

### Saídas

- **Botões:** "Lançar saída" e "Categorias", com o mesmo comportamento de hoje.
- **Por categoria:** barras com R$ e % do total.
- **Lista do mês:** como hoje, com editar e apagar.

### Ano

- **Gráfico de barras:** vendas × saídas, com 12 barras duplas. As vendas são laranja e as
  saídas cinza, com legenda.
- **Tabela mês a mês:** mês, vendas, saídas, resultado, margem e pedidos, com uma linha de
  **total** no fim.

## Regras de comparação (decididas pelo Kaiki)

- **Mês já encerrado** (anterior ao mês atual): compara o **mês inteiro** com o **mês
  anterior inteiro**.
- **Mês atual:** compara com os **mesmos dias do mês anterior**, para não comparar um mês
  pela metade com um mês completo.
  - **Pedidos:** do dia 1 do mês anterior até o mesmo dia e hora de agora no mês anterior.
    Se o mês anterior for mais curto (31/03 → fevereiro), o limite fica no fim do mês
    anterior.
  - **Saídas:** as do mês anterior com o dia do mês ≤ o dia de hoje.
- **Meses futuros:** podem ter saídas lançadas, mas nunca vendas. Comparam o mês inteiro,
  como um mês encerrado.
- **Saídas no mês atual (decisão minha):** o cartão mostra o **total do mês**, igual à aba
  Saídas e ao Ano, inclusive saídas já lançadas com data futura dentro do mês.
  - **Variação:** é calculada com as saídas do mês atual até o dia de hoje contra as do mês
    anterior até o mesmo dia. Assim os dois lados ficam no mesmo recorte.
  - **Resultado:** a variação do resultado segue o mesmo recorte: vendas até agora menos
    saídas até hoje, contra o mesmo cálculo no mês anterior.
- **Variação do resultado com sinal (decisão minha):**
  - **Cálculo:** a % usa o valor absoluto do período de comparação como denominador:
    (atual − anterior) ÷ |anterior|. Assim, ir de −1000 para −500 aparece como melhora
    (▲, verde).
  - **Troca de sinal:** quando o resultado troca de sinal, a % não aparece. No lugar dela
    sai "virou positivo" (verde) ou "virou negativo" (vermelho).

## Definições

- **Ticket médio:** vendas ÷ número de pedidos. Sem pedidos, mostra "—".
- **Margem:** resultado ÷ vendas. Sem vendas, mostra "—".
- **% do total:** cada parte em centavos ÷ total em centavos, arredondado para inteiro na
  tela.
- **Campeão e vendedor do mês (decisão minha):** o produto campeão é o maior em **R$**, o
  mesmo critério da aba Vendas. O vendedor do mês também é o maior em R$.
- **Mês sem dado nenhum (decisão minha):** um mês sem pedido entregue e sem saída, como os
  anteriores a ago/2025, aparece como "—" na tabela do Ano. No gráfico ele fica sem barra,
  e na curva do resultado fica como um buraco, nunca como zero.
  - **Total do Ano:** soma só os meses com dado.
  - **Seletor de mês:** continua sem limite, como hoje.
- **Nomes vazios (decisão minha):** um cliente sem `cliente_id` e sem nome vira "Sem
  nome". Um vendedor sem nome e sem código vira "Sem vendedor".

## Fora do escopo

- **Forma de cobrança:** fica para a Fase C.
- **Exportar** para planilha ou PDF.
- **Filtros** por vendedor ou cliente.
- **Comparar com o mesmo mês do ano anterior.** Ficou fora para não poluir; a aba Ano já
  mostra os 12 meses.
- **Mudar o banco:** a fase não altera nenhuma tabela. Ela só lê pedidos e saídas, como
  hoje.

## Não pode acontecer

- **Telas mentirosas:** zeros ou "0%" quando a busca falhou. O erro continua com "Tentar de
  novo".
- **Poluição:** o Resumo não pode virar lista. Listas completas ficam nas abas Vendas e
  Saídas.
- **Estouro em tela estreita:** nada estoura em 360 px de largura.
- **Comparação injusta:** no mês atual, a comparação não pode ser contra o mês anterior
  inteiro.

## Caminho escolhido

| Caminho | Por que |
|---|---|
| A · painel único | Completo, mas fica longo e polui conforme crescem produtos e categorias. |
| **B · abas (escolhido)** | O Resumo fica enxuto e o detalhe fica a um clique, sem poluir. Aproveita as barras da A e o histórico da C. |
| C · comparativo | Bom para acompanhar, mas mostra pouco detalhe. |

## Desenho

**Dados:**
- **Busca:** uma carga por mês escolhido, cobrindo do 1º dia de (mês − 11) até o 1º dia de
  (mês + 1). Ela traz:
  - pedidos entregues;
  - saídas;
  - categorias;
  - os prontos, só no mês atual.
- **Interface:** reutiliza a `FonteFinanceiro` existente com o intervalo maior, sem mudar
  essa interface.
- **Volume:** são cerca de 30 pedidos por mês, então 12 meses ficam em poucas centenas de
  linhas. O serviço já pagina de 1000 em 1000.

**Contas:** funções puras e testáveis em `admin/lib/financeiro/`.
- **Resumo do mês:** reaproveita `resumirMes` para o mês escolhido e acrescenta os
  clientes.
- **Comparação:** uma função que, a partir de `agora` e do mês, calcula o período de
  comparação e as variações.
- **Série dos 12 meses:** uma função que devolve, para cada mês, vendas, saídas,
  resultado, margem e pedidos.

**Tela:**
- `FinanceiroTab` ganha um `TabBar` com as quatro abas, abaixo do cabeçalho.
- Cada aba é um widget próprio que recebe os dados já calculados e não faz busca.

**Gráficos:**
- Usa o pacote **`fl_chart`** (decisão minha), na versão compatível com o Flutter do
  projeto.
- As cores fixas são laranja da marca para vendas e resultado, e cinza neutro para saídas.
- O verde e o vermelho só aparecem nas setas de variação.

**Visual:** componentes e tokens de `packages/milkdim_ui`, como o resto do Controle.

## Deixado para quem constrói

- Espaçamentos, tamanho exato dos gráficos e da fonte dos indicadores.
- O formato dos rótulos dos eixos (por exemplo "R$ 8 mil").
- A tabela do Ano pode ganhar rolagem horizontal em tela estreita.
