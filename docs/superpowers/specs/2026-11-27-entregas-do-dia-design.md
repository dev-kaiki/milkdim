# Entregas do dia (app do vendedor)

## Por quê

Quando a fábrica marca um pedido como pronto, o vendedor precisa saber o que entregar, onde, e
avisar o cliente. Hoje isso fica misturado em "Meus pedidos". Funcionalidade 3 de 11, aprovada
pelo Kaiki em 27/11.

## O que faz

- **Tela inicial:** item "Entregas do dia", subtítulo "{N} prontos para entregar" (contagem
  local; enquanto não houver contagem, "Pedidos prontos para entregar").
- **Tela "Entregas do dia":**
  - **Ao abrir:** baixa do servidor os pedidos do vendedor (o mesmo `sincronizarPedidos` de
    "Meus pedidos"); sem internet, mostra o que está no aparelho, sem erro bloqueante.
  - **Quais pedidos:** status `pronto`, deste vendedor, sem os apagados no Controle. Não há data
    de entrega no sistema, então são **todos os prontos ainda não entregues**.
  - **Ordem:** agrupados por cidade (cidade vazia por último, como "Sem cidade"), e dentro da
    cidade pelo nome de exibição do cliente.
  - **Cartão:** cliente (nome fantasia, senão nome), endereço, cidade, "Pedido nº {n}", resumo
    dos itens, total, "Pronto desde dd/MM HH:mm".
  - **Ações:**
    - **Mapa:** Google Maps com endereço, cidade e CEP
      (`https://www.google.com/maps/search/?api=1&query=<texto codificado>`); desligado sem
      endereço.
    - **Avisar:** WhatsApp com "Olá! Aqui é o {vendedor} da MilkDim. Seu pedido nº {n} está
      pronto, passo aí hoje." (sem nome do vendedor: "Olá! Aqui é da MilkDim. …");
      desligado sem número válido.
    - **Registrar entrega:** o mesmo caminho do botão de "Meus pedidos" (tela de editar com a
      assinatura da entrega). Ao voltar, a lista recarrega.
  - **Lista vazia:** "Nenhum pedido pronto para entregar."
- Reaproveita `normalizarTelefone`, `linkWhatsApp` e `nomeExibicao` de clientes sumidos.

## Fora do escopo

- Ordenar a rota por distância; data marcada de entrega.
- Nada no servidor nem no Controle; sem migração do SQLite. Nenhum pedido é alterado por esta
  tela (só o fluxo de entrega que já existe altera).

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **Tela própria agrupada por cidade (escolhido)** | Ajuda a montar a rota; ações à mão. |
| Filtro "Prontos" em Meus pedidos | Barato, mas sem mapa nem aviso. |
| Rota otimizada | Precisa de serviço pago de mapas; fica para depois. |
