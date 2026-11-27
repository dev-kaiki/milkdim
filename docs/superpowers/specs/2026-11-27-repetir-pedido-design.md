# Repetir pedido (app do vendedor)

## Por quê

O vendedor monta cada pedido do zero, produto por produto. Os clientes compram com
frequência, mas **os pedidos variam bastante** de uma vez para outra (palavra do Kaiki), então
não basta repetir o último: o vendedor escolhe de qual pedido anterior partir e ajusta.

É a primeira de 11 funcionalidades novas; esta não depende de nenhuma resposta do cliente.

## Objetivos

- **A · na tela de novo pedido:** depois de escolher o cliente, aparece o quadro "Partir de
  um pedido anterior" com os **5 últimos pedidos** dele. "Usar" preenche as quantidades.
- **B · na lista de Pedidos:** cada pedido com cliente ganha a ação **"Repetir"**, que abre um
  novo pedido com o cliente já escolhido e as quantidades preenchidas.
- A e B usam a mesma função de preenchimento.

```
Partir de um pedido anterior
  12/11  ·  R$ 480,00  ·  Pote 160g ×40, Copo ×20 …   [Usar]
  05/11  ·  R$ 210,00  ·  Pote 160g ×20 …             [Usar]
```

## Regras

- **Quais pedidos:** os do próprio aparelho (o celular já baixa os pedidos do vendedor), do
  mesmo `cliente_id`, de qualquer status **menos cancelado**, do mais novo para o mais velho.
  Funciona sem internet.
- **Como casa o produto:** o pedido guarda os itens só pelo **nome** (`nome`, `preco`,
  `quantidade`), sem id. O casamento é pelo nome sem espaços nas pontas e sem diferença de
  maiúsculas.
- **Preço:** sempre o **preço de hoje** do produto, nunca o do pedido antigo.
- **Produto que não existe mais** (desativado ou renomeado): fica fora, e o vendedor vê um
  aviso com os nomes: "Ficaram de fora (não estão mais à venda): …".
- **Tela já com quantidades:** "Usar" pergunta antes "Trocar as quantidades da tela pelas
  deste pedido?". Produtos que não estão no pedido escolhido ficam com 0.
- **Assinaturas:** nada é copiado. O pedido novo segue o fluxo normal (o cliente assina no
  pedido e na entrega, como na Fase A).
- **B com cliente apagado:** se o cliente do pedido não está mais na lista de clientes do
  aparelho, "Repetir" avisa "Este cliente não está mais cadastrado" e não abre a tela.
- **Quadro vazio:** cliente sem pedido anterior não mostra o quadro.

## Fora do escopo

- Pedidos de outros vendedores para o mesmo cliente (não estão no celular).
- Pedido "sugerido" por média (descartado: pedidos variam demais e a média confunde).
- A tela de **editar** pedido não muda.
- Nada no banco nem no Controle; não há migração.

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **A · quadro na tela de novo pedido (escolhido)** | Escolhe onde o pedido já está sendo feito. |
| **B · "Repetir" na lista de Pedidos (escolhido junto)** | Barato, usa a mesma função; bom quando o vendedor parte da lista. |
| C · pedido sugerido pela média | Descartado: com pedidos variados, a média não parece nenhum pedido real. |

## Deixado para quem constrói

- **Função pura e testável** que recebe os itens do pedido antigo e os produtos de hoje e
  devolve as quantidades por produto e a lista de nomes que ficaram de fora.
- **Texto do resumo:** os 2 ou 3 primeiros itens e "…".
- **Formato:** o quadro usa os componentes de `milkdim_ui`.
- **Abrir pré-preenchido:** um parâmetro novo na `PedidoPage` (por exemplo, o pedido de
  partida) para a ação B.
- **Testes:**
  - da função pura;
  - do quadro (aparece, "Usar", confirmação);
  - da ação "Repetir".
