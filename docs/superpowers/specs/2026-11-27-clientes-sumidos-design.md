# Clientes sumidos (app do vendedor)

## Por quê

Cliente que para de comprar some sem ninguém perceber. O vendedor precisa ver quem não
compra há algum tempo e chamar na hora (WhatsApp ou ligação). É a funcionalidade 2 de 11,
aprovada pelo Kaiki em 27/11.

## O que faz

- **Tela inicial:** um item novo, "Clientes sumidos", com a contagem de clientes (prazo de
  30 dias) no subtítulo.
- **Tela "Clientes sumidos":**
  - **Prazo:** escolhas de 30, 60 ou 90 dias no alto; começa em 30.
  - **Quem aparece:** cliente com pelo menos um pedido **deste vendedor** no aparelho (sem
    contar cancelados nem apagados no Controle) cujo último pedido tem `≥ prazo` dias.
  - **Ordem:** do sumiço mais recente para o mais antigo (menos dias primeiro).
  - **Cada linha:** nome (nome fantasia quando houver), cidade, "Última compra dd/MM · há N
    dias", "N pedidos".
  - **Ações:**
    - **WhatsApp:** abre a conversa com a mensagem pronta (o vendedor pode editar antes de
      enviar): "Olá! Aqui é o {nome do vendedor} da MilkDim. Faz um tempinho que a gente não
      se fala, posso passar aí essa semana?"
    - **Ligar:** abre o discador com o telefone.
    - **Novo pedido:** abre a tela de pedido com o cliente já escolhido (o quadro do repetir
      pedido aparece junto).
  - **Sem número:** botão de WhatsApp desligado quando o cliente não tem WhatsApp nem
    telefone válido; "Ligar" desligado sem telefone nem WhatsApp válido.
  - **Lista vazia:** "Nenhum cliente sumido há {N} dias ou mais."
- **Telefone:** só os dígitos. Com 10 ou 11 dígitos ganha o 55 na frente; com 12 ou 13 e
  começando com 55 fica como está; qualquer outro tamanho é inválido. WhatsApp usa
  `https://wa.me/<número>?text=<mensagem>`; ligar usa `tel:<número>`.
- **Funciona sem internet** (só o WhatsApp precisa).

## Fora do escopo

- Esconder um cliente da lista.
- Clientes que compram de outro vendedor (os pedidos não estão no celular).
- Nada no servidor nem no Controle; sem migração do SQLite.

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **Tela própria com prazo 30/60/90 (escolhido)** | Clara e rápida de usar no campo. |
| Selo "sumido" na busca de clientes | Barato, mas o vendedor só vê quando já vai fazer pedido. |
| Aviso automático (notificação) | Precisa de servidor de notificações; fica para depois. |

## Deixado para quem constrói

- Pacote `url_launcher` no app (o Controle já usa) e as `<queries>` do Android para `https`
  e `tel`.
- Funções puras testáveis para a lista e para os links.
- Parâmetro novo na `PedidoPage` para abrir com o cliente escolhido.
