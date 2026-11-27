# Minhas vendas (app do vendedor)

## Por quê

O vendedor não tem como ver quanto vendeu no mês; só a fábrica vê no Controle. Ver o próprio
resultado motiva e ajuda a planejar. Funcionalidade 5 de 11, aprovada pelo Kaiki em 27/11.

## O que faz

- **Regra de venda (igual ao financeiro do Controle):** pedido com status `finalizado`, contado
  no mês de `finalizado_em` em hora local. Só pedidos deste vendedor, sem os apagados no
  Controle. Dados do aparelho; funciona sem internet.
- **Tela inicial:** item "Minhas vendas", subtítulo "R$ 3.450,00 em novembro" (mês atual,
  nome do mês em minúsculas); sem dado ainda, "Quanto você vendeu no mês".
- **Tela "Minhas vendas":**
  - **Mês:** "‹ novembro de 2026 ›", navegável; não avança além do mês atual.
  - **Três números:** "Vendido" (R$), "Pedidos entregues" e "Ticket médio" (R$; "—" sem pedido).
  - **Comparação com o mês anterior** em cada número: "▲ 12%" ou "▼ 5%" (arredondado, sem
    casas); sem comparação quando o mês anterior é zero; "= 0%" quando igual.
  - **A entregar** (só no mês atual): soma em R$ e quantidade dos pedidos deste vendedor com
    status `salvo` ou `pronto`, sem apagados.
  - **Por produto:** nome, unidades e R$, do maior R$ para o menor (itens do pedido somados por
    nome, como no repetir pedido).
  - **Melhores clientes:** os 5 com mais R$ no mês, com o número de pedidos.
  - **Mês sem venda:** "Nenhuma venda entregue em {mês}."

## Fora do escopo

- Comissão (falta saber a regra; entra depois como uma linha).
- Nada no servidor, no Controle nem no esquema do SQLite. A tela só lê.

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **Tela própria com mês navegável (escolhido)** | Clara, offline, mesma regra do Controle. |
| Só um número na tela inicial | Barato, mas sem detalhe nem comparação. |
| Ler do servidor | Pega pedidos de outros aparelhos, mas não funciona sem internet. |
