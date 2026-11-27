# Comprovante para o cliente (app do vendedor)

## Por quê

O comprovante com as duas assinaturas (pedido e entrega) já existe como "PDF" em Meus pedidos,
mas o vendedor precisa lembrar de mandar. A hora certa é logo depois de registrar a entrega.
Funcionalidade 4 de 11; caminho A aprovado pelo Kaiki em 27/11.

## O que faz

- **Depois de registrar a entrega** (botão "Registrar entrega", de qualquer lugar: Meus pedidos,
  Entregas do dia ou leitura da etiqueta), se a gravação deu certo, aparece:
  "Entrega registrada. Enviar comprovante ao cliente?" com "Enviar comprovante" e "Agora não".
  - "Enviar comprovante": relê o pedido gravado no aparelho, gera o PDF com as duas assinaturas e
    abre o compartilhar do Android com o texto
    "Comprovante do pedido nº {n} – MilkDim. Obrigado pela preferência!". O vendedor escolhe o
    WhatsApp e o cliente. Depois a tela fecha como hoje.
  - "Agora não": a tela fecha como hoje.
  - Falha ao gerar ou compartilhar: aviso "Não foi possível gerar o comprovante." e a tela fecha
    mesmo assim (a entrega já está gravada).
- **Meus pedidos:** nos pedidos **entregues**, o botão "PDF" vira "Comprovante" e usa o mesmo
  texto. Nos cancelados continua "PDF" como hoje.
- Uma função só gera e compartilha o comprovante; Meus pedidos e a tela de entrega usam a mesma.

## Fora do escopo

- Mandar o PDF direto para o número do cliente sem passar pelo compartilhar (o Android não
  permite anexar arquivo por link).
- Texto direto na conversa (caminho B).
- Nada no servidor, no Controle nem no esquema do SQLite. O fluxo de entrega e o que ele grava
  não mudam: o comprovante só lê.

## Caminhos considerados

| Caminho | Troca |
|---|---|
| **A · PDF logo após a entrega (escolhido)** | Vale como prova (tem assinatura); um passo a mais no compartilhar. |
| B · texto direto na conversa | Menos toques, sem assinatura. |
