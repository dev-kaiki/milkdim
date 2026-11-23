# Implantação — Fase A (novo fluxo do pedido)

Roteiro da instalação, na ordem. Marque cada caixa ao terminar.

## Já feito

- [x] **1. Banco atualizado** — duas migrações aplicadas, as duas em 23/11/2026, com o OK do dono:
  - [x] Migração 1 (Fase A: pedidos em aberto, Produção, Cancelar).
  - [x] Migração 2 (pedido pronto para entrega + assinatura do pedido e assinatura da entrega).
- [x] Builds gerados em `Downloads\GitHub\milkdim-builds`:
  - `MilkDim_Funcionario_2026-11-23_faseA.apk` — app dos vendedores
  - `MilkDim_Controle_2026-11-23_faseA.apk` — Controle no celular
  - `MilkDim_Controle_Windows_2026-11-23_faseA\milkdim_admin.exe` — Controle no computador

## Lembrete importante

**O APK antigo continua funcionando com o banco novo.** Ele só segue enviando apenas pedidos
finalizados, como antes. Dá para instalar aos poucos, **um código de vendedor por vez**:

- **Todos os celulares que usam o mesmo código de vendedor são atualizados juntos**, no mesmo
  dia, antes de alguém voltar a fazer pedido. APK antigo e APK novo no mesmo código podem
  perder edições ou finalizações feitas no celular (o antigo não conhece os pedidos em aberto
  que o novo envia, e a sincronização dele pode passar por cima).
- Vendedores com códigos diferentes podem ficar um com o antigo e outro com o novo.

**Nunca use Apagar num pedido em aberto ou pronto no Controle; use Cancelar.** Um pedido em
aberto apagado no Controle fica para sempre "aguardando envio" no celular do vendedor. Apagar
só pedidos já entregues ou cancelados.

**Nunca desinstalar o app antes de instalar o novo.** Desinstalar apaga os pedidos guardados
no celular. Sempre instalar **por cima**.

## 2. Controle novo (instalar primeiro)

- [ ] Computador da fábrica: substituir a pasta do Controle antigo pela pasta
      `MilkDim_Controle_Windows_2026-11-23_faseA`. O executável tem o mesmo nome
      (`milkdim_admin.exe`), então o atalho continua funcionando. Guardar a pasta antiga como backup.
- [ ] Abrir e entrar com o código de um admin e a senha dele. Conferir que a primeira aba é
      **Produção**.
- [ ] Celular Android do Controle: instalar `MilkDim_Controle_2026-11-23_faseA.apk` **por cima**
      e entrar.

O que a fábrica vai notar:

- Primeira aba **Produção**, com **A fabricar** (total por produto, em unidades, contando só
  pedidos em aberto) e duas listas:
  - **Pedidos em aberto**, com **Produção concluída** (o Controle pergunta "Marcar como pronto
    para entrega?") e **Cancelar**.
  - **Prontos para entrega**, com **Marcar como entregue** e **Cancelar**.
- A tela atualiza sozinha a cada 30 segundos, e há o botão **Atualizar**.
- Aparece o aviso **"alterado depois de pronto"** quando o vendedor mexeu num pedido que já
  estava pronto. Esse pedido volta para **Pedidos em aberto**.
- Se o vendedor mudou o pedido depois que a tela foi atualizada, **Produção concluída** é
  recusada com "O pedido mudou depois que a tela foi atualizada. Atualize e confira." Basta
  tocar em Atualizar e conferir.
- A aba **Pedidos** ganhou um filtro: Todos / Em aberto / Prontos / Entregues / Cancelados.
- No detalhe do pedido aparecem **Pronto em/por**, quem entregou ou cancelou, e quando, e as
  **duas assinaturas** (do pedido e da entrega).

## 3. APK novo nos vendedores (depois do Controle)

Para cada vendedor, **com o celular na internet**:

- [ ] Instalar `MilkDim_Funcionario_2026-11-23_faseA.apk` **por cima** (não desinstalar).
- [ ] Abrir o app. Ele deve entrar direto, sem pedir login de novo.
- [ ] Esperar a tela inicial mostrar **0 pedidos aguardando envio**. Se mostrar N > 0, tocar
      "Enviar agora" e esperar zerar.

O que o vendedor vai notar:

- Pedido novo tem dois botões: **Salvar rascunho** (fica só no celular) e **Enviar pedido**.
  Em **Enviar pedido** o cliente assina o **pedido**; ele vai para a fábrica e aparece
  "Pedido enviado para produção."
- Ao abrir um pedido em aberto ou pronto aparecem **Salvar alterações** e **Registrar entrega**:
  - **Salvar alterações**: se itens ou cliente mudaram, o cliente assina o pedido de novo.
  - **Registrar entrega**: o cliente assina a **entrega** e o pedido vira **Entregue**.
- "Meus pedidos" tem três abas: **Em aberto** (inclui os pedidos prontos, com o selo
  **Pronto**), **Entregues** e **Cancelados**. Os selos dos pedidos são **Em aberto** e **Entregue**.
- O PDF mostra **Assinatura do pedido** e **Assinatura da entrega**.
- Rascunhos antigos que estavam no celular aparecem como **Não enviado**. Para serem enviados
  precisam da assinatura do cliente no pedido.
- O número do pedido fica travado depois que o pedido chega ao servidor.
- O botão **Trocar número** só aparece quando há conflito de número.

## 4. Teste de ponta a ponta

Usar **um código de vendedor que nenhum outro celular usa** (por exemplo 0001), no celular do
dono, e o Controle novo (pasta do Windows copiada para qualquer lugar do computador do dono;
isso não mexe no computador da fábrica).

- [ ] **1.** Pedido novo → **Enviar pedido** → o cliente assina. O pedido aparece em **Pedidos
      em aberto** em até 30 segundos e o total de **A fabricar** sobe.
- [ ] **2.** No Controle: **Produção concluída**. O pedido passa para **Prontos para entrega** e
      os totais descem. No celular, depois de sincronizar, o pedido mostra **Pronto**.
- [ ] **3.** No celular: abrir o pedido, mudar uma quantidade e tocar **Salvar alterações**. O
      app pede nova assinatura do cliente. O Controle mostra o pedido de volta em **Pedidos em
      aberto**, com **alterado depois de pronto**.
- [ ] **4.** No Controle: **Produção concluída** de novo.
- [ ] **5.** No celular: **Registrar entrega** → o cliente assina a entrega. O pedido sai da
      Produção; no detalhe aparecem as duas assinaturas; o PDF no celular mostra as duas.
- [ ] **6.** Outro pedido: **Produção concluída**. Colocar o celular em modo avião. No Controle,
      **Marcar como entregue**. No celular (ainda sem internet): abrir o pedido, mudar uma
      quantidade e **Registrar entrega** com assinatura. Ligar a internet e tocar **Enviar
      agora**. Vale a versão do vendedor: quantidades dele, "Finalizado por" com o código dele
      (sem "(manual)") e assinatura preenchida.
- [ ] **7.** Outro pedido: **Cancelar** pelo Controle. Ele aparece em **Cancelados** no celular.
- [ ] **8.** Limpar os pedidos de teste pelo Controle (só os entregues ou cancelados).

## Pendência

- [ ] **Conta da fábrica:** definir com o dono qual código de admin a esposa do dono vai
      usar no Controle. Admins atuais: 0001, 0002 e 700122.
