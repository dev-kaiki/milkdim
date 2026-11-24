# Fase B — Etiqueta do pedido com QR para registrar a entrega

Data: 24/11/2026. Base: branch `feat/fase-a-fluxo-pedido` (PR dev-kaiki/milkdim#3, ainda não mesclado).

## Por que

O dono da MilkDim pediu uma etiqueta impressa para cada pedido e uma forma rápida de registrar
a entrega. Hoje o vendedor procura o pedido na lista do celular. Com a etiqueta, ele lê o QR
colado na mercadoria e o pedido abre direto na assinatura de entrega. O dono também quer saber
quais pedidos já tiveram a etiqueta impressa (pedido de 18/11).

O sucesso, do ponto de vista dele:
- a fábrica imprime a etiqueta quando a produção do pedido termina;
- qualquer vendedor que está com a mercadoria lê o QR, colhe a assinatura do cliente e o pedido
  fica entregue;
- o Controle mostra quem entregou e se a etiqueta já saiu.

## Decisões do Kaiki

- O QR serve para **registrar a entrega** (23/11).
- O QR é **personalizado no estilo do QR do Instagram**: módulos e cantos arredondados, com o
  logo da MilkDim no centro. A impressora é térmica, então tudo em **preto e branco** (23/11).
- Quem lê o QR pode ser **o vendedor que fez o pedido ou outro vendedor** (24/11).
- **Caminho 1** (24/11): o QR leva um **código secreto do pedido**. Quem tem a etiqueta na mão
  abre só aquele pedido. Nenhum vendedor ganha acesso à lista de pedidos dos outros. Os caminhos
  descartados foram:
  - liberar a leitura de todos os pedidos para todos os vendedores: expõe clientes e preços, e o
    app guarda no celular só os pedidos do próprio vendedor;
  - só o vendedor do pedido registrar a entrega: não atende o pedido do Kaiki.

## Objetivos

1. Cada pedido tem um código secreto (`codigo_qr`, uuid aleatório) criado pelo servidor.
2. O Controle imprime a etiqueta de um pedido e registra quando e por quem ela foi impressa.
3. O app dos vendedores lê o QR e leva à assinatura de entrega:
   - **pedido do próprio vendedor**: usa o que já está no celular, então funciona sem internet;
   - **pedido de outro vendedor**: busca no servidor e grava a entrega no servidor. Precisa de
     internet.
4. O servidor guarda quem entregou (`finalizado_por`, que já existe) e o Controle mostra essa
   informação.

## Não objetivos

- Etiqueta por pote (validade, lote): é pergunta aberta para o dono.
- Imprimir do celular do vendedor.
- Falar a linguagem própria da impressora (PPLA, EPL, ZPL, ESC/POS). A impressão passa pelo
  driver do sistema.
- Forma de cobrança (Fase C).
- O vendedor que entrega um pedido de outro não passa a guardar esse pedido no celular dele.

## Antiobjetivos (falha mesmo funcionando)

- Um vendedor conseguir listar ou abrir pedidos de outros sem ter a etiqueta.
- Um QR estilizado que leitores comuns não leem na etiqueta térmica.
- A entrega de outro vendedor ficar registrada no nome do vendedor que fez o pedido.
- Uma etiqueta antiga, de antes de o pedido mudar, passar despercebida.

## Restrições que continuam valendo

- Repositório público: nenhuma senha, chave, URL ou ref do Supabase em arquivo versionado.
- Nenhuma migração em produção sem mostrar o SQL ao Kaiki e receber o OK no chat.
- Nenhum pedido local é apagado por login, logout, fim de sessão ou sincronização.
- Sem nomes de clientes ou do dono em documentos e capturas.
- A migração precisa ser compatível com os APKs da Fase A já instalados: colunas novas com valor
  padrão, nenhuma coluna removida, gatilhos atuais sem mudança de comportamento.
- Pedidos entregues e cancelados continuam protegidos como na Fase A. A regra "entrega assinada
  vence" continua valendo.

## Servidor (migração `2026112400000x_fase_b_etiqueta_qr.sql`)

Colunas novas em `pedidos`:
- `codigo_qr uuid not null default gen_random_uuid()` com índice único. Os 372 pedidos atuais
  recebem um código pelo valor padrão.
- `etiqueta_impressa_em timestamptz` e `etiqueta_impressa_por text`, ambas nulas por padrão.

Os gatilhos impedem que o app altere essas três colunas: o valor antigo sempre fica. Só as RPCs
abaixo as mudam.

RPCs com `security definer` e `search_path ''`, para usuário autenticado:

- **`pedido_marcar_etiqueta(p_id bigint)`**
  - Só admin; usa o mesmo erro 42501 das RPCs da Fase A.
  - Grava `etiqueta_impressa_em = now()` e `etiqueta_impressa_por` com o código de quem imprimiu.
  - Não mexe em `alterado_em` nem em `status`.

- **`pedido_por_qr(p_codigo uuid)`**: qualquer vendedor com código (`app_meu_codigo()` não nulo).
  - Devolve só o necessário para a entrega: `id`, `numero`, `status`, `vendedor_codigo`,
    `vendedor_nome`, `cliente_nome`, `cliente_nome_fantasia`, `cliente_cidade`, `itens` e
    `do_proprio_vendedor`.
  - `itens` é uma lista de nome e quantidade, sem preço. `do_proprio_vendedor` é um booleano.
  - Não devolve preço, total, CPF/CNPJ, telefone nem assinaturas.
  - Código desconhecido: SQLSTATE P0002.

- **`pedido_entregar_por_qr(p_codigo uuid, p_assinatura bytea)`**: qualquer vendedor com código.
  - Só aceita assinatura não vazia.
  - Faz a mesma transição que o vendedor faz hoje ao registrar a entrega: `status =
    'finalizado'` com a assinatura. Passa pelo gatilho atual, que preenche `finalizado_em` e
    `finalizado_por`.
  - `finalizado_por` precisa ser o código de **quem entregou**. Se `app_autor_pedido()` não der
    esse valor na chamada pela RPC, a RPC grava o código depois do gatilho.
  - **Decisão do Kaiki (24/11)**: quando quem chama **não é o vendedor do pedido**, a entrega só
    é aceita se o pedido estiver `pronto`.
    - Em qualquer outra situação, a RPC dá o SQLSTATE MD003 e o app mostra "Este pedido ainda
      não está pronto para entrega."
    - Se o pedido estiver entregue, vale o MD002 abaixo. Se estiver cancelado, o app mostra "Este
      pedido foi cancelado."
    - O vendedor do pedido continua com as regras de hoje: pode entregar pedido em aberto, e a
      entrega assinada vence o cancelamento.
    - Os mesmos casos entram no teste SQL.
  - Pedido já entregue com assinatura: erro com SQLSTATE próprio (MD002) e a mensagem "Este
    pedido já foi entregue."
  - Pedido cancelado, ou entregue pelo Controle sem assinatura: a entrega assinada vence, como na
    Fase A.
  - Código desconhecido: P0002.
  - Devolve `id`, `numero` e `finalizado_em`.

Teste SQL em `supabase/tests/fase_b_test.sql`, em begin…rollback, como nas fases anteriores. Ele
cobre:
- vendedor A lê e entrega pedido de B pelo QR, e `finalizado_por` fica com o código de A;
- A continua sem ver pedidos de B por `select`;
- código errado dá P0002;
- pedido já entregue dá MD002;
- pedido cancelado aceita a entrega assinada;
- o app não consegue alterar `codigo_qr` nem as colunas da etiqueta;
- vendedor não consegue chamar `pedido_marcar_etiqueta`.

## Conteúdo do QR

- Texto puro `MILKDIM:E:<uuid>`, sem URL e sem domínio.
- O app recusa qualquer outro conteúdo com a mensagem "Esta etiqueta não é de um pedido da
  MilkDim."

## Controle: imprimir a etiqueta

Onde aparece:
- **"Imprimir etiqueta"** em cada cartão de "Prontos para entrega" e no detalhe do pedido.
- Depois de "Produção concluída" dar certo, o Controle pergunta "Imprimir a etiqueta agora?".

Como imprime:
- A etiqueta é gerada em PDF no tamanho do rolo e enviada pelo pacote `printing`, que abre o
  diálogo de impressão do sistema.
- Só se a impressão for confirmada é que o Controle chama `pedido_marcar_etiqueta`.
- O Controle precisa ter o `codigo_qr` em mãos, então a lista de produção passa a pedir essa
  coluna.

Marcas no cartão e no detalhe:
- "Etiqueta impressa às HH:mm" quando já saiu.
- "Sem etiqueta" quando o pedido está pronto e nunca foi impresso.
- "Etiqueta desatualizada" quando `alterado_em` é posterior a `etiqueta_impressa_em`. O QR antigo
  continua abrindo o pedido, mas os itens impressos estão velhos.

Tamanho da etiqueta:
- Configuração do Controle, guardada no computador: 100×100 mm (padrão), 100×150 mm e 60×40 mm.
- A impressora ainda não foi comprada. A sugestão é a Elgin L42 Pro com etiqueta 100×100 mm.

Esboço da etiqueta (100×100 mm):

```
┌────────────────────────────────┐
│ MILKDIM            Pedido 1234 │
│ <Nome fantasia ou nome>        │
│ <Cidade>     Vendedor 0002     │
│────────────────────────────────│
│ 15×  <produto A>               │
│ 10×  <produto B>               │
│  4×  <produto C>               │
│ Total: 29 unidades             │
│────────────────────────────────│
│        ┌──────────┐            │
│        │  QR com  │ Pronto em  │
│        │  logo    │ 24/11 14:05│
│        └──────────┘            │
└────────────────────────────────┘
```

- Muitos itens: a lista diminui a fonte até um limite. Se ainda não couber, a etiqueta continua
  numa segunda ("1/2", "2/2"), e o QR sai em todas.
- QR personalizado:
  - módulos com cantos arredondados e os três quadrados de canto arredondados;
  - logo da MilkDim no centro, sobre fundo branco;
  - correção de erro alta (H), com o logo cobrindo no máximo cerca de 20% da área;
  - margem branca de 4 módulos;
  - tamanho mínimo de 30 mm na etiqueta de 100 mm;
  - tudo em preto puro, sem cinza, porque a térmica não imprime meio-tom.

## App dos vendedores: ler o QR

Botão **"Ler etiqueta"**:
- na tela inicial e em Meus pedidos;
- abre a câmera com o pacote `mobile_scanner`;
- pede a permissão de câmera na primeira vez. Se ela for negada, mostra como liberar.

Depois de ler o QR:
1. **Conteúdo inválido**: mostra a mensagem do item "Conteúdo do QR".
2. **O código bate com um pedido no celular**: abre a tela atual do pedido em "Registrar
   entrega". O fluxo é o mesmo de hoje, inclusive sem internet, e o envio vai pela fila normal.
   - Para isso o banco local passa para a v19 com a coluna `codigo_qr`, que vem do servidor no
     eco do envio e na sincronização.
   - Pedido local que nunca foi enviado não tem código, e nem poderia ter etiqueta.
3. **Não bate e há internet**: chama `pedido_por_qr` e abre uma tela nova, "Entrega de pedido",
   com:
   - número, vendedor, cliente, cidade e itens com quantidade;
   - o aviso "Pedido do vendedor 0002" quando o pedido é de outro vendedor;
   - se o pedido é de outro vendedor e não está pronto, a tela mostra o motivo no lugar da
     assinatura e não oferece "Registrar entrega". Os motivos são "ainda não está pronto",
     "cancelado" e "já entregue";
   - a assinatura do cliente e o botão "Registrar entrega", que chama `pedido_entregar_por_qr`.
   - Se der certo: "Entrega registrada." e a tela volta. Nada é gravado no banco local.
   - Se o pedido do servidor for do próprio vendedor mas não estiver no celular, por exemplo
     depois de reinstalar o app: a tela nova faz a entrega e depois a sincronização normal traz o
     pedido.
4. **Não bate e não há internet**: "Sem internet. Para entregar pedido de outro vendedor, conecte
   e leia de novo."
5. **Erros do servidor**:
   - P0002: "Pedido não encontrado.";
   - MD002: "Este pedido já foi entregue.";
   - falha de rede no meio: "Não deu para confirmar a entrega. Leia a etiqueta de novo." Ler de
     novo depois de uma entrega que deu certo cai no MD002, sem gravar duas vezes.

O vendedor que fez o pedido fica sabendo da entrega pela sincronização. Essa parte já existe para
entregas feitas pelo Controle.

## Controle: quem entregou

- O detalhe do pedido mostra "Entregue por <código> (<nome>)".
- Quando quem entregou não é o vendedor do pedido, o detalhe acrescenta "(outro vendedor)".

## Decisões tomadas por mim (Claude) depois da revisão, para o Kaiki conferir

- **Onde o Controle roda**: no Windows (build `MilkDim_Controle_Windows_*`). O Controle também
  tem um APK de Android. A web não é alvo.
  - A confirmação do diálogo de impressão não garante que a etiqueta saiu certa. Por isso,
    depois do diálogo, o Controle sempre pergunta **"A etiqueta saiu certa?"** (Sim / Imprimir
    de novo / Cancelar). Só o "Sim" chama `pedido_marcar_etiqueta`.
  - O tamanho da etiqueta fica nas preferências locais do Controle, em cada computador.
- **Código nos pedidos que já estão no celular**: na primeira sincronização depois da v19, o app
  preenche `codigo_qr` em todos os pedidos locais que já foram enviados.
  - A sincronização atual já baixa todos os pedidos do vendedor (`select` por
    `vendedor_codigo`). Com isso, um pedido do próprio vendedor entregue pela tela nova chega ao
    celular na próxima sincronização.
- **Pedido encontrado no celular**: o que está no celular sempre vence. A tela abre em
  "Registrar entrega" mesmo que o pedido tenha alterações ainda não enviadas. A fila e os
  gatilhos resolvem o resto, como hoje.
- **Depois de entregue ou cancelado**: `pedido_por_qr` devolve só `numero` e `status`, sem
  cliente nem itens. A etiqueta antiga deixa de mostrar dados do cliente.
- **Proteção das colunas novas**:
  - na inserção, o gatilho força `etiqueta_impressa_em` e `etiqueta_impressa_por` para nulo e
    ignora qualquer `codigo_qr` enviado pelo app, deixando o servidor gerar o código;
  - na alteração, as três colunas sempre ficam com o valor antigo;
  - só as RPCs da Fase B mudam essas colunas.

## O que fica para quem construir

- A forma de desenhar o QR arredondado no PDF. Uma opção é gerar a matriz com o pacote `qr` e
  desenhar as formas no `pdf`.
  - Antes de fechar a tarefa, gerar uma amostra em PDF e PNG para o Kaiki aprovar o visual.
  - Na mesma tarefa, testar a leitura da amostra com um leitor comum e com o `mobile_scanner`.
- O logo usado no QR: existe um logo no pacote `milkdim_ui`; uma versão só em preto, se
  precisar, é decisão de quem construir.
- O layout exato da etiqueta, dentro do esboço acima.

## Ordem de implantação

1. Mostrar o SQL ao Kaiki, rodar o teste em rollback e aplicar com OK. A migração é compatível
   com os APKs da Fase A.
2. Instalar o Controle novo na fábrica. Ele já imprime sem depender dos vendedores.
3. Instalar o APK novo em todos os vendedores.
4. A Fase B só vai para produção depois que o PR #3 for mesclado, porque é construída sobre ele.
