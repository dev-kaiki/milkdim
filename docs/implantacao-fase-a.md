# Implantação — Fase A (novo fluxo do pedido)

Roteiro da instalação, na ordem. Marque cada caixa ao terminar.

## Já feito

- [x] **1. Banco atualizado** — migração aplicada em 23/11/2026, com o OK do dono.
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

**Nunca use Apagar num pedido em aberto no Controle; use Cancelar.** Um pedido em aberto
apagado no Controle fica para sempre "aguardando envio" no celular do vendedor. Apagar só
pedidos já finalizados ou cancelados.

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

- Nova primeira aba **Produção**, com **A fabricar** (total por produto, em unidades) e
  **Pedidos em aberto**.
- A tela atualiza sozinha a cada 30 segundos, e há o botão **Atualizar**.
- Cada pedido em aberto tem os botões **Finalizar** (manual) e **Cancelar**.
- A aba **Pedidos** ganhou um filtro por situação.
- No detalhe do pedido aparece quem finalizou ou cancelou, e quando.

## 3. APK novo nos vendedores (depois do Controle)

Para cada vendedor, **com o celular na internet**:

- [ ] Instalar `MilkDim_Funcionario_2026-11-23_faseA.apk` **por cima** (não desinstalar).
- [ ] Abrir o app. Ele deve entrar direto, sem pedir login de novo.
- [ ] Esperar a tela inicial mostrar **0 pedidos aguardando envio**. Se mostrar N > 0, tocar
      "Enviar agora" e esperar zerar.

O que o vendedor vai notar:

- Salvar sem assinatura agora **envia o pedido para a fábrica**: aparece
  "Pedido enviado para produção."
- "Meus pedidos" abre em **Em aberto** e tem uma aba **Cancelados**.
- Rascunhos antigos que estavam no celular aparecem como **Não enviado**. Eles só são enviados
  se forem abertos e salvos.
- O número do pedido fica travado depois que o pedido chega ao servidor.
- O botão **Trocar número** só aparece quando há conflito de número.

## 4. Teste de ponta a ponta

Com um vendedor (de preferência o 0001) e o Controle aberto no computador:

- [ ] O vendedor faz um pedido de teste e **salva sem assinatura**. Aparece
      "Pedido enviado para produção."
- [ ] O pedido aparece na aba **Produção** em até 30 segundos, e os totais de **A fabricar**
      sobem.
- [ ] O vendedor edita o pedido e salva. No Controle aparece **"alterado às"** com a hora.
- [ ] O vendedor finaliza com assinatura. O pedido **sai da Produção** e os totais descem.
- [ ] Fazer outro pedido sem assinatura e testar **Cancelar** pelo Controle. Ele some da
      Produção e aparece em **Cancelados** no celular do vendedor.
- [ ] Fazer mais um pedido sem assinatura. **Finalizar manualmente no Controle** e depois o
      vendedor, sem sincronizar o celular antes, abrir o pedido em **Em aberto** e
      **finalizar com assinatura** (mudando uma quantidade). Vale a do vendedor:
      no detalhe do pedido no Controle aparecem as quantidades do vendedor, "Finalizado por"
      com o código dele (sem "manual"), e em **Dados brutos** a coluna `assinatura` vem
      preenchida.
- [ ] Apagar os pedidos de teste pelo Controle (só depois de finalizados ou cancelados).

## Pendência

- [ ] **Conta da fábrica:** definir com o dono qual código de admin a esposa do dono vai
      usar no Controle. Admins atuais: 0001, 0002 e 700122.
