# Implantação — Fase B (etiqueta com QR e entrega por leitura)

Roteiro da instalação, na ordem. Marque cada caixa ao terminar. **A ordem importa**: o banco
vem primeiro.

## Lembretes importantes

- **Banco antes do Controle.** A aba Produção do Controle novo pede colunas que só existem
  depois da migração da Fase B. Se o Controle novo for aberto num banco sem a migração, a
  aba Produção dá erro. A migração é compatível com os apps da Fase A que já estão instalados,
  então aplicá-la primeiro não atrapalha ninguém.
- **Nunca desinstalar o app antes de instalar o novo.** Desinstalar apaga os pedidos guardados
  no celular. Sempre instalar **por cima**.
- **Nunca use Apagar num pedido em aberto ou pronto no Controle; use Cancelar.** Apagar só
  pedidos já entregues ou cancelados.
- Este roteiro **não** guarda endereço do banco, senhas nem nomes de clientes. Esses dados ficam
  só com o dono.

## 1. Pré-requisito

- [ ] **PR #3 (Fase A) mesclado.** Os builds da Fase B saem da branch já mesclada, nunca da
      anterior.

## 2. Banco (primeiro de tudo)

A migração da Fase B é o arquivo `supabase/migrations/20261124000001_fase_b_etiqueta_qr.sql`.
O teste dela é `supabase/tests/fase_b_test.sql`. O teste já rodou uma vez dentro de uma
transação desfeita (24/11/2026) e passou. Agora ele roda de novo, logo antes de aplicar.

- [ ] **1.** Abrir o arquivo da migração e mostrar o SQL ao dono. Explicar em uma frase o que
      ele faz: acrescenta as colunas da etiqueta (impressão e entrega por leitura) e a função
      de entrega por QR. Não apaga nem altera dados existentes.
- [ ] **2.** Rodar o teste `fase_b_test.sql` **em rollback** (a transação é desfeita no fim e
      nada fica gravado). Conferir que terminou sem erro.
- [ ] **3.** Só depois do **OK do dono**, aplicar a migração.
- [ ] **4.** Conferir que os apps da Fase A continuam funcionando: no Controle atual, abrir a
      aba Produção e atualizar. Não deve haver erro.

## 3. Controle novo na fábrica (depois do banco)

- [ ] Gerar os builds da branch mesclada e guardá-los em `Downloads\GitHub\milkdim-builds`,
      com a data e `faseB` no nome (como foi feito na Fase A).
- [ ] Computador da fábrica: substituir a pasta do Controle antigo pela pasta nova do Controle
      Windows. O executável tem o mesmo nome (`milkdim_admin.exe`), então o atalho continua
      funcionando. Guardar a pasta antiga como backup.
- [ ] Abrir e entrar com o código de um admin e a senha dele. Conferir que a aba **Produção**
      abre sem erro.
- [ ] Celular Android do Controle: instalar o APK novo do Controle **por cima** e entrar.

### Impressora

A impressão passa pelo driver do Windows. Antes de testar no Controle:

- [ ] **Instalar o driver da impressora** no computador da fábrica e imprimir uma página de teste
      pelo próprio Windows. Se isso não imprime, o Controle também não vai imprimir.
- Sugestão de impressora térmica: **Elgin L42 Pro**, com etiquetas de **100 × 100 mm**.

### Tamanho da etiqueta

- [ ] Na aba **Produção**, tocar na **engrenagem** do topo e escolher o tamanho:
  - **100 × 100 mm** (padrão)
  - **100 × 150 mm**
  - **60 × 40 mm**
- A escolha vale **por computador**. Cada computador que imprime precisa ter o tamanho certo
  escolhido.
- No Windows, o tamanho do papel do driver da impressora precisa ser o mesmo da etiqueta.

### Etiqueta de teste

- [ ] Precisa de um pedido **pronto**: usar um pedido de teste que já esteja em **Prontos para
      entrega**, ou criar um como nos passos 1 e 2 da seção 5. No Controle, em **Prontos para
      entrega** (ou no detalhe do pedido pronto), tocar em **Imprimir etiqueta**.
- [ ] Quando perguntar **"A etiqueta saiu certa?"**: **Sim** (marca como impressa), **Imprimir de
      novo** ou **Cancelar**. Só **Sim** marca a etiqueta como impressa.
- [ ] Conferir a etiqueta: nada cortado, texto legível.
- [ ] **Ler o QR com um celular qualquer** (a câmera comum serve). O QR é um link
      (`https://dev-kaiki.github.io/m/#…`): num celular sem o app abre a página "Etiqueta de pedido
      MilkDim"; num celular com o APK novo abre o app. Se os pontinhos redondos do QR saírem
      borrados na impressora, é um pequeno ajuste que dá para pedir.

## 4. APK novo em todos os vendedores (depois do Controle)

Para cada vendedor, **com o celular na internet**:

- [ ] Instalar o APK novo do app dos vendedores **por cima** (não desinstalar).
- [ ] Abrir o app. Ele deve entrar direto, sem pedir login de novo.
- [ ] Abrir o app uma vez **com internet** depois de instalar: é assim que os pedidos que já
      estão no celular recebem o código do QR. Pedido que estava aguardando envio na hora da
      atualização recebe o código no próximo envio.
- [ ] Esperar a tela inicial mostrar **0 pedidos aguardando envio**. Se mostrar N > 0, tocar
      "Enviar agora" e esperar zerar.
- [ ] Conferir o botão **Ler etiqueta** na tela inicial e em **Meus pedidos**. No primeiro uso,
      o Android pede permissão da câmera: **Permitir**.
- [ ] Ler uma etiqueta com a **câmera comum do celular** (fora do app): tem que abrir o app
      MilkDim direto no pedido. Se abrir a página "Etiqueta de pedido MilkDim" no navegador,
      ver "A câmera abre a página e não o app" na seção 7.

## 5. Teste de ponta a ponta

Dois vendedores, **A** e **B**, com códigos diferentes e celulares com o APK novo. Mais o
Controle novo no computador (da fábrica ou do dono) e a impressora funcionando. **Não apagar
nada no fim**: os pedidos de teste ficam como estão.

- [ ] **1.** **A** cria **dois** pedidos (vamos chamar de P1 e P2) e toca **Enviar pedido** em
      cada um (o cliente assina). Os dois aparecem em **Pedidos em aberto** no Controle.
- [ ] **2.** Na fábrica: **Produção concluída** em P1. Aparece **"Imprimir a etiqueta agora?"**:
      tocar em **Agora**, imprimir e responder **Sim** em **"A etiqueta saiu certa?"**. Fazer
      o mesmo com P2 (concluir, **Agora**, imprimir, **Sim**). Os dois ficam em **Prontos para entrega**.
      Guardar as duas etiquetas, cada uma com o nome do pedido anotado.
- [ ] **3.** **A** abre P2, muda uma quantidade e toca **Salvar alterações** (o cliente assina
      de novo). P2 volta para **Pedidos em aberto** no Controle. A etiqueta de P2 que já saiu
      continua existindo: está velha, mas o QR dela ainda abre o pedido. Agora **B** toca **Ler
      etiqueta** e lê essa etiqueta de P2. Deve aparecer **"Este pedido ainda não está pronto
      para entrega."**
- [ ] **4.** **B** (com internet) lê a etiqueta de P1, que está pronto. Abre **Registrar
      entrega**, o cliente assina e aparece **"Entrega registrada."**
- [ ] **5.** No Controle, atualizar e abrir P1: mostra **"Entregue por B (outro vendedor)"**,
      com o nome de B (não o código).
- [ ] **6.** **A** sincroniza (abre o app com internet). P1 aparece como **Entregue**.
- [ ] **7.** Na fábrica, **Produção concluída** em P2 de novo e responder **Depois** em
      **"Imprimir a etiqueta agora?"** (não imprimir etiqueta nova). **A** coloca o celular em **modo
      avião**, toca **Ler etiqueta** e lê **a mesma etiqueta de P2 que saiu no passo 2** (o
      pedido é dele). Abre **Registrar entrega**, o cliente assina e a entrega fica guardada
      no celular. Desligar o modo avião e tocar **Enviar agora**: a entrega chega ao Controle.
- [ ] **8.** **Ler de novo** a etiqueta de um pedido já entregue (P1, com **B** ou **A**, com
      internet): aparece **"Este pedido já foi entregue."**
- [ ] **9.** Etiqueta desatualizada, com um terceiro pedido P3 de **A**: enviar, **Produção
      concluída**, **Imprimir etiqueta**, **Sim**. Depois **A** abre P3, muda uma quantidade e
      toca **Salvar alterações**. P3 volta para **Pedidos em aberto**. Na fábrica, **Produção
      concluída** de novo: no cartão em **Prontos para entrega** e no detalhe de P3 aparece
      **"Etiqueta desatualizada"**, e é preciso imprimir de novo. A etiqueta velha deixou de
      refletir o pedido.
- [ ] **10.** Câmera comum: com um pedido pronto P4 de **A** e a etiqueta impressa, **A** fecha o
      app, abre a **câmera comum** do celular e aponta para a etiqueta. Tocar no link que
      aparece: o app abre direto em **Registrar entrega** de P4. Fazer o mesmo com o app já
      aberto em outra tela: o pedido abre por cima.

## 6. Mensagens do app e o que fazer

| Mensagem | O que significa / o que fazer |
|---|---|
| Esta etiqueta não é de um pedido da MilkDim. | O QR lido é de outra coisa. Ler a etiqueta correta. |
| Pedido não encontrado. | O pedido foi apagado (**Apagar**) no Controle, ou a etiqueta não é deste sistema. Conferir no Controle se o pedido ainda existe. Imprimir de novo não resolve: a etiqueta nova sai com o mesmo código. |
| Este pedido já foi entregue. | Nada a fazer: a entrega já foi registrada. |
| Este pedido ainda não está pronto para entrega. | Esperar a fábrica dar **Produção concluída**. |
| Este pedido foi cancelado. | Não entregar. Falar com a fábrica. |
| Não deu para confirmar a entrega. Leia a etiqueta de novo. | Falha na confirmação. Ler a etiqueta outra vez. |
| Não deu para ler o pedido. Leia a etiqueta de novo. | O servidor não respondeu (internet fraca ou caiu). Ler a etiqueta outra vez. |
| Não deu para ler a etiqueta. Tente de novo. | Falha ao tratar a leitura no celular. Ler a etiqueta outra vez. |
| Este pedido foi apagado no Controle. | Pedido do próprio vendedor que foi apagado no Controle: não entregar por ele. Falar com a fábrica. |
| Sem internet. Para entregar pedido de outro vendedor, conecte e leia de novo. | Pedido de outro vendedor só com internet. Conectar e ler de novo. |
| Entrega registrada. | Tudo certo. |
| Libere a câmera nas configurações do Android para ler etiquetas. | Ver "Câmera negada" abaixo. |
| Não deu para abrir a câmera. | Tocar **Tentar de novo**. Se continuar, fechar o app e abrir de novo. |
| Não deu para abrir a etiqueta. Tente de novo. | Falha ao abrir o pedido pelo link da câmera comum. Ler de novo, ou usar **Ler etiqueta** dentro do app. |

Regra geral da leitura:

- **Pedido do próprio vendedor:** abre **Registrar entrega** e funciona **sem internet**.
- **Pedido de outro vendedor:** precisa de internet e só funciona se o pedido estiver **Pronto
  para entrega**. Vale também para pedido de outro vendedor guardado no mesmo celular: conta o
  vendedor que está logado.

## 7. Problemas comuns

- **Câmera negada.** O app mostra "Libere a câmera nas configurações do Android para ler
  etiquetas." No celular: Configurações, Apps, MilkDim, Permissões, Câmera, **Permitir**. Voltar
  ao app e tocar **Ler etiqueta** de novo.
- **A câmera abre a página e não o app.** O Android ainda não confirmou que o link é do app.
  Confira se o celular está com o APK novo e com internet. No celular: Configurações, Apps,
  MilkDim, **Abrir por padrão**, ligar **Abrir links compatíveis** e conferir se
  `dev-kaiki.github.io` está marcado. Enquanto isso, o botão **Ler etiqueta** dentro do app
  funciona sempre. O link depende do arquivo `.well-known/assetlinks.json` do site
  `dev-kaiki.github.io` e da chave que assina o APK: se a chave mudar, o arquivo precisa ser
  atualizado.
- **Impressora sem driver.** O Controle imprime pelo driver do Windows. Se não aparece a
  impressora ou nada sai, instalar o driver do fabricante e imprimir uma página de teste pelo
  Windows. Só depois tentar de novo no Controle.
- **Etiqueta cortada ou com margens estranhas.** O tamanho escolhido no Controle (engrenagem da
  aba Produção) não é o da etiqueta que está na impressora, ou o papel do driver está
  diferente. Escolher o tamanho certo (100 × 100, 100 × 150 ou 60 × 40 mm), ajustar o papel do
  driver para o mesmo tamanho e imprimir de novo. Lembrar: a escolha vale por computador.
- **O QR não lê.** Imprimir de novo, conferir se a etiqueta está limpa e sem dobras. Se a
  impressora borra os pontinhos, avisar para fazer o pequeno ajuste.
- **"O pedido mudou depois que a tela foi atualizada. Atualize e confira." no Controle**, ao
  responder **Sim** em "A etiqueta saiu certa?". O vendedor alterou o pedido depois que a tela
  foi atualizada, então a etiqueta que saiu é de uma versão velha e não fica marcada. Atualizar,
  conferir o pedido e imprimir de novo.
- **Aba Produção com erro.** Quase certo que o banco ainda não recebeu a migração da Fase B
  (seção 2). Aplicá-la e abrir o Controle de novo.
