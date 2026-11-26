# Implantação — Fase D (aba Financeiro no Controle, com painel em abas)

Roteiro da instalação, na ordem. Marque cada caixa ao terminar. **A ordem importa**: o banco
vem primeiro.

**Situação em 25/11/2026:** a migração do banco **já foi aplicada** em produção, com o OK do
dono (8 categorias, permissões ok, pedidos intactos). Falta só o Controle novo (seção 3) e o
teste (seção 4).

## Lembretes importantes

- **Banco antes do Controle.** A aba Financeiro pede duas tabelas novas (`categorias_saida` e
  `saidas`). Se o Controle novo for aberto num banco sem a migração, a aba mostra erro. A
  migração só acrescenta tabelas e não mexe nas existentes, então aplicá-la primeiro não
  atrapalha nenhum app instalado.
- **O app dos celulares não muda.** Nenhum vendedor precisa instalar nada nesta fase.
- **Só o Controle novo muda.** O Controle já é só para admins, então a aba Financeiro aparece só
  para admins. Um vendedor comum não vê as tabelas novas.
- **Esta fase só lê os pedidos.** Ela não altera nenhum pedido.
- **O painel novo não mexe no banco.** Ele só muda a tela do Controle: a aba Financeiro agora
  tem quatro abas (Resumo, Vendas, Saídas e Ano).
- Este roteiro **não** guarda endereço do banco, senhas nem nomes de clientes. Esses dados ficam
  só com o dono.

## O que a aba mostra (para explicar ao usuário)

No topo ficam o **seletor de mês** (setas e nome do mês) e o botão **Atualizar**. Abaixo vêm as
quatro abas. O mês escolhido vale para todas.

- **Resumo.** Três cartões: **Vendas** (com nº de pedidos e ticket médio), **Saídas** e
  **Resultado do mês** (com margem). Depois o gráfico **Resultado nos últimos 12 meses** e os
  **Destaques do mês**: **Produto campeão**, **Vendedor do mês** e **Maior gasto**. No mês atual
  aparece também **A receber**.
- **Vendas.** Três listas em barras: **Melhores clientes** (os 10 maiores, com o número de
  pedidos), **Vendas por produto** (com unidades) e **Vendas por vendedor**.
- **Saídas.** Aqui ficam os botões **Lançar saída** e **Categorias**. Mostra **Saídas por
  categoria** e **Saídas do mês** (a lista, para editar ou apagar).
- **Ano.** Gráfico de barras de Vendas e Saídas dos **12 meses que terminam no mês escolhido** e
  uma tabela com Mês, Vendas, Saídas, Resultado, Margem e Pedidos, mais a linha **Total**.

Regras que valem para as abas:

- **Vendas** contam quando o pedido é **entregue** (finalizado), no **mês da entrega**, na hora
  local. Pedido cancelado não conta.
- **A receber** mostra os pedidos prontos que ainda não foram entregues. Aparece só no **mês
  atual**.
- **Saídas** são os gastos lançados à mão, por categoria. Contam no mês da data da saída.
- **Resultado do mês** é Vendas menos Saídas. Se for negativo, aparece em vermelho.
- **Comparação com o mês anterior.** Cada cartão do Resumo mostra uma seta com a variação.
  **No mês atual, compara com os mesmos dias do mês anterior** (o mês ainda não acabou, então
  comparar com o mês inteiro seria injusto). Em mês encerrado, compara com o mês anterior
  inteiro. O cartão Saídas mostra sempre o total do mês inteiro; só a seta usa os mesmos dias.
  - **▲** = subiu, **▼** = desceu, **= 0%** = igual.
  - **Verde = melhora, vermelho = piora.** Vendas e resultado que sobem são melhora. Saída que
    sobe é piora.
  - No **Resultado**, se o sinal trocou, aparece **"virou positivo"** (verde) ou **"virou
    negativo"** (vermelho), sem porcentagem.
  - Se o mês anterior for zero, a seta **não aparece** (não dá para calcular).
- **"—" na tela.** Significa que não há dado:
  - na aba **Ano**, os meses sem pedido entregue nem saída (por exemplo, antes de ago/2025)
    aparecem com "—" em todas as colunas, sem barra no gráfico e com um buraco na curva do
    resultado. O **Total** soma só os meses com dado;
  - **ticket médio** sem pedidos, **margem** sem vendas e os **Destaques** sem dados também
    mostram "—".
- Nos meses até **novembro de 2026**, a tela mostra o aviso **"Até 23/11/2026, a data é a do
  pedido."** Os pedidos antigos eram finalizados na hora do pedido, não na entrega. Por isso,
  nesses meses a data usada é a do pedido.

## 1. Pré-requisito

- [ ] **Branch da Fase D mesclada.** O build do Controle sai da branch já mesclada.

## 2. Banco (primeiro de tudo)

**Esta seção já está feita.** A migração foi aplicada em produção em **25/11/2026**, com o OK
do dono. Os itens abaixo ficam como roteiro de **conferência**, para refazer quando quiser.

A migração é o arquivo `supabase/migrations/20261125000001_fase_d_saidas.sql`. O teste dela é
`supabase/tests/fase_d_test.sql`.

- [x] **1.** Mostrado o SQL ao dono. Em uma frase: cria a tabela de categorias de saída (com 8
      categorias iniciais) e a tabela de saídas, só para admin. Não apaga nem altera dados
      existentes.
- [x] **2.** Teste rodado **em rollback** no SQL Editor (`begin; <migração>; <teste>;
      rollback;`), sem erro.
- [x] **3.** Migração aplicada de verdade em **25/11/2026**, com o OK do dono.
- [x] **4.** Conferidas as **8 categorias** iniciais (para rever, abrir **Categorias** na aba
      **Saídas**), nesta ordem:
  1. Matéria-prima
  2. Embalagens
  3. Combustível/entrega
  4. Salários
  5. Aluguel/contas (água, luz, gás)
  6. Impostos
  7. Manutenção
  8. Outros
- [x] **5.** Conferido que **um vendedor comum não vê a tabela `saidas`**: com o login de um
      vendedor (não admin), a consulta à tabela não devolve linhas ou dá erro de permissão.
- [x] **6.** Conferido que os pedidos continuam intactos e o Controle atual (antigo) abre sem
      erro.

## 3. Controle novo na fábrica (depois do banco)

- [ ] Gerar o build do Controle Windows da branch mesclada e guardar em
      `Downloads\GitHub\milkdim-builds`, na pasta `MilkDim_Controle_Windows_<data>_faseD_painel`
      (com a data do dia, por exemplo `MilkDim_Controle_Windows_2026-11-25_faseD_painel`).
- [ ] Computador da fábrica: substituir a pasta do Controle antigo pela pasta nova. O executável
      continua `milkdim_admin.exe`, então o atalho funciona. Guardar a pasta antiga como backup.
- [ ] Abrir e entrar com o código de um admin e a senha dele. Conferir que existe a aba
      **Financeiro** e que ela mostra as quatro abas: **Resumo**, **Vendas**, **Saídas** e **Ano**.
- [ ] Celular Android do Controle (se for usado): instalar o APK novo do Controle **por cima**.
      Nunca desinstalar antes.

## 4. Teste no Controle

Use valores de teste e **apague as saídas de teste no fim**. Os pedidos não são tocados. Os
passos valem em qualquer data: "mês atual" é o mês em que você está testando.

- [ ] **1. Resumo, mês atual.** Abrir **Financeiro** (recarrega toda vez que é aberta). Deve abrir
      no mês atual, na aba **Resumo**, com os cartões **Vendas**, **Saídas** e **Resultado do
      mês**, o gráfico **Resultado nos últimos 12 meses**, os **Destaques do mês** e a seção
      **A receber** (só no mês atual). Conferir uma venda conhecida contra o Controle de pedidos.
- [ ] **2. Comparação.** Ainda no mês atual, olhar as setas abaixo dos cartões. Conferir que
      **▲** verde é melhora e **▼** vermelho é piora (Saídas é o contrário: subir é vermelho).
      Lembrar que **no mês atual compara com os mesmos dias do mês anterior**. Se o resultado
      trocou de sinal, aparece **"virou positivo"** ou **"virou negativo"**. Se o mês anterior
      não teve nada, a seta não aparece.
- [ ] **3. Vendas.** Tocar na aba **Vendas**. Conferir **Melhores clientes**, **Vendas por
      produto** e **Vendas por vendedor**. Um mês sem vendas mostra **"Sem registros no mês."**
- [ ] **4. Ano.** Tocar na aba **Ano**. Deve aparecer o gráfico de barras e a tabela dos 12 meses
      que terminam no mês da tela, com a linha **Total**. Meses sem pedido entregue nem saída
      aparecem com **"—"**, não com zero.
- [ ] **5. Mês de histórico.** Tocar em **Mês anterior** até um mês antigo. Deve aparecer o aviso
      **"Até 23/11/2026, a data é a do pedido."** e, no **Resumo**, **não** aparecer **A
      receber**. Um mês sem nada mostra R$ 0,00 (e ticket médio e margem com "—") e não dá erro.
      Voltar ao mês atual.
- [ ] **6. Lançar saída de teste.** Na aba **Saídas**, tocar em **Lançar saída**. Escolher a
      **Categoria**, digitar o **Valor** (ex.: `1.234,56`, `480,5` ou `R$ 480,00`), uma
      **Descrição** e a **Data**. Tocar em **Salvar**. A saída aparece em **Saídas do mês** e o
      **Resultado do mês** (aba **Resumo**) diminui no mesmo valor. Aparece o aviso **"Saída
      lançada em dd/MM/aaaa."**; se a data caiu em outro mês que não o da tela, o aviso diz em
      qual mês ela aparece (ex.: "Ela aparece em Novembro 2026.").
- [ ] **7. Editar.** Tocar na linha da saída. O diálogo abre como **Editar saída**. Mudar o valor,
      **Salvar** (aviso **"Saída alterada."**) e conferir que os totais mudaram.
- [ ] **8. Apagar.** Tocar no ícone de lixeira (**Apagar saída**). Aparece **"Apagar esta
      saída?"**, com categoria, data e valor da saída. Tocar em **Apagar** e conferir que sumiu
      e que os totais voltaram.
- [ ] **9. Categoria.** Na aba **Saídas**, tocar no ícone **Categorias**. Em **Nova categoria**,
      criar uma de teste (campo **Nome**, **Salvar**). Depois **Desativar** (ícone do olho): ela
      fica com **(desativada)** na lista. Abrir **Lançar saída** e conferir que ela **não**
      aparece na escolha. Tocar em **Reativar** se quiser voltar atrás.
- [ ] **10. Categoria com saídas.** Uma categoria que já tem saídas **só pode ser desativada**,
      nunca apagada. Desativada, ela some do lançamento, mas as saídas antigas continuam
      aparecendo com o nome dela nos meses passados.
- [ ] **11. Tela estreita (celular Android, se for usado).** Abrir cada aba. Nada deve ficar
      cortado. Na aba **Ano**, a tabela rola para o lado.

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

- **A aba mostra erro e o botão "Tentar de novo".** Se for só a internet, o botão resolve. Se
  continuar, conferir se a migração da Fase D está no banco (seção 2, já aplicada em 25/11/2026).
  O erro aparece igual em todas as quatro abas. A aba nunca mostra zeros no lugar de um erro.
- **O mês está vazio, mas o dono diz que vendeu.** Lembrar que a venda conta no mês da
  **entrega**, não do pedido. Um pedido pronto e ainda não entregue só aparece em **A receber**,
  no mês atual. Pedido cancelado não conta.
- **Aparece "—" em vez de zero.** É esperado: é mês sem dado (aba **Ano**), ou ticket/margem sem
  vendas.
- **A seta não aparece num cartão.** O mês anterior (ou os mesmos dias dele) estava zerado.
- **Nos meses antigos a venda "mudou de mês".** É esperado: até 23/11/2026 vale a data do
  pedido (aviso na tela).
- **Não vejo a aba Financeiro.** Conferir se o Controle aberto é o novo (`faseD_painel`) e se o login é
  de admin.
- **Uma categoria sumiu da lista de lançar.** Ela está desativada. Na aba **Saídas**, em **Categorias**,
  tocar em **Reativar**.
