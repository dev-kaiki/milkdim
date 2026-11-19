# MilkDim — Supabase Auth e banco fechado — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o login por senha em tabela pelo Supabase Auth nos dois apps, fechar o banco para a chave anônima e parar de perder pedidos finalizados offline.

**Architecture:** Banco em duas migrações — fase 1 aditiva (contas Auth, funções, constraint) e fase 3 que fecha (políticas, revoga `anon`, apaga senhas). Entre elas, os apps novos são instalados por cima dos atuais. O app do funcionário passa a guardar a sessão do Supabase e um flag `pendente_envio` no SQLite; o controle loga por Auth e gerencia vendedores por RPC.

**Tech Stack:** Flutter 3.41 / Dart 3.11, `supabase_flutter` ^2.3.3, `sqflite` + `sqflite_common_ffi` (testes), Postgres 17 no projeto Supabase MilkDim, Supabase MCP (`execute_sql`, `apply_migration`).

**Spec:** `docs/superpowers/specs/2026-11-18-seguranca-auth-design.md`

## Global Constraints

- E-mail técnico: `<codigo>@milkdim.local` (código com `trim()` e `toLowerCase()`, sem completar zeros).
- Admin: `<usuario>@milkdim.local` com `raw_app_meta_data.role = 'admin'`; se o usuário digitar algo com `@`, usar como está.
- Senha mínima de 6 caracteres só em `app_criar_vendedor` e `app_alterar_senha_vendedor`; a migração copia as senhas atuais como estão (0003 tem 4).
- Desativar = `banned_until = timestamptz '2999-12-31'`; reativar = `null`.
- Os oito campos de token de `auth.users` (`confirmation_token`, `recovery_token`, `email_change`, `email_change_token_new`, `email_change_token_current`, `phone_change`, `phone_change_token`, `reauthentication_token`) gravados como `''`, nunca NULL; `phone` fica NULL.
- Funções `SECURITY DEFINER` sempre com `set search_path` fixo.
- `applicationId` não muda: `com.example.milkdim_app`, `com.example.milkdim_admin`.
- Nenhuma senha, chave ou URL do Supabase em arquivo versionado. Build com `--dart-define-from-file=dart_defines.json` (no `.gitignore`).
- Nenhum `git push` antes da fase 3 aplicada.
- Nenhuma migração aplicada no banco real sem mostrar o SQL ao Kaiki e receber OK no chat.
- Pedido local nunca é apagado por login, logout, sessão expirada ou sync.
- Toda mensagem de commit termina com a linha `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Primeiro acesso sem internet depois da atualização** (ainda não há sessão): a tela de login deve dizer "O primeiro acesso precisa de internet" em vez de "Login ou senha inválidos". → teste em Task 6 (`mensagemErroLogin`).
2. **Sessão salva vencida e celular offline:** o app tem que abrir na Home. Decidir a rota por `currentSession != null`, nunca por `isExpired`. → teste em Task 5 (`rotaInicial`).
3. **Código digitado com espaço ou maiúscula** (`' 0003 '`): vira `0003@milkdim.local`. Admin digitando o e-mail inteiro não ganha `@milkdim.local` duplicado. → testes em Task 5 e Task 7.
4. **Pedido finalizado offline editado depois de já sincronizado** (id < 1e9, `pendente_envio = 1`): a sync não pode sobrescrever a edição com a versão do servidor. → teste em Task 5 (`aplicarPedidosRemotos`).
5. **Upsert de pedido sob a RLS nova:** vendedor reenviando o próprio `(numero, vendedor_codigo)` atualiza; com código de outro vendedor falha; inserir cliente e ler o id de volta funciona. → asserções em Task 3.

---

### Task 1: Linha de base, testes antigos e credenciais por arquivo

**Files:**
- Create: `app/test/rascunho_persistencia_test.dart` (copiar de `D:\AndroidStudioProjects\MilkDim_App\test\`)
- Create: `dart_defines.example.json`
- Modify: `.gitignore`
- Modify: `README.md` (seção "Running it")

**Interfaces:**
- Produces: `dart_defines.json` (local, ignorado) com `SUPABASE_URL` e `SUPABASE_ANON_KEY`; todos os `flutter run/build` do plano usam `--dart-define-from-file=../dart_defines.json`.

- [ ] **Step 1: Commit do estado atual do clone, sem mudanças**

```bash
git status   # só deve aparecer docs/superpowers/
git add docs/superpowers/specs docs/superpowers/plans
git commit -m "docs: desenho e plano da migracao para Supabase Auth"
```

- [ ] **Step 2: Copiar o teste antigo e rodar**

Run: `cd app && flutter pub get && flutter test`
Expected: PASS (`rascunho salvo sobrevive a um sync com id remoto baixo`). Se falhar, parar: a linha de base não bate com o D:.

- [ ] **Step 3: Criar `dart_defines.example.json` com as duas chaves vazias, adicionar `dart_defines.json` ao `.gitignore`, criar o `dart_defines.json` real localmente a partir do `D:\AndroidStudioProjects\MilkDim_App\lib\main.dart` (URL e anon key) e trocar no README o exemplo para `--dart-define-from-file`.**

- [ ] **Step 4: Verificar que nada secreto ficou versionado**

Run: `git status --porcelain && git grep -n "eyJhbGci\|<ref do projeto Supabase MilkDim>" -- . ':!docs'`
Expected: `dart_defines.json` não aparece; o grep não acha nada.

- [ ] **Step 5: Commit**

```bash
git add app/test .gitignore dart_defines.example.json README.md
git commit -m "chore: teste de rascunho e credenciais por dart_defines.json"
```

---

### Task 2: Migração fase 1 (aditiva)

**Files:**
- Create: `supabase/migrations/20261118000001_fase1_auth_aditivo.sql`
- Create: `supabase/tests/fase1_test.sql`

**Interfaces:**
- Produces (SQL, schema `public`):
  - colunas `vendedores.auth_user_id uuid unique references auth.users(id) on delete set null`, `vendedores.is_admin boolean not null default false`
  - `constraint pedidos_numero_vendedor_key unique (numero, vendedor_codigo)`
  - `app_criar_usuario_auth(p_email text, p_hash text, p_app_meta jsonb, p_user_meta jsonb, p_ativo boolean) returns uuid` — interna; `revoke execute ... from public, anon, authenticated`
  - `app_is_admin() returns boolean` (stable): sem `role` no JWT → true; `auth.jwt()->'app_metadata'->>'role' = 'admin'` → true; vendedor ligado a `auth.uid()` com `is_admin` → true
  - `app_meu_codigo() returns text` (stable): `codigo` de `vendedores` onde `auth_user_id = auth.uid()`
  - `app_criar_vendedor(p_codigo text, p_nome text, p_senha text, p_anotacao text default null, p_ativo boolean default true, p_is_admin boolean default false) returns integer`
  - `app_alterar_senha_vendedor(p_codigo text, p_senha text) returns void`
  - `app_definir_ativo_vendedor(p_codigo text, p_ativo boolean) returns void` (atualiza `vendedores.ativo` e `banned_until`)
  - `app_excluir_vendedor(p_codigo text) returns void` (prefere `auth_user_id`; cai para o e-mail)
  - `app_migrar_admin(p_usuario text, p_acesso_admin_id bigint) returns uuid` — copia `crypt(acesso_admin.senha)`, `app_meta = {"provider":"email","providers":["email"],"role":"admin"}`; só executável sem JWT
  - bloco final: para cada vendedor sem `auth_user_id`, cria a conta com `crypt(senha, gen_salt('bf'))`, `user_meta = {codigo, nome}`, ativo conforme a linha, e grava `auth_user_id`
  - As quatro `app_*_vendedor`, `app_is_admin`, `app_meu_codigo`: `grant execute to authenticated`; as de gestão começam com `if not app_is_admin() then raise exception ... using errcode = '42501'`.
- Referência viva: funções `app_criar_tecnico`, `app_alterar_senha_tecnico`, `app_definir_ativo_tecnico`, `app_excluir_tecnico` no projeto `nqwocdqaphapaojixslb` (ler com `pg_get_functiondef`).

- [ ] **Step 1: Escrever `supabase/tests/fase1_test.sql`** — blocos `do $$ ... $$` que dão `raise exception` quando falham:
  - `select count(*) from vendedores where auth_user_id is null` = 0
  - para cada vendedor, existe `auth.users` com `email = lower(codigo)||'@milkdim.local'` e `encrypted_password = crypt(v.senha, encrypted_password)`
  - `confirmation_token = ''` e `phone is null` nessas contas
  - `app_migrar_admin('teste_admin', 1)` cria conta com `raw_app_meta_data->>'role' = 'admin'` e senha igual à de `acesso_admin` id 1
  - com `set local role authenticated` e `request.jwt.claims` de um vendedor sem `is_admin`: `app_criar_vendedor('9999','X','123456')` falha com SQLSTATE `42501`
  - com claims de admin: `app_criar_vendedor('9999','X','12345')` falha (senha curta); `app_criar_vendedor('9999','X','123456')` funciona; `app_definir_ativo_vendedor('9999', false)` deixa `banned_until = '2999-12-31'`; `app_excluir_vendedor('9999')` apaga linha e usuário
  - inserir pedido com `numero` e `vendedor_codigo` já existentes falha com `23505`

- [ ] **Step 2: Rodar o teste antes da migração existir**

Run (Supabase MCP `execute_sql`, projeto Supabase MilkDim): `begin;` + conteúdo de `fase1_test.sql` + `rollback;`
Expected: FAIL (coluna `auth_user_id` não existe).

- [ ] **Step 3: Escrever `20261118000001_fase1_auth_aditivo.sql`** com o que está em Interfaces. Não mexe em políticas, não apaga nada.

- [ ] **Step 4: Rodar migração + teste dentro de transação**

Run (MCP `execute_sql`): `begin;` + migração + `fase1_test.sql` + `rollback;`
Expected: sem erro. Conferir depois: `select count(*) from auth.users` = 0 (nada ficou gravado).

- [ ] **Step 5: Commit** (não aplicar no banco real ainda — isso é a Task 9)

```bash
git add supabase/
git commit -m "feat(db): fase 1 aditiva — contas Auth, funcoes de vendedor e constraint unica"
```

---

### Task 3: Migração fase 3 (fecha o banco)

**Files:**
- Create: `supabase/migrations/20261118000002_fase3_fechar_banco.sql`
- Create: `supabase/tests/fase3_test.sql`

**Interfaces:**
- Consumes: tudo da Task 2.
- Produces: apaga as 17 políticas atuais (nomes em `pg_policies`: `public_select_insert`, `anon read/insert/update/delete <tabela>`, `anon select vendedores`, `Public read for acesso_admin`); cria políticas `to authenticated` conforme a tabela do spec; `revoke all on all tables in schema public from anon`; `revoke execute on all functions in schema public from anon`; `alter table vendedores drop column senha`; `drop table acesso_admin`; `drop function app_migrar_admin`.
- Políticas de `pedidos`: select `vendedor_codigo = app_meu_codigo() or app_is_admin()`; insert `with check (vendedor_codigo = app_meu_codigo() or app_is_admin())`; update `using` e `with check` iguais; delete `app_is_admin()`.

- [ ] **Step 1: Escrever `fase3_test.sql`** — com claims do vendedor 0002 (sub = seu `auth_user_id`, `role = authenticated`):
  - `select count(*) from pedidos where vendedor_codigo <> '0002'` = 0, e `count(*)` > 0
  - `insert into pedidos (numero, vendedor_codigo, ...) values ('teste-x','0003', ...)` falha (`42501`)
  - insert de pedido próprio `('teste-y','0002')` funciona; `insert ... on conflict (numero, vendedor_codigo) do update set total = 1` na mesma chave funciona
  - `delete from pedidos where numero = 'teste-y'` não apaga (0 linhas)
  - `insert into clientes (nome) values ('teste') returning id` devolve id; `update clientes set nome = 'x'` afeta 0 linhas
  - `insert into produtos (nome) values ('x')` falha
  - `select count(*) from vendedores` = 1
  - com `set local role anon`: `select count(*) from pedidos` falha com permissão negada
  - com claims de admin (`app_metadata.role = 'admin'`): vê os 372+ pedidos e consegue apagar `teste-y`
  - coluna `vendedores.senha` e tabela `acesso_admin` não existem

- [ ] **Step 2: Rodar só o teste (sem fase 3)**

Run (MCP): `begin;` + fase 1 (se ainda não aplicada) + `fase3_test.sql` + `rollback;`
Expected: FAIL (vendedor ainda vê pedidos dos outros).

- [ ] **Step 3: Escrever a migração fase 3.**

- [ ] **Step 4: Rodar fase 1 (se não aplicada) + fase 3 + teste**

Run (MCP): `begin;` + fase1 + fase3 + `fase3_test.sql` + `rollback;`
Expected: sem erro; depois, `select count(*) from pg_policies where policyname = 'public_select_insert'` ainda = 4 (nada persistiu).

- [ ] **Step 5: Commit**

```bash
git add supabase/
git commit -m "feat(db): fase 3 — politicas por usuario autenticado e remocao das senhas"
```

---

### Task 4: App — SQLite v16 e controle de pedidos pendentes

**Files:**
- Modify: `app/lib/utils/db.dart`
- Test: `app/test/pendentes_test.dart`

**Interfaces:**
- Produces (em `db.dart`):
  - `_dbVersion = 16`; `pedidos.pendente_envio INTEGER NOT NULL DEFAULT 0`; `vendedores` recriada sem `senha` (colunas `id, codigo UNIQUE, nome, ativo`), mantendo as linhas.
  - Upgrade < 16: `pendente_envio = 1` onde `status = 'finalizado' AND id >= kLocalIdBase`.
  - `salvarPedidoLocal` e `atualizarPedidoLocal` gravam `pendente_envio = status == 'finalizado' ? 1 : 0`.
  - `Future<List<Map<String, dynamic>>> listarPedidosPendentesEnvio(String vendedorCodigo)` — `pendente_envio = 1`, ordem `datetime(datahora) ASC`.
  - `Future<int> contarPedidosPendentesEnvio(String vendedorCodigo)`
  - `Future<Set<String>> codigosComPendentesEnvio()`
  - `Future<void> salvarVendedorLocal(Map<String, dynamic> v)` — grava só `codigo, nome, ativo` e apaga as linhas de outros códigos.
  - `loginLocalVendedor` removida.
  - Apaga `listarPedidosPendentes` (substituída).

- [ ] **Step 1: Testes que falham**

```dart
test('v16 marca finalizados locais como pendentes e remove senha', ...);
  // cria banco v15 à mão com vendedores(senha) e pedidos: (id 1e9+1, finalizado), (id 5, finalizado), (id 1e9+2, salvo)
  // abre getDb(); expect PRAGMA table_info(vendedores) sem 'senha'
  // expect listarPedidosPendentesEnvio('0003') só com id 1e9+1
test('salvar finalizado marca pendente; salvo não', ...);
test('contarPedidosPendentesEnvio filtra pelo vendedor', ...);
test('codigosComPendentesEnvio devolve {0003} quando só 0003 tem pendente', ...);
test('salvarVendedorLocal deixa só o vendedor logado', ...);
```

- [ ] **Step 2: Run** `cd app && flutter test test/pendentes_test.dart` → FAIL
- [ ] **Step 3: Implementar em `db.dart`** (recriar `vendedores` com `CREATE TABLE vendedores_new` + `INSERT ... SELECT` + `DROP` + `ALTER ... RENAME`, dentro do `onUpgrade`; o `onOpen` não pode readicionar `senha`).
- [ ] **Step 4: Run** `flutter test` → PASS (inclui o teste antigo de rascunho)
- [ ] **Step 5: Commit** `feat(app): pendente_envio no SQLite v16 e vendedores sem senha`

---

### Task 5: App — sessão, envio de pendentes e sync filtrada

**Files:**
- Create: `app/lib/utils/auth.dart`
- Modify: `app/lib/utils/supabase_helper.dart`
- Test: `app/test/auth_test.dart`, `app/test/envio_pendentes_test.dart`

**Interfaces:**
- Consumes: Task 4 (`listarPedidosPendentesEnvio`, `codigosComPendentesEnvio`, `salvarVendedorLocal`).
- Produces (`auth.dart`):
  - `String emailDoCodigo(String codigo)` → `'${codigo.trim().toLowerCase()}@milkdim.local'`
  - `enum RotaInicial { login, home }`; `RotaInicial rotaInicial({required bool temSessao})`
  - `class LoginRecusado implements Exception { final String mensagem; }`
  - `Future<Map<String, dynamic>> entrar(String codigo, String senha)` — recusa com `LoginRecusado('Há pedidos do vendedor X aguardando envio neste aparelho.')` se `codigosComPendentesEnvio()` tem código diferente; `signInWithPassword`; lê `vendedores` (`id, codigo, nome, ativo`) por `auth_user_id = user.id`; `salvarVendedorLocal`; devolve a linha.
  - `Future<void> sair()` — `LoginRecusado` se houver pendente do vendedor; senão `signOut()`.
  - `Future<Map<String, dynamic>?> vendedorLocal()` — a única linha de `vendedores` no SQLite.
- Produces (`supabase_helper.dart`):
  - `Future<({int enviados, int falhas})> subirPedidosPendentes({required String vendedorCodigo, Future<void> Function(Map<String, dynamic>) enviar = salvarPedidoSupabase})`
  - `sincronizarPedidos({required String vendedorCodigo})` — `.eq('vendedor_codigo', vendedorCodigo)`; pula remotos cujo par local (`numero, vendedor_codigo`) tem `pendente_envio = 1`.
  - `sincronizarTudo({required String vendedorCodigo})` = clientes + produtos + pedidos + `subirPedidosPendentes`; devolve `bool`.
  - Remover: `sincronizarVendedores`, `inserirVendedorSupabase`, `inserirProdutoSupabase`, `loginSupabaseVendedor`.
  - A gravação local do retorno do servidor em `salvarPedidoSupabase` grava `pendente_envio = 0`.

- [ ] **Step 1: Testes que falham**

```dart
expect(emailDoCodigo(' 0003 '), '0003@milkdim.local');
expect(emailDoCodigo('ABC'), 'abc@milkdim.local');
expect(rotaInicial(temSessao: true), RotaInicial.home);   // mesmo vencida/offline
expect(rotaInicial(temSessao: false), RotaInicial.login);
// envio_pendentes_test (ffi): 2 pendentes de 0003, 1 de 0002;
// subirPedidosPendentes(vendedorCodigo: '0003', enviar: fake) chama fake 2x, nunca com 0002
// fake que lança na 2ª chamada → (enviados: 1, falhas: 1) e o 2º continua pendente_envio = 1
// sincronizarPedidos não sobrescreve pedido local com pendente_envio = 1 — testar a função
//   interna aplicarPedidosRemotos(List<Map> remotos) extraída de sincronizarPedidos
```

- [ ] **Step 2: Run** `flutter test test/auth_test.dart test/envio_pendentes_test.dart` → FAIL
- [ ] **Step 3: Implementar** (extrair `Future<void> aplicarPedidosRemotos(List<Map<String, dynamic>> remotos)` de `sincronizarPedidos` para testar sem rede)
- [ ] **Step 4: Run** `flutter test` → PASS
- [ ] **Step 5: Commit** `feat(app): login por Supabase Auth e reenvio de pedidos pendentes`

---

### Task 6: App — telas

**Files:**
- Modify: `app/lib/main.dart`, `app/lib/pages/login_page.dart`, `app/lib/pages/home_page.dart`, `app/lib/pages/configuracoes_page.dart`
- Delete: `app/lib/pages/novo_vendedor_page.dart`, `app/lib/pages/novo_produto_page.dart`
- Test: `app/test/login_msg_test.dart`

**Interfaces:**
- Consumes: Task 5 (`rotaInicial`, `entrar`, `sair`, `vendedorLocal`, `sincronizarTudo`, `subirPedidosPendentes`), Task 4 (`contarPedidosPendentesEnvio`).
- Produces: `String mensagemErroLogin(Object erro, {required bool online})` em `login_page.dart`:
  - `LoginRecusado` → a mensagem dele
  - offline → `'O primeiro acesso precisa de internet.'`
  - `AuthException` com status 400 → `'Código ou senha inválidos.'`
  - banido (mensagem contém `banned`) → `'Vendedor inativo. Fale com o administrador.'`
  - outro → `'Não foi possível entrar. Tente de novo.'`

- [ ] **Step 1: Teste de `mensagemErroLogin` para os cinco casos** → FAIL
- [ ] **Step 2: Implementar as telas:**
  - `main.dart`: tira a sync anônima do `initState`; `home:` escolhe por `rotaInicial(temSessao: Supabase.instance.client.auth.currentSession != null)`; se home, carrega `vendedorLocal()`; escuta `onAuthStateChange` e, em `signedOut`, vai para o login sem tocar no SQLite.
  - `login_page.dart`: usa `entrar`; mantém o diálogo de sync obrigatória de 7 dias, agora rodado depois do login e na abertura da Home (`ultima_sincronizacao` no SharedPreferences, como hoje).
  - `home_page.dart`: remove `_adminPin` e o diálogo de senha; engrenagem abre Configurações direto; mostra `"$n pedidos aguardando envio"` quando `n > 0` (com botão "Enviar agora"); botão "Sair" que mostra a mensagem de `LoginRecusado` quando bloqueado; ao abrir com internet chama `subirPedidosPendentes`.
  - `configuracoes_page.dart`: só "Sincronizar" e "Cadastrar novo cliente".
- [ ] **Step 3: Run** `flutter test && flutter analyze` → PASS, sem erros (avisos antigos podem ficar)
- [ ] **Step 4: Manual (Windows desktop, banco ainda aberto + fase 1 aplicada no banco de teste da Task 9):** `flutter run -d windows --dart-define-from-file=../dart_defines.json` — entrar com 0001, ver Home, fechar e abrir sem rede → Home direto.
- [ ] **Step 5: Commit** `feat(app): telas usam sessao do Supabase; sem PIN; cadastros de vendedor e produto removidos`

---

### Task 7: Controle — login por Auth

**Files:**
- Create: `admin/lib/services/auth_admin.dart`
- Modify: `admin/lib/main.dart`, `admin/lib/pages/login_page.dart`, `admin/lib/pages/home_page.dart`
- Test: `admin/test/auth_admin_test.dart`

**Interfaces:**
- Produces:
  - `String emailDoUsuario(String usuario)` — com `@` devolve `trim()`; senão `'${usuario.trim().toLowerCase()}@milkdim.local'`
  - `Future<void> entrarAdmin(String usuario, String senha)` — `signInWithPassword`; `rpc('app_is_admin')`; se `false`, `signOut()` e lança `AcessoNegado`
  - `class AcessoNegado implements Exception` — mensagem `'Sem acesso ao controle.'`
  - `Future<void> sairAdmin()`
- Remove `admin_logged` do SharedPreferences; `initialRoute` decidido por `currentSession != null`; `HomePage._ensureLogged` usa a sessão.

- [ ] **Step 1: Testes** `emailDoUsuario('kaiki') == 'kaiki@milkdim.local'`, `emailDoUsuario(' Kaiki ') == 'kaiki@milkdim.local'`, `emailDoUsuario('kaiki@milkdim.local') == 'kaiki@milkdim.local'` → FAIL
- [ ] **Step 2: Implementar**; tela de login ganha campo "Usuário" acima de "Senha".
- [ ] **Step 3: Run** `cd admin && flutter test && flutter analyze` → PASS
- [ ] **Step 4: Commit** `feat(admin): login por Supabase Auth com verificacao de admin`

---

### Task 8: Controle — vendedores por RPC e limpeza do service

**Files:**
- Modify: `admin/lib/tabs/vendedores_tab.dart`, `admin/lib/services/supabase_service.dart`, `admin/lib/models/vendedor.dart`
- Test: `admin/test/supabase_service_test.dart`

**Interfaces:**
- Consumes: RPCs da Task 2.
- Produces em `supabase_service.dart`:
  - `String filtroBuscaClientes(String termo)` → `'nome.ilike.%t%,nome_fantasia.ilike.%t%,cpf_cnpj.ilike.%t%,telefone.ilike.%t%,cidade.ilike.%t%,whatsapp.ilike.%t%,email.ilike.%t%'`
  - `String filtroBuscaProdutos(String termo)` → `nome`, `descricao`, `codigo`
  - `String filtroBuscaVendedores(String termo)` → `nome`, `codigo`
  - `String filtroBuscaPedidos(String termo)` → `vendedor_nome`, `cliente_nome`, `cliente_nome_fantasia`, `numero`
  - `Future<void> criarVendedor({required String codigo, required String nome, required String senha, String? anotacao, bool ativo = true, bool isAdmin = false})` → `rpc('app_criar_vendedor', ...)`
  - `Future<void> alterarSenhaVendedor(String codigo, String senha)`, `Future<void> definirAtivoVendedor(String codigo, bool ativo)`, `Future<void> excluirVendedor(String codigo)`
  - Apagados: `_*ModelToDb`, `_coerceToMap`, `inserirPedido`, `atualizarPedido`, `autenticarVendedor`, `autenticarAdmin`, `RepoFailure` só se ficar sem uso.
  - Os `_*DbToModel` perdem os fallbacks acentuados (`m['código']` etc.).
- `vendedores_tab.dart`: criar → `criarVendedor`; editar → `update({'nome', 'anotacao'})` direto; item de menu novo "Trocar senha" → `alterarSenhaVendedor`; ativar/desativar → `definirAtivoVendedor`; excluir → `excluirVendedor`. Campo de senha só no diálogo de criar. `Vendedor` perde o campo `senha`.

- [ ] **Step 1: Testes dos quatro `filtroBusca*`**: cada um contém só colunas do schema real e nenhuma das strings `código`, `preço`, `número`, `WhatsApp`, `e-mail`, `nome_do_cliente`, `descrição` → FAIL
- [ ] **Step 2: Implementar**
- [ ] **Step 3: Run** `flutter test && flutter analyze` → PASS; `grep -rn "código\|preço\|número\|anotação\|descrição\|WhatsApp'\|e-mail'" admin/lib/services` → vazio
- [ ] **Step 4: Commit** `refactor(admin): vendedores por RPC e remocao das colunas inexistentes`

---

### Task 9: Implantação (fases 1, 2 e 3)

**Files:**
- Create: `docs/implantacao-auth.md` (roteiro com as caixas abaixo, para o Kaiki seguir com os vendedores)

Cada passo de banco: mostrar o SQL ao Kaiki e esperar OK no chat antes de aplicar.

- [ ] **Step 1: Fase 1 no banco real** — `apply_migration` com `20261118000001_fase1_auth_aditivo.sql`. Perguntar ao Kaiki o nome de usuário de cada admin e rodar `select app_migrar_admin('<usuario1>', 1); select app_migrar_admin('<usuario2>', 2);`.
  Verify: `select count(*) from vendedores where auth_user_id is null` = 0; `select count(*) from auth.users` = 6. Os apps atuais continuam funcionando (abrir o app velho e listar pedidos).
- [ ] **Step 2: Builds**
  - `cd app && flutter build apk --release --dart-define-from-file=../dart_defines.json`
  - `cd admin && flutter build windows --release --dart-define-from-file=../dart_defines.json` e `flutter build apk --release --dart-define-from-file=../dart_defines.json`
  Expected: builds sem erro; `strings` do APK não contém o PIN fixo de administrador.
- [ ] **Step 3: Teste de ponta a ponta com a conta 0001** (banco ainda aberto): login, pedido finalizado com rede, pedido finalizado em modo avião (aparece "1 pedido aguardando envio"), religar a rede → enviado e contador some; conferir no banco.
- [ ] **Step 4: Instalação** — Kaiki instala por cima nos celulares do 0002 e 0003 e o controle nos aparelhos das duas pessoas de admin. Em cada celular: login, Home mostra "0 pedidos aguardando envio" (se mostrar N > 0, esperar enviar).
  Verify: `select email, last_sign_in_at from auth.users` — 0002, 0003 e os dois admins com `last_sign_in_at` depois da instalação.
- [ ] **Step 5: Fase 3 no banco real** — só com o Step 4 confirmado. `apply_migration` com `20261118000002_fase3_fechar_banco.sql`.
  Verify: `select count(*) from pg_policies where 'anon' = any(roles) or 'public' = any(roles)` = 0; nos celulares, criar um pedido e ver no controle.
- [ ] **Step 6: Publicar** — atualizar o README (tirar "never had real users" só depois de o Kaiki decidir o texto), `git push`.
