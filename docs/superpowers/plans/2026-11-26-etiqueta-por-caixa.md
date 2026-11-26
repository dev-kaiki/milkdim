# Etiqueta por caixa — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dividir o pedido em volumes (caixas cheias por tipo e um volume de avulsos), deixar a fábrica ajustar e imprimir uma etiqueta por volume ("Pedido 448 · Caixa 1/3"), guardando os volumes no banco.

**Architecture:**
- **Banco:** ganha `tipos_caixa`, `produtos.tipo_caixa_id` e `pedido_volumes`. A tabela de volumes é gravada só pela RPC `pedido_salvar_volumes`, que confere as somas no servidor.
- **Regras:** a sugestão, a conferência e os rótulos são funções puras em Dart.
- **Telas:** a tela "Volumes do pedido" substitui a impressão direta nos dois pontos que imprimem hoje (Produção e detalhe do pedido). O PDF ganha uma página (ou mais) por volume.

**Tech Stack:** Flutter 3.41 / Dart 3.11 (Windows), supabase_flutter, pdf/printing, Postgres no Supabase.

**Spec:** `docs/superpowers/specs/2026-11-25-etiqueta-por-caixa-design.md`

## Global Constraints

- **Repositório público:** nenhuma senha, chave, URL ou ref do Supabase em arquivo versionado. Nada de nomes de clientes.
- **Migração:** o teste SQL roda antes em `begin … rollback` (pelo controlador). A migração só é aplicada com OK do Kaiki no chat.
- **Tipos iniciais:** `Pote` (capacidade 16), `Copo` (20) e `Médio` (4). Todos com `mistura_sabores = true` e `ativo = true`.
- **Ligação inicial pelo nome** (`btrim`, sem diferenciar maiúsculas), só nos casos claros:
  - nome que começa com "pote" **e** contém "160g" → Pote;
  - nome que começa com "copo" → Copo;
  - nome que começa com "550g" → Médio.
  - O resto fica sem tipo.
- **Acesso:**
  - `tipos_caixa` e `pedido_volumes`: só administrador lê (RLS com `public.app_is_admin()`); o `anon` não tem acesso.
  - `tipos_caixa`: só administrador escreve.
  - `pedido_volumes`: ninguém escreve direto; só a RPC.
  - `produtos.tipo_caixa_id`: segue as políticas atuais de `produtos`, em que todos os autenticados leem e só administrador altera.
- **RPC `pedido_salvar_volumes(p_id bigint, p_solto boolean, p_volumes jsonb)`:**
  - **Tipo:** `security definer`, `set search_path = ''`, executável só por `authenticated`.
  - **Formato de `p_volumes`:** array de objetos `{"tipo": "caixa"|"avulso", "caixa": text|null, "itens": [{"nome": text, "quantidade": int}]}`.
  - **Erros:**
    - não admin → `42501`;
    - pedido inexistente → `P0002`;
    - status diferente de `salvo` ou `pronto` → `MD010` ("Este pedido não pode ter as caixas alteradas.");
    - formato inválido, volume vazio ou quantidade ≤ 0 → `22023`;
    - soma por nome (com `btrim`) diferente dos itens do pedido → `MD011` ("As caixas não batem com o pedido.").
  - **Se `p_solto` for true:** `p_volumes` tem que ter exatamente 1 volume, do tipo `avulso`.
  - **Gravação:** um upsert em `pedido_volumes` com `pedido_alterado_em = pedidos.alterado_em`, `salvo_em = now()` e `salvo_por = public.app_autor_pedido()`.
- **Sugestão:**
  - os tipos entram na ordem do primeiro item de cada tipo no pedido, e os itens na ordem do pedido;
  - com a mistura ligada, as caixas cheias atravessam os sabores;
  - com a mistura desligada, cada produto enche só as próprias caixas;
  - a sobra nunca vira caixa parcial e vai para os avulsos;
  - os avulsos formam um único volume, sempre **por último**;
  - produto sem tipo, com tipo inativo ou não encontrado vai para os avulsos.
- **Ligação de item a produto:** pelo nome com `trim` e sem diferenciar maiúsculas. Com vários produtos de mesmo nome, vale o ativo de menor `id`; se não houver ativo, o inativo de menor `id`.
- **Rótulo dos volumes:**
  - **caixa:** `Caixa i/n · <tipo>`;
  - **avulsos:** `Avulsos i/n`;
  - **pedido solto:** `Pedido solto`, sem numeração;
  - **pedido só com avulsos:** `Avulsos 1/1`;
  - o `n` conta todos os volumes.
- **Volumes salvos** só valem enquanto a soma por produto bater com os itens atuais. Se não bater, a tela mostra o aviso "O pedido mudou depois que as caixas foram montadas." e sugere de novo.
- **Status do pedido:**
  - `salvo` e `pronto`: monta, salva e imprime;
  - `finalizado`: só reimprime os volumes salvos, sem editar; sem volumes salvos, sai a etiqueta única de hoje;
  - `cancelado`: não imprime.
- **Etiquetas:**
  - cada uma tem os itens **só daquele volume** e os mesmos cliente, endereço, vendedor e QR do pedido;
  - tudo sai num único PDF;
  - depois vem a pergunta "As etiquetas saíram certas?", com as opções "Sim" (marca a etiqueta impressa), "Imprimir de novo" (escolhe "Todas" ou um volume) e "Cancelar".
- **Telas:**
  - nada estoura em 360 px de largura;
  - visual com os componentes e tokens de `packages/milkdim_ui`.

## Review Focus

1. **Pedido com o mesmo produto em duas linhas** (por exemplo, duas linhas de "Copo leite em pó 160g"): a sugestão, a conferência e a RPC somam por nome. Testado nas Tarefas 1 e 2.
2. **Nome do item com maiúsculas ou espaços diferentes do cadastro:** liga ao produto do mesmo jeito. Testado na Tarefa 2.
3. **Tela de volumes com a soma errada:** o botão Imprimir fica bloqueado, com a mensagem da diferença por produto ("Copo …: faltam 3"). Testado na Tarefa 6.
4. **Pedido alterado depois de salvo:** os volumes salvos são ignorados, aparece o aviso e uma nova sugestão. Testado nas Tarefas 2 e 6.
5. **Etiqueta 60×40 com muitos itens num volume:** pagina sem perder item, com o rótulo do volume em todas as páginas. Testado na Tarefa 5.

---

### Task 1: Migração e teste SQL

**Files:**
- Create: `supabase/migrations/20261126000001_etiqueta_caixas.sql`
- Create: `supabase/tests/etiqueta_caixas_test.sql`

**Interfaces:**
- Produces:
  - **`public.tipos_caixa`:**
    - `id bigint identity pk`;
    - `nome text not null`, com `check (btrim(nome) <> '')` e índice único em `lower(btrim(nome))`;
    - `capacidade int not null check (capacidade > 0)`;
    - `mistura_sabores boolean not null default true`;
    - `ativo boolean not null default true`.
  - **`public.produtos.tipo_caixa_id`:** `bigint null references public.tipos_caixa(id) on delete set null`.
  - **`public.pedido_volumes`:**
    - `pedido_id bigint pk references public.pedidos(id) on delete cascade`;
    - `solto boolean not null`;
    - `volumes jsonb not null`;
    - `pedido_alterado_em timestamptz`;
    - `salvo_em timestamptz not null`;
    - `salvo_por text`.
  - **RPC** `public.pedido_salvar_volumes(bigint, boolean, jsonb)`, conforme as Global Constraints.
  - **Arquivo:** idempotente, sem `begin`/`commit` dentro e com comentários em português sem acento, no estilo de `supabase/migrations/20261125000001_fase_d_saidas.sql`.

- [ ] **Step 1: Escrever o teste**, no estilo de `supabase/tests/fase_d_test.sql`: vendedor comum `-920`, admin `-921`, conta sem vendedor, `anon`, pedidos de teste do vendedor `-920`.
  1. Existem 3 tipos com as capacidades certas.
  2. A ligação inicial pelo nome casa os padrões: um produto de teste "Copo teste 160g" fica com o tipo Copo, e "Pudim teste" fica sem tipo.
  3. O admin salva os volumes de um pedido `pronto` cujos itens somam certo → linha gravada, com `salvo_por = '-921'` e `pedido_alterado_em` igual ao do pedido.
  4. Soma errada → `MD011`. Volume vazio ou quantidade 0 → `22023`. `p_solto` com 2 volumes → `22023`.
  5. Pedido `finalizado` ou `cancelado` → `MD010`.
  6. O vendedor comum chama a RPC → `42501`. Ele também não lê `pedido_volumes` nem `tipos_caixa` (0 linhas) e não insere direto em `pedido_volumes` (`42501`).
  7. O admin não consegue `insert` direto em `pedido_volumes` (`42501`); só pela RPC.
  8. O `anon` recebe `42501` ao ler `tipos_caixa` e `pedido_volumes`.
  9. Duas linhas do mesmo produto no pedido somam por nome: volumes com o total certo passam.
  10. Os pedidos não mudam: `count` e `sum(total)` iguais antes e depois.
- [ ] **Step 2: Escrever a migração.**
- [ ] **Step 3: Conferir.** O controlador roda `begin; <migração>; <teste>; rollback;` pelo MCP. Quem implementa só confere que não há `begin`, `commit` nem `rollback` nos arquivos.
- [ ] **Step 4: Commit.** Rode `git add supabase/migrations/20261126000001_etiqueta_caixas.sql supabase/tests/etiqueta_caixas_test.sql` e depois `git commit -m "feat(caixas): tipos de caixa, volumes do pedido e RPC de gravação"`.

### Task 2: Regras dos volumes (Dart puro)

**Files:**
- Create: `admin/lib/etiqueta/volumes.dart`
- Test: `admin/test/volumes_test.dart`

**Interfaces:**
- Produces:
  - `class TipoCaixa { final int id; final String nome; final int capacidade; final bool misturaSabores; final bool ativo; factory TipoCaixa.fromMap(Map<String, dynamic>); }`
  - `class ItemVolume { final String nome; final int quantidade; }`
  - `class Volume { final bool caixa; final String? tipoNome; final List<ItemVolume> itens; Map<String, dynamic> toJson(); factory Volume.fromJson(Map<String, dynamic>); }`
    - O JSON é `{"tipo": "caixa"|"avulso", "caixa": tipoNome, "itens": [{"nome", "quantidade"}]}`.
  - `class VolumesPedido { final bool solto; final List<Volume> volumes; }`
  - `Map<String, TipoCaixa?> tiposPorNomeDeProduto(List<Produto> produtos, List<TipoCaixa> tipos)`
    - A chave é o nome normalizado (`trim` + minúsculas), seguindo a regra do produto ativo de menor `id`.
    - O valor é `null` quando o produto não tem tipo ou o tipo está inativo.
  - `String chaveNome(String nome)`
  - `VolumesPedido sugerirVolumes(List<PedidoItem> itens, Map<String, TipoCaixa?> tipos)`
  - `VolumesPedido pedidoSolto(List<PedidoItem> itens)`
  - `List<String> conferirVolumes(List<PedidoItem> itens, VolumesPedido v)`
    - A lista vazia quer dizer que está certo.
    - As mensagens são por produto, por exemplo "Copo X: faltam 3" e "Copo X: sobram 2".
    - Também aponta "Caixa 2 está vazia".
  - `bool volumesValem(List<PedidoItem> itens, VolumesPedido salvos)`: devolve true se a conferência estiver vazia.
  - `String rotuloVolume(VolumesPedido v, int indice)`
  - `List<String> avisosCapacidade(VolumesPedido v, Map<String, TipoCaixa> tiposPorNome)`: por exemplo "Caixa 1/3 tem 22 unidades (cabem 20)". É só aviso, não bloqueia.
- Consumes: `PedidoItem` (`nome`, `quantidade`) de `admin/lib/models/pedido.dart` e `Produto` de `admin/lib/models/produto.dart`. Esta tarefa acrescenta `final int? tipoCaixaId` ao `Produto`, lido de `tipo_caixa_id`.

- [ ] **Step 1: Testes que falham.** Os nomes e os valores são obrigatórios.
  - `'50 copos de um sabor: 2 caixas e 10 avulsos'` → rótulos `['Caixa 1/3 · Copo', 'Caixa 2/3 · Copo', 'Avulsos 3/3']`, avulsos com 10.
  - `'mistura ligada atravessa sabores'` → 30 de leite + 20 de doce de leite (Copo, 20) dão a caixa 1 com 20 de leite, a caixa 2 com 10 de leite e 10 de doce, e os avulsos com 10 de doce.
  - `'mistura desligada: cada produto só nas próprias caixas'` → mesmo pedido dá caixa de 20 de leite, caixa de 20 de doce e avulsos com 10 de leite.
  - `'tipos na ordem do primeiro item; avulsos por último'` → itens [pote 16, copo 20, grande 2] dão `['Caixa 1/3 · Pote', 'Caixa 2/3 · Copo', 'Avulsos 3/3']`.
  - `'sem avulsos, n conta só as caixas'` → 40 copos dão `['Caixa 1/2 · Copo', 'Caixa 2/2 · Copo']`.
  - `'só produtos sem caixa vira Avulsos 1/1'`.
  - `'pedido solto: um volume com tudo e rótulo Pedido solto'`.
  - `'mesmo produto em duas linhas soma por nome'`.
  - `'nome com maiúsculas e espaços liga ao produto'` → " COPO leite 160g " casa com "Copo leite 160g".
  - `'produto repetido: vale o ativo de menor id'`.
  - `'tipo inativo vai para avulsos'`.
  - `'conferirVolumes aponta faltam/sobram/caixa vazia'`.
  - `'volumesValem falso quando o pedido mudou'`.
  - `'avisosCapacidade não bloqueia'`.
  - `'Volume.toJson/fromJson ida e volta'`.
- [ ] **Step 2: Rodar e ver falhar.** Rode `cd admin && flutter test test/volumes_test.dart`. Esperado: FAIL na compilação.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar e ver passar.** Rode o mesmo comando e depois `flutter test`. Esperado: PASS.
- [ ] **Step 5: Commit.** Rode `git commit -m "feat(caixas): sugestão, conferência e rótulos dos volumes"`.

### Task 3: Serviço

**Files:**
- Create: `admin/lib/services/caixas_service.dart`
- Modify: `admin/lib/services/supabase_service.dart` (leitura e gravação de `tipo_caixa_id` no produto, só onde o produto é salvo e lido)
- Test: `admin/test/caixas_service_test.dart`

**Interfaces:**
- Consumes: `TipoCaixa`, `Volume`, `VolumesPedido` (Tarefa 2) e `RepoFailure`.
- Produces:
  - `abstract class FonteCaixas`, com os métodos:
    - `Future<List<TipoCaixa>> tiposCaixa()`: todos, ordenados por nome;
    - `Future<void> criarTipo(String nome, int capacidade, bool mistura)`;
    - `Future<void> alterarTipo(TipoCaixa t)`;
    - `Future<VolumesPedido?> volumesSalvos(int pedidoId)`;
    - `Future<void> salvarVolumes(int pedidoId, VolumesPedido v)`;
    - `Future<void> definirTipoDoProduto(int produtoId, int? tipoId)`.
  - `class CaixasService implements FonteCaixas`, com o construtor `([SupabaseClient? injected])`.
  - `static String mensagemErroCaixas(String? code)`:
    - `MD010` → "Este pedido não pode ter as caixas alteradas.";
    - `MD011` → "As caixas não batem com o pedido.";
    - `23505` → "Já existe um tipo de caixa com esse nome.";
    - `42501` → "Sem permissão para essa ação.";
    - qualquer outro → "Erro ao salvar as caixas.".
  - `static Map<String, dynamic> paramsSalvarVolumes(int id, VolumesPedido v)` → `{'p_id': id, 'p_solto': v.solto, 'p_volumes': [...toJson]}`.
- [ ] **Step 1: Testes.** Testar `mensagemErroCaixas` em cada código e `paramsSalvarVolumes`. Também `Produto.fromMap` lendo `tipo_caixa_id`, e o produto salvo levando `tipo_caixa_id` (se o `supabase_service` tiver uma função pura de montar o mapa, teste essa função).
- [ ] **Step 2: Rodar e ver falhar.** Rode `flutter test test/caixas_service_test.dart`.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar e ver passar.** Rode `flutter test` (a suíte inteira).
- [ ] **Step 5: Commit.** Rode `git commit -m "feat(caixas): serviço de tipos de caixa e volumes"`.

### Task 4: Cadastro — tipo de caixa nos produtos

**Files:**
- Modify: `admin/lib/tabs/produtos_tab.dart`
- Create: `admin/lib/etiqueta/dialogo_tipos_caixa.dart`
- Test: `admin/test/produtos_caixa_test.dart`

**Interfaces:**
- Consumes: `FonteCaixas` (Tarefa 3) e `TipoCaixa`.
- Produces:
  - **No diálogo de produto:** um campo "Tipo de caixa", com os tipos **ativos** mais "Sem caixa (avulso)". Se o produto tiver um tipo inativo, ele aparece selecionado mesmo assim.
  - **Na lista de produtos:** mostra o tipo ("Caixa: Copo (20)") ou "Avulso".
  - **Botão "Tipos de caixa"**, que abre `mostrarDialogoTiposCaixa(BuildContext, FonteCaixas)`. Nele dá para criar e editar nome, capacidade, "Misturar sabores na mesma caixa" e ativo. Não há apagar. O erro do serviço aparece em SnackBar.
  - **Para testes:** `ProdutosTab` recebe uma `FonteCaixas? fonteCaixas` opcional, no padrão `@visibleForTesting` das outras abas.
- [ ] **Step 1: Testes de widget que falham:**
  - escolher o tipo "Copo" e salvar chama `definirTipoDoProduto(id, idCopo)`;
  - "Sem caixa (avulso)" grava `null`;
  - tipo inativo não aparece na lista, mas fica selecionado se já for o do produto;
  - criar tipo com capacidade 0 mostra "Capacidade inválida.";
  - a lista de produtos mostra "Avulso" e "Caixa: Copo (20)";
  - a tela em 360 px não estoura.
- [ ] **Step 2: Rodar e ver falhar.** **Step 3: Implementar.** **Step 4: Rodar** `flutter test`. **Step 5: Commit** com a mensagem `"feat(caixas): tipo de caixa no cadastro de produtos"`.

### Task 5: PDF com uma etiqueta por volume

**Files:**
- Modify: `admin/lib/etiqueta/etiqueta_pdf.dart`
- Modify: `admin/test/etiqueta_test.dart`

**Interfaces:**
- Consumes: `VolumesPedido` e `rotuloVolume` (Tarefa 2).
- Produces:
  - `EtiquetaDados` ganha `this.volume = ''`, o texto do rótulo do volume. Ele aparece em destaque no cabeçalho, logo abaixo de "Pedido N", em **todas** as páginas daquele volume.
  - `Future<Uint8List> gerarEtiquetasPdf(List<EtiquetaDados> volumes, TamanhoEtiqueta t, {Uint8List? logo})`: um documento com as páginas de cada volume em ordem.
    - Com 1 volume e `volume == ''`, sai igual a `gerarEtiquetaPdf`.
    - `gerarEtiquetaPdf` continua existindo e chama `gerarEtiquetasPdf([d], t)`.
  - `List<EtiquetaDados> etiquetasDosVolumes(EtiquetaDados base, VolumesPedido v)`: copia `base`, troca os itens pelos do volume e preenche o `volume` com `rotuloVolume`.
- [ ] **Step 1: Testes:**
  - 3 volumes geram um PDF que começa com `%PDF`;
  - `etiquetasDosVolumes` copia o cliente e o QR, troca os itens e preenche os rótulos `'Caixa 1/3 · Copo'`, …;
  - um volume com 25 itens em 60×40 continua paginando;
  - o PDF de um volume sem rótulo tem o mesmo número de páginas que antes.
- [ ] **Step 2–4:** rode `flutter test test/etiqueta_test.dart` e depois `flutter test`.
- [ ] **Step 5: Commit** com a mensagem `"feat(caixas): etiqueta com o rótulo do volume e PDF com vários volumes"`.

### Task 6: Tela "Volumes do pedido" e fluxo de impressão

**Files:**
- Create: `admin/lib/etiqueta/tela_volumes.dart`
- Modify: `admin/lib/etiqueta/imprimir_etiqueta.dart`, `admin/lib/tabs/producao_tab.dart` e `admin/lib/widgets/detalhe_pedido.dart`
- Test: `admin/test/tela_volumes_test.dart` e os ajustes em `admin/test/producao_etiqueta_test.dart`

**Interfaces:**
- Consumes: as Tarefas 2, 3 e 5, mais os `marcar` e `EnviarParaImpressora` existentes.
- Produces:
  - `Future<VolumesPedido?> mostrarTelaVolumes(BuildContext, {required Pedido pedido, required VolumesPedido inicial, required Map<String, TipoCaixa> tiposPorNome, String? aviso, bool somenteLeitura = false})`. Ela devolve os volumes confirmados, ou `null` se cancelado. A tela tem:
    - o título "Volumes do pedido N";
    - um interruptor "Pedido solto (sem caixas)";
    - cada volume com o rótulo, os itens e campos de quantidade, mais os botões "Nova caixa", "Apagar caixa" e "Adicionar produto" (só os produtos do pedido);
    - a lista de `conferirVolumes` em vermelho e os `avisosCapacidade` em amarelo;
    - o botão "Imprimir", desabilitado enquanto a conferência não estiver vazia;
    - no modo somente leitura, só "Imprimir" e "Cancelar".
  - **Novo fluxo** `imprimirEtiquetasComVolumes(BuildContext, Pedido p, {required FonteCaixas fonte, required List<Produto> produtos, required Future<void> Function(int, String?) marcar, EnviarParaImpressora? enviar})`, que substitui a chamada atual nos dois pontos:
    1. Pedido `cancelado`: não faz nada.
    2. Carrega os tipos e os volumes salvos.
    3. Se os volumes salvos valerem, usa esses. Se não valerem, sugere de novo; se existiam volumes salvos que não valem mais, mostra o aviso "O pedido mudou depois que as caixas foram montadas.".
    4. Pedido `finalizado` sem volumes salvos: usa o fluxo antigo de etiqueta única. Com volumes salvos: abre a tela em somente leitura.
    5. Abre a tela.
    6. Se o pedido não estiver `finalizado`, chama `salvarVolumes`. Se falhar, mostra o SnackBar com a mensagem e para.
    7. Gera e envia o PDF de todos os volumes.
    8. Pergunta "As etiquetas saíram certas?" com as opções "Sim" (marca), "Imprimir de novo" (escolhe "Todas" ou "Volume i/n" e reenvia só esse) e "Cancelar".
  - **Pontos de teste:** `ProducaoTab` e `DetalhePedido` recebem `FonteCaixas?` e o carregamento de produtos opcionais, no padrão `@visibleForTesting`.
- [ ] **Step 1: Testes de widget que falham:**
  - a sugestão aparece com os rótulos certos;
  - mudar uma quantidade para errado desabilita "Imprimir" e mostra "faltam";
  - "Pedido solto" vira um volume;
  - volumes salvos que ainda batem são usados sem o aviso;
  - volumes salvos que não batem mostram o aviso e a sugestão nova;
  - imprimir chama `salvarVolumes` antes do envio, e envia 1 PDF com os N volumes;
  - "Imprimir de novo" com "Volume 2/3" envia só esse volume;
  - "Sim" chama `marcar`;
  - erro em `salvarVolumes` mostra o SnackBar e não envia;
  - pedido finalizado com volumes salvos abre em somente leitura e não chama `salvarVolumes`;
  - a tela em 360 px não estoura.
- [ ] **Step 2: Rodar e ver falhar.** **Step 3: Implementar e ajustar** os testes existentes de etiqueta e produção, sem enfraquecer as asserções. **Step 4: Rodar** `flutter test`. **Step 5: Commit** com a mensagem `"feat(caixas): tela de volumes e impressão por caixa"`.

### Task 7: Roteiro de implantação

**Files:**
- Create: `docs/implantacao-etiqueta-caixas.md`

- [ ] **Step 1: Escrever o roteiro**, no formato de `docs/implantacao-fase-b.md`. Ele cobre:
  - **ordem:** primeiro o SQL (com OK), depois o Controle novo; o app dos celulares não muda;
  - **conferência dos tipos de produto:** quais produtos ficaram sem tipo, e como definir no cadastro;
  - **teste:**
    1. pedido de 50 copos → 3 etiquetas;
    2. pedido solto;
    3. reimprimir só a 2/3;
    4. alterar o pedido depois e ver o aviso;
  - **mensagens:** "As caixas não batem com o pedido.", "Este pedido não pode ter as caixas alteradas.", "O pedido mudou depois que as caixas foram montadas.";
  - **build:** `MilkDim_Controle_Windows_<data>_caixas`.
  - Confira cada texto da tela no código.
- [ ] **Step 2: Commit** com a mensagem `"docs: roteiro da etiqueta por caixa"`.
