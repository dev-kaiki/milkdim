# Fase B — Etiqueta com QR para registrar a entrega: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O Controle imprime uma etiqueta com QR personalizado para cada pedido pronto. Qualquer
vendedor lê o QR no app e registra a entrega assinada: o dono do pedido pelo fluxo local, que
funciona sem internet, e outro vendedor pelo servidor, só com o pedido pronto.

**Architecture:**
- **Servidor:** o pedido ganha um `codigo_qr` secreto e duas colunas de etiqueta. Três RPCs
  `security definer` fazem tudo o que não é do dono do pedido, sem abrir a RLS.
- **Controle:** gera a etiqueta em PDF (pacotes `pdf`, `printing` e `qr`) e a imprime pelo driver
  do Windows.
- **App:** lê o QR com `mobile_scanner`.
  - Se acha o código no SQLite, abre a tela atual em "Registrar entrega".
  - Se não acha, usa as RPCs numa tela nova.

**Tech Stack:** Flutter 3.41 / Dart 3.11, supabase_flutter, sqflite (testes com
sqflite_common_ffi), Postgres 17 no Supabase. Pacotes novos:
- `pdf`, `printing` e `qr` no Controle;
- `mobile_scanner` no app;
- `image` e `zxing2` só como dependência de desenvolvimento, para decodificar o QR nos testes.

**Spec:** `docs/superpowers/specs/2026-11-24-fase-b-etiqueta-qr-design.md`. Ela manda sobre o
plano, inclusive a seção "Decisões tomadas por mim (Claude) depois da revisão".

## Global Constraints

- Repositório público: nenhuma senha, chave, URL ou ref do Supabase em arquivo versionado.
- Nenhuma migração em produção sem mostrar o SQL ao Kaiki e receber OK no chat. O implementador
  **não** acessa banco nenhum: só escreve o SQL e o teste. O controlador roda os dois.
- Nenhum pedido local é apagado por login, logout, fim de sessão ou sincronização.
- Sem nomes de clientes ou do dono em código, testes, documentos e capturas. Use nomes inventados
  ("Cliente Teste").
- A migração precisa ser compatível com os APKs da Fase A instalados:
  - só colunas novas, com valor padrão;
  - sem mudança no comportamento atual dos gatilhos para as colunas antigas.
- Conteúdo do QR: `MILKDIM:E:<uuid>`. Qualquer outro conteúdo dá a mensagem exata "Esta etiqueta
  não é de um pedido da MilkDim."
- QR: correção de erro H, logo cobrindo no máximo cerca de 20% da área, margem de 4 módulos,
  mínimo de 30 mm na etiqueta de 100 mm, preto puro sem cinza.
- Tamanhos de etiqueta: 100×100 mm (padrão), 100×150 mm e 60×40 mm, guardados por computador.
- SQLSTATEs:
  - `P0002`: pedido não encontrado;
  - `MD002`: já entregue;
  - `MD003`: não está pronto, para quem não é o dono;
  - `MD004`: cancelado, para quem não é o dono;
  - `42501`: sem permissão.
- Mensagens exatas no app:
  - "Pedido não encontrado."
  - "Este pedido já foi entregue."
  - "Este pedido ainda não está pronto para entrega."
  - "Este pedido foi cancelado."
  - "Não deu para confirmar a entrega. Leia a etiqueta de novo."
  - "Sem internet. Para entregar pedido de outro vendedor, conecte e leia de novo."
  - "Entrega registrada."
- Textos exatos no Controle:
  - "Imprimir etiqueta"
  - "Imprimir a etiqueta agora?"
  - "A etiqueta saiu certa?", com as opções Sim / Imprimir de novo / Cancelar
  - "Etiqueta impressa às HH:mm"
  - "Sem etiqueta"
  - "Etiqueta desatualizada"
  - "Entregue por <código> (<nome>)", com " (outro vendedor)" quando não é o dono
- Testes como hoje: `flutter test` em `app/`, `admin/` e `packages/milkdim_ui`. O
  `flutter analyze` não pode ganhar avisos novos. Hoje são 42 no app, 14 no admin e 0 no
  pacote.

## Review Focus

1. **A câmera lê o mesmo QR várias vezes por segundo**: só uma navegação e uma chamada ao
   servidor por leitura. Fica na Tarefa 6.
2. **A rede cai depois que a entrega deu certo no servidor**: ler de novo mostra "Este pedido já
   foi entregue." e nada é gravado duas vezes. Ficam na Tarefa 1 (MD002 no SQL) e na Tarefa 5
   (mapeamento).
3. **Pedido com muitos itens** (25 produtos na etiqueta de 60×40): a etiqueta continua em mais
   páginas com "1/N" e o QR sai em todas. Fica na Tarefa 2.
4. **Pedido alterado depois da impressão**: o cartão mostra "Etiqueta desatualizada". Fica na
   Tarefa 3.
5. **Pedido do dono com alteração ainda não enviada (`pendente_envio = 1`)**: o QR abre o fluxo
   local, não a RPC. Fica na Tarefa 5.

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `supabase/migrations/20261124000001_fase_b_etiqueta_qr.sql` | colunas, gatilhos e RPCs |
| `supabase/tests/fase_b_test.sql` | teste em begin…rollback |
| `packages/milkdim_ui/lib/src/qr_entrega.dart` | monta e lê o conteúdo `MILKDIM:E:<uuid>` |
| `admin/lib/etiqueta/qr_arredondado.dart` | geometria do QR arredondado, função pura |
| `admin/lib/etiqueta/etiqueta_pdf.dart` | PDF da etiqueta (layout e paginação) |
| `admin/lib/etiqueta/tamanho_etiqueta.dart` | tamanhos e preferência local |
| `admin/lib/etiqueta/imprimir_etiqueta.dart` | fluxo de impressão e confirmação |
| `admin/lib/models/pedido.dart`, `services/supabase_service.dart`, `tabs/producao_tab.dart`, `widgets/detalhe_pedido.dart` | ligação no Controle |
| `app/lib/utils/db.dart` | v19 e `codigo_qr` |
| `app/lib/utils/supabase_helper.dart` | `codigo_qr` no eco e na sincronização, nunca no envio |
| `app/lib/utils/entrega_qr.dart` | decide o caminho depois da leitura e chama as RPCs |
| `app/lib/pages/ler_etiqueta_page.dart` | câmera |
| `app/lib/pages/entrega_qr_page.dart` | entrega pelo servidor |
| `docs/implantacao-fase-b.md` | roteiro de implantação e teste de ponta a ponta |

---

### Task 1: Servidor — código do QR, etiqueta e RPCs

**Files:**
- Create: `supabase/migrations/20261124000001_fase_b_etiqueta_qr.sql`
- Create: `supabase/tests/fase_b_test.sql`

**Interfaces:**
- Consumes:
  - `public.app_is_admin()`, `public.app_meu_codigo()` e `public.app_autor_pedido()`;
  - a flag `milkdim.acao_controle`;
  - os gatilhos `pedidos_antes_inserir` e `pedidos_antes_alterar` da migração
    `20261123000002_fase_a2_pronto_assinaturas.sql`. Leia essa migração inteira antes de começar
    e reescreva os dois gatilhos como `create or replace`, mantendo todo o comportamento atual.
- Produces:
  - colunas `pedidos.codigo_qr uuid not null default gen_random_uuid()` (índice único
    `pedidos_codigo_qr_key`), `etiqueta_impressa_em timestamptz` e
    `etiqueta_impressa_por text`;
  - `public.pedido_marcar_etiqueta(p_id bigint) returns void`;
  - `public.pedido_por_qr(p_codigo uuid) returns jsonb`;
  - `public.pedido_entregar_por_qr(p_codigo uuid, p_assinatura bytea) returns jsonb`. Devolve
    `{id, numero, finalizado_em}`.
  - `execute` liberado só para `authenticated`. Revogado de `public` e `anon`.

Regras que o SQL fixa (a spec manda):

- **Gatilho de inserção**:
  - força `codigo_qr := gen_random_uuid()`, ignorando o que vier do app;
  - zera `etiqueta_impressa_em` e `etiqueta_impressa_por`.
  - Exceção: com a flag `milkdim.acao_controle = '1'` o gatilho de inserção não muda nada disso.
    Hoje nenhuma RPC insere pedido.
- **Gatilho de alteração** sem a flag: `codigo_qr`, `etiqueta_impressa_em` e
  `etiqueta_impressa_por` sempre ficam com o valor antigo. Coloque isso **antes** do `return old`
  dos pedidos fechados, para valer em todos os caminhos.
- **`pedido_marcar_etiqueta`**:
  - não admin: `42501`;
  - id inexistente: `P0002`;
  - grava `etiqueta_impressa_em = now()` e `etiqueta_impressa_por = app_autor_pedido()` com a
    flag ligada, e desliga a flag depois, como em `pedido_marcar_pronto`;
  - não muda `status` nem `alterado_em`.
- **`pedido_por_qr`**:
  - `app_meu_codigo()` nulo: `42501`;
  - código desconhecido: `P0002`;
  - status `finalizado` ou `cancelado`: `{"numero":…, "status":…}` e nada mais;
  - nos outros casos: `{id, numero, status, vendedor_codigo, vendedor_nome, cliente_nome,
    cliente_nome_fantasia, cliente_cidade, itens, do_proprio_vendedor}`.
    - `itens` é `[{"nome":…, "quantidade":…}]`, tirado de `produtos`. A quantidade é
      `quantidade` ou, na falta, `qtd`, convertida para inteiro. Sem preço.
- **`pedido_entregar_por_qr`**:
  - `app_meu_codigo()` nulo: `42501`;
  - `p_assinatura` nula ou vazia: `22023`;
  - código desconhecido: `P0002`;
  - lê o pedido com `for update`.
  - **Quem não é o dono:**
    - `finalizado`: `MD002`;
    - `cancelado`: `MD004`;
    - qualquer status diferente de `pronto`: `MD003`.
  - **O dono:**
    - `finalizado` com `assinatura` não nula: `MD002`;
    - o resto segue as regras de hoje, inclusive pedido em aberto e a entrega assinada vencendo
      cancelado e entregue manual.
  - Depois faz `update … set status = 'finalizado', assinatura = p_assinatura` **sem** a flag,
    para o gatilho atual preencher `finalizado_em` e `finalizado_por`.
    - `finalizado_por` sai do `app_autor_pedido()`, que lê o JWT de quem chamou. O teste confere
      que é o código de quem entregou.
  - Se o gatilho devolver o pedido sem mudança, a RPC dá `55000`. Isso não deveria acontecer
    depois das checagens acima.

- [ ] **Step 1: Escrever `supabase/tests/fase_b_test.sql`** no formato do `fase_a2_test.sql`:
  - roda dentro de begin…rollback montado por quem executa, depois de `fase_a_test.sql` e
    `fase_a2_test.sql`;
  - números `teste-fb-*`, vendedores `-905` (A), `-906` (B) e `-907` (admin);
  - cada bloco dá `raise exception` quando a verificação falha;
  - o login é simulado com `set local role authenticated` e `request.jwt.claims`, como no
    `fase_a2_test.sql`.

  Blocos, cada um com sua asserção:
  1. Inserção pelo vendedor com `codigo_qr` e `etiqueta_impressa_em` preenchidos: o servidor
     troca o código e zera a etiqueta.
  2. Alteração pelo vendedor tentando mudar `codigo_qr` ou `etiqueta_impressa_*`: os valores
     antigos ficam. Testar em pedido `salvo` e em pedido `finalizado`.
  3. `pedido_marcar_etiqueta`:
     - vendedor comum dá `42501`;
     - admin grava `etiqueta_impressa_em = now()` e `etiqueta_impressa_por = '-907'`;
     - `status` e `alterado_em` não mudam;
     - id inexistente dá `P0002`.
  4. `pedido_por_qr`:
     - A lê o pedido `pronto` de B: as chaves são exatamente as 10 da lista e
       `do_proprio_vendedor = false`;
     - `itens` sem `preco`;
     - pedido finalizado devolve só `numero` e `status`;
     - uuid aleatório dá `P0002`.
  5. A continua sem ver o pedido de B por `select` (0 linhas).
  6. A entrega o pedido `pronto` de B:
     - `status = 'finalizado'`, `finalizado_por = '-905'`, `assinatura` igual à enviada;
     - `vendedor_codigo` continua `-906`.
  7. Repetir a entrega do bloco 6: `MD002`.
  8. Quem não é o dono, com pedido `salvo`: `MD003`. Com pedido `cancelado`: `MD004`. O pedido
     não muda em nenhum dos dois.
  9. O dono entrega o próprio pedido `salvo` pelo QR: aceita, com `finalizado_por = '-906'`.
  10. O dono entrega o próprio pedido `cancelado` pelo QR: aceita (a entrega assinada vence).
  11. Assinatura vazia (`'\x'::bytea`): `22023`.
  12. Usuário autenticado sem vendedor: `42501` nas duas RPCs de vendedor.

- [ ] **Step 2: Escrever a migração.**
  - Comentários em português, como nas anteriores.
  - Termina com `notify pgrst, 'reload schema';` se as migrações anteriores fizerem isso. Confira
    e siga o mesmo padrão.

- [ ] **Step 3: Verificação estática.** Releia a migração contra as regras acima e confira:
  - que nenhum comportamento antigo dos gatilhos mudou, comparando com o `diff` da versão da
    A.2;
  - que nenhum ref ou URL do projeto aparece no arquivo:

  Run: `grep -niE "supabase\.co" supabase/migrations/20261124000001_fase_b_etiqueta_qr.sql supabase/tests/fase_b_test.sql`. O controlador confere também o ref do projeto, que não aparece neste plano.
  Expected: nenhuma linha.

  O controlador roda o teste no banco (begin; A.2-test pré-requisitos; migração; testes;
  rollback) depois do OK do Kaiki.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20261124000001_fase_b_etiqueta_qr.sql supabase/tests/fase_b_test.sql
git commit -m "feat(db): codigo do QR, etiqueta impressa e entrega pelo QR"
```

---

### Task 2: Etiqueta em PDF com o QR arredondado

**Files:**
- Create: `packages/milkdim_ui/lib/src/qr_entrega.dart` e exportar em `milkdim_ui.dart`.
- Create: `packages/milkdim_ui/test/qr_entrega_test.dart`
- Create: `admin/lib/etiqueta/qr_arredondado.dart`, `admin/lib/etiqueta/etiqueta_pdf.dart` e
  `admin/lib/etiqueta/tamanho_etiqueta.dart`
- Create: `admin/test/etiqueta_test.dart`
- Modify: `admin/pubspec.yaml`:
  - dependências `pdf`, `printing` e `qr`, nas mesmas versões principais do `app/` quando o
    pacote existir lá;
  - dependências de desenvolvimento `image` e `zxing2`.

**Interfaces:**
- Produces (pacote):
  - `String conteudoQrEntrega(String codigoQr)`, que devolve `'MILKDIM:E:$codigoQr'`;
  - `String? codigoDoQrEntrega(String lido)`, que devolve o uuid em minúsculas ou `null`.
  - Aceita espaços nas pontas. O prefixo é sensível a maiúsculas. O uuid precisa ter o formato
    8-4-4-4-12 hexadecimal.
- Produces (admin):
  - `enum TamanhoEtiqueta { m100x100, m100x150, m60x40 }`, com `larguraMm`, `alturaMm` e
    `rotulo` ("100 × 100 mm", …);
  - `Future<TamanhoEtiqueta> lerTamanhoEtiqueta()` e
    `Future<void> gravarTamanhoEtiqueta(TamanhoEtiqueta t)`, com `shared_preferences` na chave
    `'etiqueta_tamanho'` e padrão `m100x100`;
  - `class FormaQr { final double x, y, largura, altura, raio; }`, em unidades de módulo, com a
    margem já somada;
  - `({int modulos, List<FormaQr> formas, ({double x, double y, double lado}) areaLogo}) geometriaQrArredondado(String conteudo)`.
    Usa o pacote `qr`, correção H, e uma margem de 4 módulos.
    - Os módulos escuros saem com raio de 0,5 módulo nos cantos livres. Basta um retângulo
      arredondado por módulo; não precisa unir vizinhos.
    - Os três quadrados de canto saem como anel externo 7×7 arredondado e miolo 3×3 arredondado.
    - A área do logo fica centralizada, com lado de cerca de 20% da largura útil (sem a margem)
      e alinhada a módulos inteiros. Os módulos dentro dela são omitidos.
  - `Future<Uint8List> gerarEtiquetaPdf(EtiquetaDados d, TamanhoEtiqueta t)`, com
    `class EtiquetaDados { numero, clienteTitulo, cidade, vendedorCodigo, List<({String nome, int quantidade})> itens, DateTime? prontoEm, String codigoQr }`.
    - `clienteTitulo` é o nome fantasia ou, na falta, o nome.
  - `List<List<int>> paginarItens(int totalItens, TamanhoEtiqueta t)` devolve os índices dos
    itens de cada página. É exposta para teste.

Layout (siga o esboço da spec):
- cabeçalho com "MILKDIM" e "Pedido <numero>";
- cliente, cidade e "Vendedor <código>";
- itens como "N×  nome", com a fonte diminuindo até um mínimo de 7 pt;
- "Total: X unidades";
- QR com o logo de `packages/milkdim_ui/assets/logo.jpg` sobre fundo branco, convertido para
  preto e branco puro com limiar;
- "Pronto em dd/MM HH:mm";
- "1/N" no rodapé quando houver mais de uma página. O QR sai em todas as páginas.

- [ ] **Step 1: Testes do pacote** em `packages/milkdim_ui/test/qr_entrega_test.dart`:

```dart
test('monta e lê o conteúdo do QR', () {
  const u = '3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b';
  expect(conteudoQrEntrega(u), 'MILKDIM:E:$u');
  expect(codigoDoQrEntrega('  MILKDIM:E:$u \n'), u);
  expect(codigoDoQrEntrega('MILKDIM:E:${u.toUpperCase()}'), u);
});
test('recusa conteúdo que não é da MilkDim', () {
  for (final s in ['', 'https://milkdim.com', 'MILKDIM:E:', 'MILKDIM:E:123', 'milkdim:e:3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b']) {
    expect(codigoDoQrEntrega(s), isNull, reason: s);
  }
});
```

- [ ] **Step 2: Testes do admin** em `admin/test/etiqueta_test.dart`:
  - `'o QR arredondado decodifica de volta no mesmo conteúdo'`:
    - rasteriza a `geometriaQrArredondado(conteudoQrEntrega(u))` num `image.Image` de 8 px por
      módulo, preto sobre branco, com a área do logo pintada de branco e um quadrado preto
      menor no meio;
    - decodifica com `zxing2` (`QRCodeReader`);
    - `expect(texto, conteudoQrEntrega(u))`.
    - Repita para 5 uuids fixos.
  - `'a área do logo cobre no máximo 22% da área útil'`.
  - `'margem de 4 módulos'`: nenhuma forma toca as 4 faixas de borda.
  - `'paginarItens: 25 itens em 60x40 dão mais de uma página e não perdem item'`: a união das
    páginas é `0..24`, em ordem, sem repetição.
  - `'paginarItens: 3 itens em 100x100 dão uma página'`.
  - `'gerarEtiquetaPdf gera PDF não vazio para os três tamanhos'`: os bytes começam com
    `%PDF`.
  - `'tamanho da etiqueta: padrão 100x100 e grava a escolha'`, com
    `SharedPreferences.setMockInitialValues({})`.

- [ ] **Step 3: Rodar e ver falhar**

  Run: `cd packages/milkdim_ui && flutter test test/qr_entrega_test.dart` e
  `cd admin && flutter test test/etiqueta_test.dart`.
  Expected: FAIL (símbolos inexistentes).

- [ ] **Step 4: Implementar** os arquivos com as assinaturas acima.

- [ ] **Step 5: Amostra para o Kaiki.** Um teste marcado `@Tags(['amostra'])`, fora da suíte
  normal, grava em `admin/build/amostra_etiqueta/`:
  - `etiqueta_100x100.pdf` e `etiqueta_60x40_muitos_itens.pdf`;
  - `qr.png`, a rasterização do Step 2.

  Os dados são inventados ("Cliente Teste", "Cidade Teste") e o pedido é `1234`.

  Run: `cd admin && flutter test --tags amostra test/etiqueta_test.dart`
  Expected: os três arquivos existem. O controlador mostra a amostra ao Kaiki.

- [ ] **Step 6: Rodar tudo**

  Run: `flutter test` e `flutter analyze` em `packages/milkdim_ui` e em `admin`.
  Expected: todos passam, sem aviso novo. Configure o `dart_test.yaml` do admin para pular a tag
  `amostra` por padrão.

- [ ] **Step 7: Commit**

```bash
git add packages/milkdim_ui admin/pubspec.yaml admin/pubspec.lock admin/lib/etiqueta admin/test/etiqueta_test.dart admin/dart_test.yaml
git commit -m "feat(controle): etiqueta em PDF com QR arredondado"
```

---

### Task 3: Controle — imprimir e marcar a etiqueta na Produção

**Files:**
- Modify: `admin/lib/models/pedido.dart`:
  - `codigoQr` (`String?`), `etiquetaImpressaEm` (`DateTime?`) e
    `etiquetaImpressaPor` (`String?`);
  - getter `bool get etiquetaDesatualizada`: verdadeiro quando `etiquetaImpressaEm != null &&
    alteradoEm != null && alteradoEm.isAfter(etiquetaImpressaEm)`.
- Modify: `admin/lib/services/supabase_service.dart`:
  - acrescentar `codigo_qr, etiqueta_impressa_em, etiqueta_impressa_por` em
    `colunasPedidoSemAssinatura`;
  - `Future<void> marcarEtiqueta(int id)`, que chama `_rpcPedido('pedido_marcar_etiqueta', id)`.
- Create: `admin/lib/etiqueta/imprimir_etiqueta.dart`
- Modify: `admin/lib/tabs/producao_tab.dart`
- Test: `admin/test/producao_etiqueta_test.dart`

**Interfaces:**
- Consumes: `gerarEtiquetaPdf`, `EtiquetaDados`, `lerTamanhoEtiqueta` e
  `gravarTamanhoEtiqueta` (Tarefa 2).
- Produces:
  - `typedef EnviarParaImpressora = Future<bool> Function(Uint8List pdf, TamanhoEtiqueta t);`.
    O padrão usa `Printing.layoutPdf` com
    `PdfPageFormat(t.larguraMm * PdfPageFormat.mm, t.alturaMm * PdfPageFormat.mm)`;
  - `EtiquetaDados etiquetaDoPedido(Pedido p)`;
  - `Future<bool> imprimirEtiquetaComConfirmacao(BuildContext context, Pedido p, {required Future<void> Function(int id) marcar, EnviarParaImpressora? enviar})`.
    - Gera o PDF, envia para a impressora e mostra o diálogo "A etiqueta saiu certa?".
      - **Sim**: chama `marcar(p.id)` e devolve `true`.
      - **Imprimir de novo**: repete o ciclo.
      - **Cancelar**: devolve `false` sem marcar.
    - Se `enviar` devolver `false` (o diálogo do sistema foi cancelado), sai sem perguntar e sem
      marcar.
  - `ProducaoTab` ganha os parâmetros opcionais `marcarEtiqueta` e `enviarParaImpressora`, para
    teste, no mesmo padrão de `marcarPronto`.

Comportamento na `ProducaoTab`:
- Cada cartão de "Prontos para entrega" ganha o botão "Imprimir etiqueta" (`OutlinedButton.icon`
  com `Icons.print_outlined`).
- Abaixo dos botões aparece um `MdStatusChip`:
  - "Sem etiqueta" (`MdTipo.atencao`);
  - "Etiqueta impressa às HH:mm", sem tipo de alerta;
  - "Etiqueta desatualizada" (`MdTipo.atencao`), que tem precedência sobre "impressa".
- Depois de "Produção concluída" dar certo, aparece o diálogo "Imprimir a etiqueta agora?"
  (Agora / Depois). "Agora" chama `imprimirEtiquetaComConfirmacao` e recarrega a lista no fim.
- Sem `codigoQr` (Controle antigo apontando para um banco sem a migração), o botão fica
  desabilitado com a dica "Atualize o banco para imprimir etiquetas".
- O cabeçalho da Produção ganha um ícone de engrenagem que abre o diálogo de escolha do tamanho
  da etiqueta, com os 3 `rotulo`.

- [ ] **Step 1: Testes** em `admin/test/producao_etiqueta_test.dart`, no padrão de
  `producao_tab_test.dart`, com `enviarParaImpressora` falso que conta as chamadas e
  `marcarEtiqueta` falso:
  - `'pronto sem etiqueta mostra "Sem etiqueta" e o botão Imprimir etiqueta'`;
  - `'Sim em "A etiqueta saiu certa?" marca a etiqueta uma vez'`;
  - `'Imprimir de novo envia outra vez e só marca no Sim'`: 2 envios e 1 marcação;
  - `'Cancelar não marca'`;
  - `'diálogo do sistema cancelado (enviar devolve false) não pergunta nem marca'`;
  - `'alterado depois da impressão mostra "Etiqueta desatualizada"'`;
  - `'depois de Produção concluída pergunta "Imprimir a etiqueta agora?"'`;
  - `'Pedido.fromMap lê codigo_qr e as colunas de etiqueta'`.
- [ ] **Step 2: Rodar e ver falhar.** Run: `cd admin && flutter test test/producao_etiqueta_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar a suíte inteira e o analyze do admin.** Expected: todos passam, no máximo 14
  avisos.
- [ ] **Step 5: Commit** `feat(controle): imprimir etiqueta e marcar como impressa`.

---

### Task 4: Controle — etiqueta e quem entregou no detalhe e na aba Pedidos

**Files:**
- Modify: `admin/lib/widgets/detalhe_pedido.dart` e `admin/lib/tabs/pedidos_tab.dart`.
- Test: `admin/test/detalhe_entregue_por_test.dart`

**Interfaces:**
- Consumes: os campos do `Pedido` (Tarefa 3) e `imprimirEtiquetaComConfirmacao`.
- Produces:
  - `String? textoEntreguePor(Pedido p, Map<String, String> nomesPorCodigo)`, função pura
    exposta para teste.
    - Devolve `null` se o pedido não está `finalizado` ou se `finalizadoPor` é nulo.
    - Devolve "Entregue por <código> (<nome>)", sem o parêntese do nome quando o nome não é
      conhecido.
    - Acrescenta " (outro vendedor)" quando `finalizadoPor != vendedorCodigo` e não é
      `finalizadoManual`.
    - Entrega manual continua mostrando "(manual)", como hoje.
  - O `DetalhePedido` recebe `Map<String, String> nomesPorCodigo` (padrão `const {}`). A aba
    Pedidos monta o mapa com `buscarVendedores()` uma vez por carga.
  - O detalhe mostra a linha de etiqueta ("Etiqueta impressa às HH:mm por <código>", "Sem
    etiqueta" ou "Etiqueta desatualizada") e o botão "Imprimir etiqueta" quando o status é
    `pronto`.

- [ ] **Step 1: Testes:**
  - `textoEntreguePor` para:
    - o dono;
    - outro vendedor com nome conhecido (`'Entregue por 0003 (Vendedor Teste) (outro vendedor)'`);
    - outro vendedor sem nome;
    - manual;
    - não finalizado;
  - widget: o detalhe de pedido pronto mostra "Imprimir etiqueta".
- [ ] **Step 2: Ver falhar, implementar e ver passar.** Rodar a suíte e o analyze do admin.
- [ ] **Step 3: Commit** `feat(controle): mostrar quem entregou e a etiqueta no detalhe`.

---

### Task 5: App — `codigo_qr` no celular e a decisão depois da leitura

**Files:**
- Modify: `app/lib/utils/db.dart`:
  - `_dbVersion = 19`;
  - coluna `codigo_qr TEXT` no `onCreate`, no `onUpgrade` (`if (oldV < 19)`, via
    `_ensureColumn`) e garantida no `onOpen`, no mesmo padrão;
  - índice `CREATE INDEX IF NOT EXISTS idx_pedidos_codigo_qr ON pedidos(codigo_qr)`;
  - `Future<Map<String, dynamic>?> buscarPedidoLocalPorCodigoQr(String codigoQr)`.
- Modify: `app/lib/utils/supabase_helper.dart`:
  - `'codigo_qr'` entra em `_camposDoServidor`, que serve à sincronização e ao eco;
  - `'codigo_qr'` entra em `_camposForaDoPayload`, para nunca ser enviado.
- Create: `app/lib/utils/entrega_qr.dart`
- Test: `app/test/entrega_qr_test.dart`

**Interfaces:**
- Consumes: `codigoDoQrEntrega` (pacote), `temInternet()`, `supabase` e `bytesToHex0x`.
- Produces:
  - `sealed class DestinoLeitura`, com:
    - `QrInvalido`;
    - `AbrirPedidoLocal(Map<String, dynamic> pedido)`;
    - `AbrirEntregaServidor(String codigoQr)`;
    - `SemInternet`;
  - `Future<DestinoLeitura> decidirDestinoDaLeitura(String lido, {Future<bool> Function()? internet})`.
    A ordem segue a spec: inválido, local, internet ou sem internet;
  - `class PedidoQr`, com `id`, `numero`, `status`, `vendedorCodigo`, `vendedorNome`,
    `clienteTitulo`, `cidade`, `List<({String nome, int quantidade})> itens` e
    `bool doProprioVendedor`;
    - getter `String? motivoSemEntrega`:
      - `null` quando a entrega é possível;
      - "Este pedido já foi entregue." para `finalizado`;
      - "Este pedido foi cancelado." para `cancelado`;
      - "Este pedido ainda não está pronto para entrega." quando não é do próprio vendedor e
        não está `pronto`;
  - `PedidoQr.fromJson(Map<String, dynamic>)`, que aceita a forma reduzida (só `numero` e
    `status`);
  - variáveis substituíveis para teste, no padrão de `buscarRemotoPorId`:
    - `Future<Map<String, dynamic>> Function(String codigoQr) rpcPedidoPorQr`;
    - `Future<Map<String, dynamic>> Function(String codigoQr, String assinaturaHex) rpcEntregarPorQr`;
  - `Future<PedidoQr> buscarPedidoPorQr(String codigoQr)` e
    `Future<void> entregarPorQr(String codigoQr, Uint8List assinaturaPng)`. Os dois lançam
    `FalhaEntregaQr(String mensagem)`;
  - `String mensagemErroEntregaQr(String? code)`:
    - `P0002` → "Pedido não encontrado.";
    - `MD002` → "Este pedido já foi entregue.";
    - `MD003` → "Este pedido ainda não está pronto para entrega.";
    - `MD004` → "Este pedido foi cancelado.";
    - erro de rede ou qualquer outro durante a entrega → "Não deu para confirmar a entrega.
      Leia a etiqueta de novo.".

- [ ] **Step 1: Testes** em `app/test/entrega_qr_test.dart`, com sqflite ffi no padrão de
  `fluxo_pronto_assinaturas_test.dart`:
  - `'banco v18 sobe para v19 com codigo_qr e sem perder pedidos'`;
  - `'sincronização grava codigo_qr do servidor'`: `aplicarPedidosRemotos` com `codigo_qr`;
  - `'eco do envio grava codigo_qr'`;
  - `'montarPayloadPedido nunca leva codigo_qr'`;
  - `'QR inválido dá QrInvalido'`;
  - `'código de pedido local abre o pedido local, mesmo com pendente_envio = 1'` (Review Focus
    5);
  - `'código desconhecido com internet vai ao servidor; sem internet dá SemInternet'`;
  - `'mensagemErroEntregaQr mapeia P0002, MD002, MD003, MD004 e o resto'` (Review Focus 2);
  - `'PedidoQr.motivoSemEntrega'`: pronto de outro (`null`), salvo de outro (não pronto), salvo
    do próprio (`null`), finalizado, cancelado;
  - `'entregarPorQr envia a assinatura como \\x + hex'`, com `rpcEntregarPorQr` falso que
    captura o argumento.
- [ ] **Step 2: Ver falhar.** Run: `cd app && flutter test test/entrega_qr_test.dart`. Expected:
  FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar a suíte inteira do app e o analyze.** Expected: 236 + novos testes
  passando, no máximo 42 avisos.
  - Se um teste de tempo de relógio falhar sob carga, rode de novo isolado antes de concluir.
- [ ] **Step 5: Commit** `feat(app): codigo do QR no celular e decisão da leitura`.

---

### Task 6: App — telas de leitura e de entrega pelo servidor

**Files:**
- Modify: `app/pubspec.yaml`: `mobile_scanner`, na versão estável mais recente que
  `flutter pub add` resolver.
- Modify: `app/android/app/src/main/AndroidManifest.xml`: acrescentar
  `android.permission.CAMERA`.
- Create: `app/lib/pages/ler_etiqueta_page.dart` e `app/lib/pages/entrega_qr_page.dart`.
- Modify: `app/lib/pages/home_page.dart` e `app/lib/pages/pedidos_page.dart`: botão "Ler
  etiqueta" com `Icons.qr_code_scanner`.
- Test: `app/test/telas_entrega_qr_test.dart`

**Interfaces:**
- Consumes: `decidirDestinoDaLeitura`, `buscarPedidoPorQr`, `entregarPorQr`, `PedidoQr`,
  `FalhaEntregaQr` (Tarefa 5), `AssinaturaPage`, que devolve PNG em `Uint8List`, e
  `PedidoEditPage`.
- Produces:
  - `LerEtiquetaPage({Stream<String>? leituras})`. Em teste, `leituras` substitui a câmera; sem
    ele, usa `MobileScanner`.
    - A página trava depois da primeira leitura e só volta a ler quando a tela de destino fecha
      ou depois de uma mensagem de erro (Review Focus 1).
  - `EntregaQrPage({required String codigoQr, PedirAssinatura? pedirAssinatura})`.
    - Carrega `buscarPedidoPorQr`.
    - Mostra número, "Pedido do vendedor <código>" quando não é do próprio vendedor, cliente,
      cidade e itens "N×".
    - Com `motivoSemEntrega` preenchido, mostra o motivo e não mostra o botão.
    - Sem motivo, mostra "Registrar entrega": pede a assinatura, chama `entregarPorQr`, mostra
      "Entrega registrada." e fecha.

Caminhos da `LerEtiquetaPage`:
- `AbrirPedidoLocal`: abre `PedidoEditPage` com o pedido, no mesmo modo que "Registrar entrega"
  abre hoje em Meus pedidos. Use a mesma chamada que `pedidos_page.dart` já faz, sem duplicar
  regra.
- `AbrirEntregaServidor`: abre `EntregaQrPage`.
- `QrInvalido`: mostra "Esta etiqueta não é de um pedido da MilkDim." e volta a ler.
- `SemInternet`: mostra a mensagem de sem internet e volta a ler.
- Permissão de câmera negada (erro do `MobileScanner`): mostra "Libere a câmera nas
  configurações do Android para ler etiquetas." com um botão "Tentar de novo".

- [ ] **Step 1: Testes** em `app/test/telas_entrega_qr_test.dart`:
  - `'três leituras iguais em sequência abrem uma tela só'`;
  - `'QR inválido mostra a mensagem e continua lendo'`;
  - `'EntregaQrPage de pedido pronto de outro vendedor mostra o aviso, itens e Registrar entrega'`;
  - `'Registrar entrega com assinatura chama entregarPorQr uma vez e mostra "Entrega registrada."'`;
  - `'pedido salvo de outro vendedor mostra "Este pedido ainda não está pronto para entrega." sem botão'`;
  - `'falha na entrega mostra a mensagem e mantém a tela'`;
  - `'Home e Meus pedidos têm o botão Ler etiqueta'`.
- [ ] **Step 2: Ver falhar, implementar e ver passar.**
- [ ] **Step 3: Build de conferência.** Run: `cd app && flutter build apk --debug`. Expected:
  build ok, o que confere que o `mobile_scanner` compila no Android do projeto.
- [ ] **Step 4: Suíte inteira e analyze do app.**
- [ ] **Step 5: Commit** `feat(app): ler etiqueta e registrar entrega pelo QR`.

---

### Task 7: Roteiro de implantação e teste de ponta a ponta

**Files:**
- Create: `docs/implantacao-fase-b.md`, no estilo de `docs/implantacao-fase-a.md`.

Conteúdo obrigatório:
1. **Pré-requisito:** PR #3 (Fase A) mesclado.
2. **Banco:** mostrar o SQL, rodar o teste em rollback e aplicar com OK.
3. **Controle novo na fábrica:**
   - escolher o tamanho da etiqueta;
   - imprimir uma etiqueta de teste.
4. **APK novo em todos os vendedores.**
5. **Teste de ponta a ponta**, sem apagar nada no fim, com dois vendedores (A e B):
   1. A envia um pedido;
   2. a fábrica dá "Produção concluída" e imprime a etiqueta;
   3. B lê o QR com o pedido ainda em aberto, usando outro pedido, e vê "ainda não está pronto";
   4. B lê o QR do pedido pronto e registra a entrega;
   5. o Controle mostra "Entregue por B (outro vendedor)";
   6. A sincroniza e vê o pedido entregue;
   7. A lê o QR de um pedido próprio sem internet e registra a entrega;
   8. ler de novo um QR já entregue mostra "já foi entregue";
   9. alterar um pedido pronto mostra "Etiqueta desatualizada" depois de pronto de novo.
6. **Problemas comuns:**
   - câmera negada;
   - impressora sem driver;
   - etiqueta cortada porque o tamanho escolhido está errado.

- [ ] **Step 1: Escrever** e conferir que não há nomes reais nem ref do projeto:
  `grep -niE "supabase\.co" docs/implantacao-fase-b.md` não devolve nada. O controlador confere o
  ref do projeto.
- [ ] **Step 2: Commit** `docs: roteiro de implantação da Fase B`.
