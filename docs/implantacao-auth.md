# Implantação — login por Supabase Auth

Roteiro da troca, na ordem. Marque cada caixa ao terminar.

## Já feito (19/11/2026)

- [x] Fase 1 aplicada no banco (contas dos 4 vendedores com a senha atual).
- [x] Contas do Controle criadas: usuário `milkdim` e usuário `kaiki`, cada um com a senha que já usava.
- [x] Vendedores 0001, 0002 e 700122 marcados como admin: entram no Controle com o código e a senha de vendedor.
- [x] Builds gerados em `Downloads\GitHub\milkdim-builds`:
  - `MilkDim_Funcionario_2026-11-19.apk` — app dos vendedores
  - `MilkDim_Controle_2026-11-19.apk` — Controle no celular
  - `MilkDim_Controle_Windows_2026-11-19\milkdim_admin.exe` — Controle no computador

## Regra até o fim da troca

**Não cadastrar vendedor, não trocar senha e não ativar/desativar ninguém pelo Controle antigo.**
Essas mudanças não chegam às contas novas, e a fase 3 se recusa a rodar se encontrar diferença.

## 1. Teste com a conta 0001 (antes de mexer nos vendedores de verdade)

Num celular Android de teste, com internet:

- [ ] Instalar `MilkDim_Funcionario_2026-11-19.apk`.
- [ ] Entrar com código `0001` e a senha de sempre. Deve abrir a tela inicial.
- [ ] Fazer um pedido de teste e finalizar com internet. Conferir no Controle novo que ele aparece.
- [ ] Ligar o modo avião. Fazer outro pedido e finalizar. Deve aparecer
      "Pedido salvo. Será enviado quando houver internet." e, na tela inicial,
      "1 pedido aguardando envio".
- [ ] Tentar "Sair": deve ser recusado enquanto houver pedido aguardando.
- [ ] Fechar e abrir o app ainda em modo avião: deve abrir direto na tela inicial.
- [ ] Desligar o modo avião e tocar "Enviar agora". O aviso some e o pedido aparece no Controle.
- [ ] Apagar os dois pedidos de teste pelo Controle novo.

No computador:

- [ ] Abrir `milkdim_admin.exe` da pasta nova e entrar com o código de um admin (0001, 0002 ou 700122) e a senha dele.
- [ ] Ver as quatro abas carregando. Em Vendedores, abrir o 0001 e confirmar que o código não é editável.

## 2. Instalação para valer

Para cada vendedor (0002 e 0003), **com o celular na internet**:

- [ ] Abrir o app antigo uma última vez e anotar se ele mostra pedidos que não chegaram ao Controle.
- [ ] Instalar o APK novo **por cima** (não desinstalar — os pedidos guardados no celular ficam).
- [ ] Entrar com o código e a senha de sempre.
- [ ] Esperar a tela inicial mostrar **0 pedidos aguardando envio**. Se mostrar N > 0, tocar
      "Enviar agora" e esperar zerar.

Para as duas pessoas do Controle:

- [ ] Celular: instalar `MilkDim_Controle_2026-11-19.apk` por cima e entrar com o usuário
      (`kaiki` ou `milkdim`).
- [ ] Computador: substituir a pasta do Controle antigo pela pasta nova. O executável tem o
      mesmo nome (`milkdim_admin.exe`), então o atalho continua funcionando. Guardar a pasta
      antiga como backup.

## 3. Fechar o banco (fase 3)

Só depois de tudo acima. Avisar o Claude, que confere antes de aplicar:

- `auth.users.last_sign_in_at` depois da instalação para 0002, 0003, `kaiki` e `milkdim`;
- os vendedores batem com as contas (a própria fase 3 aborta se não baterem);
- o SQL é mostrado antes, e só aplicado com OK.

A partir da fase 3 o app antigo para de funcionar, e as senhas antigas são apagadas do banco.

## Depois da fase 3

- Não trocar senha nem desativar vendedor no meio do expediente: o app volta para a tela de
  login e um pedido em digitação (ainda não salvo) se perde.
- Para os pedidos e as etiquetas, identificar pedido por **vendedor + número**: números se
  repetem entre vendedores.
