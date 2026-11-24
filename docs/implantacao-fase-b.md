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

- [ ] No Controle, em **Prontos para entrega** (ou no detalhe de um pedido pronto), tocar em
      **Imprimir etiqueta** num pedido de teste.
- [ ] Quando perguntar **"A etiqueta saiu certa?"**: **Sim** (marca como impressa), **Imprimir de
      novo** ou **Cancelar**. Só **Sim** marca a etiqueta como impressa.
- [ ] Conferir a etiqueta: nada cortado, texto legível.
- [ ] **Ler o QR com um celular qualquer** (a câmera comum serve). Tem que ler. Se os pontinhos
      redondos do QR saírem borrados na impressora, é um pequeno ajuste que dá para pedir.

## 4. APK novo em todos os vendedores (depois do Controle)

Para cada vendedor, **com o celular na internet**:

- [ ] Instalar o APK novo do app dos vendedores **por cima** (não desinstalar).
- [ ] Abrir o app. Ele deve entrar direto, sem pedir login de novo.
- [ ] Esperar a tela inicial mostrar **0 pedidos aguardando envio**. Se mostrar N > 0, tocar
      "Enviar agora" e esperar zerar.
- [ ] Conferir o botão **Ler etiqueta** na tela inicial e em **Meus pedidos**. No primeiro uso,
      o Android pede permissão da câmera: **Permitir**.

## 5. Teste de ponta a ponta

Dois vendedores, **A** e **B**, com códigos diferentes e celulares com o APK novo. Mais o
Controle novo no computador (da fábrica ou do dono) e a impressora funcionando. **Não apagar
nada no fim**: os pedidos de teste ficam como estão.

- [ ] **1.** **A** cria um pedido e toca **Enviar pedido** (o cliente assina). Cria também um
      segundo pedido e envia, para usar no passo 3. O pedido aparece em **Pedidos em aberto**
      no Controle.
- [ ] **2.** Na fábrica: **Produção concluída** no **primeiro** pedido. Aparece
      **"Imprimir a etiqueta agora?"**: tocar em sim, imprimir e responder **Sim** em **"A
      etiqueta saiu certa?"**. O pedido fica em **Prontos para entrega**. O segundo pedido
      continua em aberto.
- [ ] **3.** **B** toca **Ler etiqueta** e lê o QR do **segundo** pedido (o que ainda está em
      aberto). Para isso, imprimir a etiqueta dele pelo detalhe do pedido, sem concluir a
      produção. Deve aparecer **"Este pedido ainda não está pronto para entrega."**
- [ ] **4.** **B** (com internet) lê o QR do **primeiro** pedido, o pronto. Abre **Registrar
      entrega**, o cliente assina e aparece **"Entrega registrada."**
- [ ] **5.** No Controle, atualizar e abrir o pedido: mostra **"Entregue por B (outro
      vendedor)"**, com o código e o nome de B.
- [ ] **6.** **A** sincroniza (abre o app com internet). O primeiro pedido aparece como
      **Entregue**.
- [ ] **7.** Na fábrica, concluir a produção do segundo pedido. **A** coloca o celular em **modo
      avião**, toca **Ler etiqueta** e lê o QR desse pedido (que é dele). Abre **Registrar
      entrega**, o cliente assina e a entrega fica guardada no celular. Desligar o modo avião e
      tocar **Enviar agora**: a entrega chega ao Controle.
- [ ] **8.** **Ler de novo** o QR de um pedido já entregue (com **B** ou **A**, com internet):
      aparece **"Este pedido já foi entregue."**
- [ ] **9.** Alterar um pedido pronto: com um pedido novo de **A** já pronto, **A** abre o
      pedido, muda uma quantidade e toca **Salvar alterações** (o cliente assina de novo). No
      Controle ele volta para **Pedidos em aberto**. Dar **Produção concluída** de novo: a
      etiqueta que já existe aparece como **"Etiqueta desatualizada"** e precisa ser
      impressa de novo. A etiqueta velha não vale mais.

## 6. Mensagens do app e o que fazer

| Mensagem | O que significa / o que fazer |
|---|---|
| Esta etiqueta não é de um pedido da MilkDim. | O QR lido é de outra coisa. Ler a etiqueta correta. |
| Pedido não encontrado. | Etiqueta antiga ou de outro sistema. Imprimir uma nova pelo Controle. |
| Este pedido já foi entregue. | Nada a fazer: a entrega já foi registrada. |
| Este pedido ainda não está pronto para entrega. | Esperar a fábrica dar **Produção concluída**. |
| Este pedido foi cancelado. | Não entregar. Falar com a fábrica. |
| Não deu para confirmar a entrega. Leia a etiqueta de novo. | Falha na confirmação. Ler a etiqueta outra vez. |
| Sem internet. Para entregar pedido de outro vendedor, conecte e leia de novo. | Pedido de outro vendedor só com internet. Conectar e ler de novo. |
| Entrega registrada. | Tudo certo. |
| Libere a câmera nas configurações do Android para ler etiquetas. | Ver "Câmera negada" abaixo. |

Regra geral da leitura:

- **Pedido do próprio vendedor:** abre **Registrar entrega** e funciona **sem internet**.
- **Pedido de outro vendedor:** precisa de internet e só funciona se o pedido estiver **Pronto
  para entrega**.

## 7. Problemas comuns

- **Câmera negada.** O app mostra "Libere a câmera nas configurações do Android para ler
  etiquetas." No celular: Configurações, Apps, MilkDim, Permissões, Câmera, **Permitir**. Voltar
  ao app e tocar **Ler etiqueta** de novo.
- **Impressora sem driver.** O Controle imprime pelo driver do Windows. Se não aparece a
  impressora ou nada sai, instalar o driver do fabricante e imprimir uma página de teste pelo
  Windows. Só depois tentar de novo no Controle.
- **Etiqueta cortada ou com margens estranhas.** O tamanho escolhido no Controle (engrenagem da
  aba Produção) não é o da etiqueta que está na impressora, ou o papel do driver está
  diferente. Escolher o tamanho certo (100 × 100, 100 × 150 ou 60 × 40 mm), ajustar o papel do
  driver para o mesmo tamanho e imprimir de novo. Lembrar: a escolha vale por computador.
- **O QR não lê.** Imprimir de novo, conferir se a etiqueta está limpa e sem dobras. Se a
  impressora borra os pontinhos, avisar para fazer o pequeno ajuste.
- **Aba Produção com erro.** Quase certo que o banco ainda não recebeu a migração da Fase B
  (seção 2). Aplicá-la e abrir o Controle de novo.
