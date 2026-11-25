# Fase D (parte 1): Financeiro: resultado de vendas e saídas

Data: 25/11/2026. Aprovado na conversa com o Kaiki.

## Por quê

Nos áudios de 20/11, o Janderson pediu uma aba de financeiro com duas coisas:

- o **resultado de vendas**;
- um campo para a esposa **lançar todas as saídas** de dinheiro.

Hoje o Controle não tem nada disso: os pedidos guardam o total, mas ninguém vê quanto a
fábrica vendeu no mês, nem quanto gastou.

Esta é a parte da Fase D que **não depende da Fase C** (a forma de cobrança). Ela começa
agora porque a Fase C espera uma resposta do Janderson: a escolha entre dinheiro, cupom e
nota é feita ao terminar a fabricação ou depois da entrega?

## Objetivos

1. Uma aba **Financeiro** no Controle, que mostra o resultado de um mês:
   - **Vendas** do mês, em R$, com o número de pedidos.
   - **Saídas** do mês, em R$.
   - **Resultado** do mês: vendas − saídas.
   - **Vendas por vendedor**, em R$.
   - **Vendas por produto**, em unidades e em R$.
   - **Saídas por categoria**, em R$.
   - **A receber**: quantos pedidos estão prontos e ainda não foram entregues, e o valor
     somado. Esse quadro não entra no resultado.
     - **Mês atual:** o quadro é a situação de **agora**, então só aparece no mês atual.
     - **Meses passados:** o quadro não aparece. Decisão minha: o banco não guarda o que
       estava pronto num mês passado.
2. Navegar entre os meses (◀ ▶), inclusive pelos meses antigos, desde agosto de 2025.
3. **Lançar uma saída**: data, categoria, descrição e valor. Também deve ser possível
   corrigir e apagar uma saída.
4. **Categorias** de saída editáveis, começando com estas: Matéria-prima, Embalagens,
   Combustível/entrega, Salários, Aluguel/contas (água, luz, gás), Impostos, Manutenção,
   Outros.
5. Registrar **quem lançou e quando** cada saída, e quem a alterou por último.

## Regras de conta (decididas pelo Kaiki)

- **Quando a venda conta:** o pedido conta como venda quando está **entregue**, ou seja,
  `status = 'finalizado'`. Isso vale também para a finalização manual. A venda entra no
  mês de `finalizado_em`.
- **Pedido cancelado** não conta.
- **Pedidos `salvo`** (em aberto) não aparecem no financeiro.
- **Pedidos `pronto`** aparecem só no quadro "A receber".
- **Mês no horário local:** o mês é contado na hora local do Brasil. Um pedido entregue às
  22h do dia 30 conta naquele mês, mesmo que em UTC já seja o mês seguinte.
- **Meses antigos (decisão minha):**
  - **Data usada:** até a Fase A (23/11/2026), o `finalizado_em` dos pedidos antigos foi
    preenchido com a data do pedido (`coalesce(datahora, created_at, enviado_em)`). No
    app antigo, o pedido era assinado e finalizado na hora em que era feito. Por isso, no
    histórico, "mês da entrega" é na prática o mês do pedido.
  - **Aviso na tela:** é aceito sem ajuste. Os meses até novembro de 2026 mostram uma
    linha pequena: "Até 23/11/2026, a data é a do pedido."
- **Reentrega (decisão minha):** a entrega assinada sobre um pedido cancelado ou
  finalizado manual troca o `finalizado_em` para a nova data. O pedido passa para o mês
  da reentrega, e o mês antigo diminui. É aceito: o mês sempre segue o `finalizado_em`
  atual, e não existe "mês fechado".
- **Valor da venda:** o `total` do pedido. Conferido em 25/11: nos 372 pedidos, o total é
  igual à soma de quantidade × preço dos itens, e todos têm `finalizado_em`.
- **Vendas por produto:** agrupa pelo **nome** do item, que vem no jsonb `produtos`, com
  as chaves `nome`, `preco`, `quantidade` e `subtotal`. O pedido não guarda código de
  produto. Se um produto mudou de nome, ele aparece em duas linhas. Isso é aceito.
- **Vendas por vendedor:** mostra o nome do vendedor, e o código quando não há nome. Segue
  a mesma regra da etiqueta.
- **Saídas:** a saída conta no mês da sua **data**, que é a data informada, não a data em
  que foi lançada.

## Fora do escopo

- **Forma de cobrança** (dinheiro, cupom ou nota): fica para a Fase C. Quando ela chegar,
  entra no relatório como mais um quadro, "Vendas por cobrança".
- **Contas a receber detalhadas:** prazos, Pix, boleto, quem pagou e quem não pagou. O
  Janderson não pediu.
- **Emissão fiscal:** fica para a Fase E.
- **DRE formal**, com impostos sobre a venda e custo da mercadoria: por enquanto o
  resultado é só vendas − saídas.
- **Exportar** para planilha ou PDF.
- **Estoque.**
- **O financeiro no app do vendedor:** ele fica só no Controle.

## Não pode acontecer

- **Vendedor sem acesso às saídas:** um vendedor comum (não administrador) não pode ler
  nem gravar saídas, nem pelo app nem chamando a API direto.
- **Resultado errado em silêncio:** se a busca falhar, a tela mostra o erro e não zeros.
- **Pedidos intocados:** a fase não altera nenhum pedido. Ela só lê.

## Caminho escolhido

O Kaiki escolheu **calcular no Controle**.

| Caminho | Como | Por que sim / não |
|---|---|---|
| **1. Calcular no Controle** (escolhido) | O banco ganha só as tabelas de saídas e de categorias. O Controle baixa os pedidos do mês e faz as contas em Dart. | A mudança no banco de produção é pequena, as contas ficam testadas com `flutter test` e o fuso local sai certo. O contra: as contas não podem ser reaproveitadas fora do Controle. |
| 2. Calcular no banco | O banco ganha as mesmas tabelas e uma função que devolve o resultado pronto. | Concentra as contas num lugar só, mas cada ajuste vira uma migração em produção. Nada hoje pede reaproveitamento. |

## Desenho

### Banco: uma migração nova, `supabase/migrations/2026112500000x_fase_d_saidas.sql`

**`public.categorias_saida`**

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | bigint identity | chave primária |
| `nome` | text | obrigatório, único sem diferenciar maiúsculas de minúsculas |
| `ativa` | boolean | padrão `true` |
| `ordem` | int | ordena a lista |

A migração cria as 8 categorias iniciais.

**Excluir categoria:** uma categoria **não é apagada** se tiver saídas. Ela é desativada e
some da lista ao lançar, mas continua aparecendo nos meses antigos.

**`public.saidas`**

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | bigint identity | chave primária |
| `data` | date | obrigatório |
| `categoria_id` | bigint | obrigatório; referencia `categorias_saida`, sem apagar em cascata |
| `descricao` | text | pode ficar vazia |
| `valor` | numeric(12,2) | obrigatório, maior que 0 |
| `criado_em`, `criado_por` | | preenchidos pelo gatilho |
| `alterado_em`, `alterado_por` | | preenchidos pelo gatilho |

- **Auditoria:** quem fez a ação é `public.app_autor_pedido()`, a mesma função das fases
  anteriores. Ela devolve o código do vendedor logado e, para um administrador que não é
  vendedor, o e-mail do login. Num SQL Editor, sem login, o autor fica NULL, e isso é
  aceito.
  - **Quem preenche:** o gatilho preenche os campos `*_por` e `*_em`, e o cliente não
    consegue forjar esses valores.
  - **Permissão do gatilho:** a função do gatilho precisa ser `security definer` com
    `set search_path = ''`, porque `app_autor_pedido()` não tem `execute` para
    `authenticated`.
- **Índice:** em `saidas(data)`.
- **Acesso:** RLS nas duas tabelas. Ler, inserir, alterar e apagar só com
  `public.app_is_admin()`. O `anon` não tem acesso nenhum.
- **Apagar uma saída:** é um `delete` real, permitido só para administrador. A saída não
  vira pedido nem nota, então não há o que preservar. Se aparecer essa necessidade, dá
  para trocar por uma marcação de apagada.

A migração é testada como nas fases anteriores:

- um teste SQL em `supabase/tests/fase_d_test.sql`, rodado em rollback contra a produção;
- depois disso, ela só é aplicada com o OK do Kaiki no chat.

### Controle

**Serviço** (`admin/lib/services/supabase_service.dart` ou um serviço novo de
financeiro):

- `buscarPedidosEntreguesEntre(DateTime inicioLocal, DateTime fimLocal)`: busca
  `status = 'finalizado'` com `finalizado_em` no intervalo. As bordas locais são
  convertidas para UTC.
  - Não traz as colunas de assinatura (`colunasPedidoSemAssinatura`).
  - **Paginação:** pagina com `.range` em blocos de 1000, como o resto do serviço, para
    não depender do limite de linhas do PostgREST.
- `buscarPedidosProntos()`: busca `status = 'pronto'` para o quadro "A receber". Pode
  reaproveitar `buscarPedidosEmAberto` filtrando por pronto.
- Listar, inserir, alterar e apagar saídas do mês. Listar, criar, renomear e desativar
  categorias.

**Contas** (`admin/lib/financeiro/resumo_financeiro.dart`):

- Uma função pura, `ResumoMes resumirMes(List<Pedido> entregues, List<Pedido> prontos,
  List<Saida> saidas)`, sem rede. Ela devolve:
  - total de vendas e número de pedidos;
  - vendas por vendedor;
  - vendas por produto (unidades e R$);
  - saídas totais e por categoria;
  - resultado;
  - a receber (quantidade e valor).
- **Ordem das listas:** cada lista vem do maior valor para o menor.
- **Precisão:** o dinheiro é somado em centavos inteiros, para não acumular erro de ponto
  flutuante.

**Tela** (`admin/lib/tabs/financeiro_tab.dart`):

- Sexta aba, **Financeiro**. O Controle já só abre para administradores.
- **Cabeçalho:** o seletor de mês, que abre no mês atual.
- **Resumo:** três números grandes, Vendas, Saídas e Resultado. O resultado negativo
  aparece em destaque.
- **Quadros:** por vendedor, por produto, por categoria e a receber.
- **Saídas do mês:** a lista das saídas, com editar e apagar (apagar pede confirmação), e
  o botão **+ Lançar saída**.
- **Lançar saída:** um diálogo com data (padrão hoje), categoria, descrição e valor. O
  valor aceita vírgula ("480,00"), e a data não pode ficar mais de um ano no futuro.
- **Categorias:** a gestão fica num botão da própria aba, com criar, renomear e desativar.
- **Visual:** usa os componentes de `packages/milkdim_ui`, como as outras abas.
- **Estados:** a tela tem estado de carregando, de erro (com "Tentar de novo") e de mês
  vazio.

## Deixado para quem constrói

- **Layout:** a posição exata dos quadros, e se eles ficam em duas colunas na tela larga
  e em uma na estreita.
- **Formato de moeda:** o mesmo usado nas outras telas do Controle.
- **Sem tempo real:** a aba atualiza ao abrir, ao trocar de mês e no botão Atualizar.
