# Implantação — Fase D (aba Financeiro no Controle)

Roteiro da instalação, na ordem. Marque cada caixa ao terminar. **A ordem importa**: o banco
vem primeiro.

## Lembretes importantes

- **Banco antes do Controle.** A aba Financeiro pede duas tabelas novas (`categorias_saida` e
  `saidas`). Se o Controle novo for aberto num banco sem a migração, a aba mostra erro. A
  migração só acrescenta tabelas e não mexe nas existentes, então aplicá-la primeiro não
  atrapalha nenhum app instalado.
- **O app dos celulares não muda.** Nenhum vendedor precisa instalar nada nesta fase.
- **Só o Controle novo muda.** O Controle já é só para admins, então a aba Financeiro aparece só
  para admins. Um vendedor comum não vê as tabelas novas.
- **Esta fase só lê os pedidos.** Ela não altera nenhum pedido.
- Este roteiro **não** guarda endereço do banco, senhas nem nomes de clientes. Esses dados ficam
  só com o dono.

## O que a aba mostra (para explicar ao usuário)

- **Vendas** contam quando o pedido é **entregue** (finalizado), no **mês da entrega**, na hora
  local. Pedido cancelado não conta.
- **A receber** mostra os pedidos prontos que ainda não foram entregues. Aparece só no **mês
  atual**.
- **Saídas** são os gastos lançados à mão, por categoria.
- **Resultado do mês** é Vendas menos Saídas. Se for negativo, aparece com sinal de menos em
  destaque.
- Nos meses até **novembro de 2026**, a aba mostra o aviso **"Até 23/11/2026, a data é a do
  pedido."** Os pedidos antigos eram finalizados na hora do pedido, não na entrega. Por isso,
  nesses meses a data usada é a do pedido.

## 1. Pré-requisito

- [ ] **Branch da Fase D mesclada.** O build do Controle sai da branch já mesclada.

## 2. Banco (primeiro de tudo)

A migração é o arquivo `supabase/migrations/20261125000001_fase_d_saidas.sql`. O teste dela é
`supabase/tests/fase_d_test.sql`.

- [ ] **1.** Abrir o arquivo da migração e mostrar o SQL ao dono. Explicar em uma frase: cria a
      tabela de categorias de saída (com 8 categorias iniciais) e a tabela de saídas, só para
      admin. Não apaga nem altera dados existentes.
- [ ] **2.** Rodar o teste **em rollback**, no SQL Editor do banco (Supabase), tudo numa
      execução só: `begin; <migração>; <teste>; rollback;`. A transação é desfeita no fim e
      nada fica gravado. Conferir que terminou sem erro.
- [ ] **3.** Só depois do **OK do dono**, aplicar a migração de verdade.
- [ ] **4.** Conferir as **8 categorias** iniciais, nesta ordem:
  1. Matéria-prima
  2. Embalagens
  3. Combustível/entrega
  4. Salários
  5. Aluguel/contas (água, luz, gás)
  6. Impostos
  7. Manutenção
  8. Outros
- [ ] **5.** Conferir que **um vendedor comum não vê a tabela `saidas`**: com o login de um
      vendedor (não admin), a consulta à tabela não devolve linhas ou dá erro de permissão.
- [ ] **6.** Conferir que o Controle atual (antigo) continua abrindo sem erro.

## 3. Controle novo na fábrica (depois do banco)

- [ ] Gerar o build do Controle Windows da branch mesclada e guardar em
      `Downloads\GitHub\milkdim-builds`, na pasta `MilkDim_Controle_Windows_<data>_faseD`
      (com a data do dia).
- [ ] Computador da fábrica: substituir a pasta do Controle antigo pela pasta nova. O executável
      continua `milkdim_admin.exe`, então o atalho funciona. Guardar a pasta antiga como backup.
- [ ] Abrir e entrar com o código de um admin e a senha dele. Conferir que existe a aba
      **Financeiro**.
- [ ] Celular Android do Controle (se for usado): instalar o APK novo do Controle **por cima**.
      Nunca desinstalar antes.

## 4. Teste no Controle

Use valores de teste e **apague as saídas de teste no fim**. Os pedidos não são tocados.

- [ ] **1. Mês atual.** Abrir **Financeiro**. Deve abrir em novembro de 2026, com **Vendas**,
      **Saídas** e **Resultado do mês**, e os quadros "Vendas por vendedor", "Vendas por
      produto" e "Saídas por categoria". Aparece a seção **A receber** (só no mês atual).
      Conferir uma venda conhecida contra o Controle de pedidos.
- [ ] **2. Mês de histórico.** Tocar em **Mês anterior** até um mês de 2025. Deve aparecer o
      aviso **"Até 23/11/2026, a data é a do pedido."** e **não** aparecer **A receber**. Um
      mês sem nada mostra R$ 0,00 e não dá erro.
- [ ] **3. Lançar saída de teste.** Voltar ao mês atual e tocar em **Lançar saída**. Escolher a
      **Categoria**, digitar o **Valor** (ex.: `1.234,56`, `480,5` ou `R$ 480,00`), uma
      **Descrição** e a **Data**. Tocar em **Salvar**. A saída aparece em **Saídas do mês** e o
      **Resultado do mês** diminui no mesmo valor.
- [ ] **4. Editar.** Tocar na linha da saída. O diálogo abre como **Editar saída**. Mudar o valor,
      **Salvar** e conferir que os totais mudaram.
- [ ] **5. Apagar.** Tocar no ícone de lixeira (**Apagar saída**). Aparece **"Apagar esta
      saída?"**. Tocar em **Apagar** e conferir que sumiu e que os totais voltaram.
- [ ] **6. Categoria.** Tocar no ícone **Categorias**. Em **Nova categoria**, criar uma de teste
      (campo **Nome**, **Salvar**). Depois **Desativar** (ícone do olho): ela fica com
      **(desativada)** na lista. Abrir **Lançar saída** e conferir que ela **não** aparece na
      escolha. Tocar em **Reativar** se quiser voltar atrás.
- [ ] **7. Categoria com saídas.** Uma categoria que já tem saídas **só pode ser desativada**,
      nunca apagada. Desativada, ela some do lançamento, mas as saídas antigas continuam
      aparecendo com o nome dela nos meses passados.

## 5. Mensagens que podem aparecer e o que fazer

| Mensagem | O que significa / o que fazer |
|---|---|
| Valor inválido. | O valor está vazio, zero, negativo, com letras ou com mais de duas casas decimais. Digitar como `1.234,56` ou `480,5`. |
| Escolha a categoria. | Falta escolher a **Categoria** no diálogo. |
| Data muito no futuro. | A data passa de 365 dias a partir de hoje. Provável erro de digitação do ano. Corrigir a data. |
| Informe o nome. | O nome da categoria está vazio. Digitar um nome. |
| Já existe uma categoria com esse nome. | Escolher outro nome, ou reativar a categoria que já existe (pode estar desativada). |
| Essa categoria tem saídas; desative em vez de apagar. | O banco recusou apagar. Usar **Desativar** em vez disso. |
| Sem permissão para essa ação. | O login não é de admin. Entrar com um admin. |
| Erro ao acessar o financeiro. | Falha no banco. Tentar de novo. Se continuar, ver a seção 6. |
| Erro ao carregar o financeiro: ... | A aba não conseguiu carregar. Tocar em **Tentar de novo**. |

## 6. Problemas comuns

- **A aba mostra erro e o botão "Tentar de novo".** Quase certo que o banco ainda não recebeu a
  migração da Fase D (seção 2). Aplicá-la e tocar em **Tentar de novo**. Se for só a internet, o
  mesmo botão resolve. A aba nunca mostra zeros no lugar de um erro.
- **O mês está vazio, mas o dono diz que vendeu.** Lembrar que a venda conta no mês da
  **entrega**, não do pedido. Um pedido pronto e ainda não entregue só aparece em **A receber**,
  no mês atual. Pedido cancelado não conta.
- **Nos meses antigos a venda "mudou de mês".** É esperado: até 23/11/2026 vale a data do
  pedido (aviso na tela).
- **Não vejo a aba Financeiro.** Conferir se o Controle aberto é o novo (`faseD`) e se o login é
  de admin.
- **Uma categoria sumiu da lista de lançar.** Ela está desativada. Em **Categorias**, tocar em
  **Reativar**.
