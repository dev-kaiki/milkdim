# Implantação — Etiqueta por caixa

Roteiro da instalação, na ordem. Marque cada caixa ao terminar. **A ordem importa**: o banco
vem primeiro, depois o Controle novo. O app dos celulares **não muda**.

## Lembretes importantes

- **Banco antes do Controle.** Enquanto o banco não tem a migração, o Controle novo continua
  imprimindo a etiqueta única de sempre e mostra o aviso **"Caixas indisponíveis; imprimindo
  etiqueta única."** Nada quebra, mas as caixas só funcionam depois da migração.
- **O app dos celulares não muda.** Não é preciso instalar APK novo nos vendedores.
- **A migração só é aplicada com o OK do dono**, dado no chat.
- Este roteiro **não** guarda endereço do banco, senhas nem nomes de clientes. Esses dados ficam
  só com o dono. Quando o texto diz "o banco (Supabase)", é o mesmo banco dos outros roteiros.

## 1. Banco (primeiro de tudo)

A migração é o arquivo `supabase/migrations/20261126000001_etiqueta_caixas.sql`. O teste dela é
`supabase/tests/etiqueta_caixas_test.sql`. O teste já rodou dentro de uma transação desfeita
(26/11/2026) e passou, inclusive com a migração aplicada uma segunda vez (ela pode ser
repetida sem estragar nada). Ainda **não foi aplicada**.

- [ ] **1.** Abrir o arquivo da migração e mostrar o SQL ao dono. Explicar em uma frase: cria a
      tabela de tipos de caixa, a tabela das caixas montadas por pedido, a coluna "tipo de caixa"
      em cada produto e a função que salva as caixas. Não apaga nem altera pedidos.
- [ ] **2.** Rodar o teste `etiqueta_caixas_test.sql` **em rollback** (a transação é desfeita no
      fim e nada fica gravado). Conferir que terminou sem erro.
- [ ] **3.** Só depois do **OK do dono**, aplicar a migração.
- [ ] **4.** Conferir o resultado (seção 2).

## 2. Conferir os tipos e os produtos (logo depois do banco)

Consultas de conferência, em palavras (rodar no banco (Supabase), só leitura):

- [ ] **Tipos de caixa.** Tem que haver **3 tipos**, todos ativos e com mistura de sabores
      ligada: **Pote** (cabem 16), **Copo** (cabem 20) e **Médio** (cabem 4).
- [ ] **Produtos ligados sozinhos.** A migração liga o tipo pelo nome do produto, só nos casos
      claros:
  - nome que **começa com "Pote"** e tem **"160g"** → **Pote**;
  - nome que **começa com "Copo"** → **Copo**;
  - nome que **começa com "550g"** → **Médio**.
- [ ] **Produtos sem tipo.** Listar os produtos com o tipo de caixa vazio. Todo o resto fica
      assim de propósito. Exemplos que devem aparecer sem tipo: grande 1100g, geladinho, pacote
      c/30, pudim de vidro 40 ml, Pudim Pote, Pote Pró Vida.
- [ ] **Definir os que faltam, no Controle.** Aba **Produtos**, abrir o produto, campo **Tipo
      de caixa**. As opções são os tipos ativos e **"Sem caixa (avulso)"**. Salvar. Na lista, o
      produto passa a mostrar **"Caixa: Copo (20)"** (ou o tipo escolhido).
- [ ] **Tipos novos ou ajustes.** Na aba **Produtos**, botão **Tipos de caixa**. Cada tipo tem
      **Nome**, **Capacidade (unidades)**, **Misturar sabores na mesma caixa** e **Ativo**.
      Capacidade zero ou vazia dá **"Capacidade inválida."** Nome repetido dá **"Já existe um tipo
      de caixa com esse nome."**
- Produto sem tipo, ou com tipo desativado, **vai para os avulsos** na hora de montar as caixas.
  Não dá erro.

## 3. Controle novo na fábrica (depois do banco)

- [ ] Gerar o build do Windows da branch mesclada e guardar em `Downloads\GitHub\milkdim-builds`
      com a pasta `MilkDim_Controle_Windows_<data>_caixas` (exemplo:
      `MilkDim_Controle_Windows_2026-11-26_caixas`).
- [ ] Computador da fábrica: substituir a pasta do Controle antigo pela pasta nova. O executável
      tem o mesmo nome (`milkdim_admin.exe`), então o atalho continua funcionando. Guardar a
      pasta antiga como backup.
- [ ] Abrir, entrar como admin e conferir que a aba **Produção** abre sem erro.
- [ ] A impressora e o tamanho da etiqueta continuam como na Fase B (engrenagem da aba Produção).
      Nada novo aqui.

## 4. Como funciona (para explicar ao dono)

Ao imprimir a etiqueta de um pedido (**Imprimir etiqueta** na aba Produção ou no detalhe do
pedido, ou **Agora** em "Imprimir a etiqueta agora?"), abre a tela **"Volumes do pedido"**, com
as caixas já sugeridas:

- cada tipo de caixa enche até a capacidade; a sobra **nunca vira caixa parcial**: vai para os
  **avulsos**, que formam um único volume e saem **por último**;
- com a mistura de sabores ligada, a caixa cheia pode ter sabores diferentes; desligada, cada
  produto enche só as próprias caixas;
- **pote e copo nunca se misturam** na mesma caixa;
- os rótulos são **"Caixa 1/3 · Copo"**, **"Avulsos 3/3"** e, no pedido solto, **"Pedido solto"**.

Na tela dá para: ligar **"Pedido solto (sem caixas)"**, **"Nova caixa"**, **"Apagar caixa"**,
**"Adicionar produto"**, mudar a quantidade de cada linha e remover linhas. O botão **Imprimir**
só libera quando a soma de cada produto bate com o pedido. **Cancelar** fecha sem imprimir.

Caixa com mais unidades que a capacidade só mostra um aviso: não bloqueia.

Ao tocar **Imprimir**, as caixas ficam salvas no banco e sai **um único PDF** com uma etiqueta
por volume (cada uma só com os itens daquele volume, e o mesmo QR do pedido). Depois vem a
pergunta **"As etiquetas saíram certas?"**: **Sim** (marca como impressa), **Imprimir de novo**
(escolher **Todas** ou um volume) ou **Cancelar**. Só **Sim** marca a etiqueta como impressa.

## 5. Teste de ponta a ponta

Precisa de um pedido de teste e da impressora funcionando. **Não apagar nada no fim.**

- [ ] **1. Pedido de 50 copos.** Criar um pedido com **50 copos de um só sabor** (produto com
      tipo Copo) e deixá-lo **pronto** (**Produção concluída**). Tocar **Imprimir etiqueta**. A
      tela deve sugerir **3 volumes**: **Caixa 1/3 · Copo** (20), **Caixa 2/3 · Copo** (20) e
      **Avulsos 3/3** (10). Imprimir: saem **3 etiquetas** num PDF, cada uma só com os itens do
      seu volume e o mesmo QR. Responder **Sim**.
- [ ] **2. Mistura de sabores.** Pedido com **dois sabores de copo** (por exemplo 30 + 30).
      Com a mistura ligada, a primeira caixa vem cheia atravessando os sabores. Depois, no
      diálogo **Tipos de caixa**, desligar **Misturar sabores na mesma caixa** do Copo e repetir:
      cada sabor enche só as próprias caixas e o resto vai para os avulsos. Ligar de novo no fim.
- [ ] **3. Pedido solto.** Abrir a tela de volumes de um pedido e ligar **"Pedido solto (sem
      caixas)"**. Sai **uma** etiqueta, **"Pedido solto"**, sem numeração.
- [ ] **4. Reimprimir só um volume.** No pedido do passo 1, tocar **Imprimir etiqueta** de novo
      (as caixas salvas voltam como estavam). Imprimir, e em **"As etiquetas saíram certas?"**
      tocar **Imprimir de novo** e escolher **"Volume 2/3 · Caixa 2/3 · Copo"**. Sai só a
      etiqueta da caixa 2/3.
- [ ] **5. Pedido alterado depois.** Com as caixas salvas do passo 1, o vendedor altera uma
      quantidade e reenvia o pedido, e a fábrica dá **Produção concluída** de novo. Ao tocar
      **Imprimir etiqueta**, a tela mostra o aviso **"O pedido mudou depois que as caixas foram
      montadas."** com uma **nova sugestão**. As caixas antigas são ignoradas.
- [ ] **6. Soma errada.** Na tela de volumes, tirar uma unidade de um produto. Aparece o erro
      do tipo **"Copo …: faltam 1"** e o botão **Imprimir** fica bloqueado. Devolver a unidade:
      libera.
- [ ] **7. Pedido entregue (só leitura).** Para um pedido **já entregue** com caixas salvas, a
      tela de volumes abre **sem edição** (sem "Pedido solto", "Nova caixa" nem "Apagar caixa") e
      reimprime as caixas salvas. Entregue **sem** caixas salvas: sai a etiqueta única de antes.
      Pedido cancelado não imprime. Hoje o botão **Imprimir etiqueta** só aparece para pedido
      **pronto**; se o botão não estiver disponível para um entregue, este passo não se aplica
      na tela (fica coberto pelos testes automáticos).
- [ ] **8. Etiqueta pequena.** Se usarem 60 × 40 mm, testar um volume com muitos itens: o
      conteúdo passa para mais páginas, sem perder item, e o rótulo do volume aparece em todas.

## 6. Mensagens e o que fazer

| Mensagem | O que significa / o que fazer |
|---|---|
| Caixas indisponíveis; imprimindo etiqueta única. | O Controle não leu os tipos ou as caixas do banco. Se aparece sempre, a migração ainda não foi aplicada (seção 1). Se aparece só às vezes, internet fraca: imprimir de novo. A etiqueta única sai normalmente. |
| O pedido mudou depois que as caixas foram montadas. | Aviso (amarelo). O vendedor alterou o pedido depois de salvas as caixas. A tela já vem com uma nova sugestão: conferir e imprimir. |
| As caixas não batem com o pedido. | O banco recusou salvar: a soma por produto é diferente do pedido (alguém alterou o pedido nesse meio tempo). Voltar, atualizar a tela e tentar de novo. |
| Este pedido não pode ter as caixas alteradas. | O pedido já foi entregue ou cancelado. Só se reimprime o que já estava salvo. |
| Erro ao salvar as caixas. | Falha geral ao gravar. Tentar de novo; se continuar, ver internet e o banco. |
| Sem permissão para essa ação. | O usuário não é admin. Entrar com um código de admin. |
| Capacidade inválida. | No diálogo de tipo de caixa: informar um número maior que zero. |
| Já existe um tipo de caixa com esse nome. | Escolher outro nome ou editar o tipo que já existe. |
| Informe o nome | Falta o nome do tipo de caixa. |
| (produto): faltam N / sobram N | Na tela de volumes: a soma das caixas está diferente do pedido. Ajustar até zerar; o Imprimir só libera então. |
| Caixa N está vazia / Avulsos está vazio | Volume sem itens. Apagar a caixa ou colocar produto nela. |
| Caixa N/M tem X unidades (cabem Y) | Aviso. Não bloqueia: só diz que a caixa passa da capacidade. |
| Produto salvo, mas o tipo de caixa não foi gravado: … | No cadastro de Produtos, o produto foi salvo mas o tipo falhou. Abrir o produto de novo e escolher o tipo. |

## 7. Problemas comuns

- **Sempre aparece "Caixas indisponíveis".** A migração não foi aplicada ou o Controle está sem
  internet. Conferir a seção 1.
- **Todo produto vai para os avulsos.** Os produtos estão sem tipo. Conferir a seção 2 e definir
  em **Produtos, Tipo de caixa**.
- **Um produto novo não entra em caixa.** Produto criado depois da migração nasce sem tipo.
  Definir o tipo no cadastro.
- **Pedido com dois nomes quase iguais.** A conferência soma pelo nome do item, sem diferenciar
  maiúsculas nem espaços nas pontas. Duas linhas do mesmo produto entram na mesma conta.
- **Impressora, tamanho da etiqueta e QR.** Iguais à Fase B (`docs/implantacao-fase-b.md`).

## 8. Combinar com o cliente (perguntas em aberto)

- [ ] **Mistura de sabores:** hoje vem **ligada** nos três tipos. Pode ser desligada por tipo
      (diálogo **Tipos de caixa**). Confirmar se é isso mesmo que a fábrica quer.
- [ ] **Pote e copo** nunca são misturados na mesma caixa, de propósito. Confirmar.
- [ ] **Geladinho, pacote e pudim de vidro** ficam **avulsos** até o cliente definir a caixa
      de cada um. Quando definir, criar o tipo e ligar os produtos (seção 2).
