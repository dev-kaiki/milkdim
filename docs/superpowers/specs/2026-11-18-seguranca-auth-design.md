# MilkDim — login por Supabase Auth e banco fechado

Data: 18/11/2026 · Escopo: `app/` (funcionário) e `admin/` (controle) · Projeto Supabase MilkDim

## Por que

O cliente vai pedir etiquetas e controle de expedição dos pedidos. Antes disso os dois
apps precisam de uma base confiável: hoje qualquer pessoa com a chave anônima — que vai
dentro de todo APK — lê, altera e apaga os 372 pedidos, lê a senha do admin e as senhas
dos vendedores. Um controle de "etiqueta emitida" construído em cima disso não vale nada.

## Situação atual (medida em 18/11/2026)

- Banco: `clientes` 48, `produtos` 16, `vendedores` 4 (0001, 0002, 0003, 700122), `pedidos` 372
  (todos `status = 'finalizado'`; 0002 e 0003 fazem quase todos), `acesso_admin` 2.
- RLS ligada em tudo, mas com política `public_select_insert` `FOR ALL USING (true)` para o
  papel `public` em `clientes`, `pedidos`, `produtos`, `vendedores`, e leitura pública em
  `acesso_admin`. Na prática, aberto.
- Senhas em texto puro em `vendedores.senha` e `acesso_admin.senha`. O vendedor 0003 tem senha
  de 4 caracteres.
- Nenhum `(numero, vendedor_codigo)` repetido nem `numero` nulo nos pedidos; não existe
  constraint única no servidor (o SQLite local tem `ux_pedidos_num_vend`).
- Views `clientes_com_ultimo_pedido` e `pedidos_with_created_at` já são `security_invoker=on`.
- App do funcionário: login offline contra a tabela local `vendedores` (senha em texto puro no
  SQLite), sync obrigatória a cada 7 dias, Configurações protegidas pelo PIN fixo de administrador
  (publicado neste repositório). A sync baixa **todos** os pedidos de todos os vendedores.
- App de controle: login só com senha, contra `acesso_admin`; flag `admin_logged` no
  SharedPreferences. Abas escrevem direto nas tabelas. `supabase_service.dart` tem mapas
  `*ModelToDb` e buscas com colunas acentuadas que não existem (`"código"`, `"preço"`,
  `"número"`, `"WhatsApp"`, `"e-mail"`…) — código morto que quebra se for chamado.
- `applicationId`: `com.example.milkdim_app` e `com.example.milkdim_admin`.

## Objetivos

1. Só usuário autenticado acessa o banco; a chave anônima sozinha não lê nem escreve nada.
2. Vendedor vê e grava só os próprios pedidos; admin vê e gerencia tudo.
3. Nenhuma senha em texto puro: nem no banco, nem no SQLite, nem no código.
4. O app do funcionário continua funcionando offline como hoje.
5. Os vendedores não precisam trocar de senha na migração.
6. Remover o código quebrado e ter a constraint única que a sync já espera.

## Não-objetivos

- Etiquetas, impressora e status de expedição (próxima etapa).
- Sync incremental por data — o volume é ~28 pedidos/mês e o filtro por vendedor já reduz o
  download ao necessário.
- Redesenho visual das telas.
- Trocar `applicationId` (perderia o SQLite com rascunhos e pedidos pendentes).

## Anti-objetivos (falha mesmo que funcione)

- Perder qualquer pedido finalizado que esteja só no celular de um vendedor.
- Deixar vendedor sem conseguir trabalhar no dia da troca.
- Qualquer senha ou chave embutida no código ou no repositório.

## Abordagens consideradas

- **A — Supabase Auth, mesmo padrão dos apps SMI (escolhida pelo Kaiki).** Uma conta por
  vendedor `<codigo>@milkdim.local`, uma conta para cada admin, RLS por `auth.uid()`,
  cadastro/senha/ativação por RPC `SECURITY DEFINER`. Padrão já rodando no projeto `Smi_App`
  (`app_criar_tecnico`, `app_alterar_senha_tecnico`, `app_definir_ativo_tecnico`,
  `app_excluir_tecnico`, `app_pode_cadastrar_tecnico`).
- B — Tabelas fechadas e tudo por funções que recebem código+senha. Descartada: a senha viaja
  em toda chamada, continua em texto puro no celular para o login offline, e exige uma função
  por operação.
- C — Só esconder `acesso_admin` e `senha`. Descartada: pedidos continuam apagáveis por
  qualquer um.

## Desenho

### Banco

Novas colunas em `vendedores`: `auth_user_id uuid unique references auth.users(id)`,
`is_admin boolean not null default false`.

Funções (`SECURITY DEFINER`, `search_path` fixo), copiadas do padrão SMI trocando `@smi.local`
por `@milkdim.local` e `tecnicos` por `vendedores`:

- `app_is_admin()` — verdadeiro se o JWT traz `app_metadata.role = 'admin'` (marcado no
  `raw_app_meta_data` das contas de admin, que o usuário não consegue alterar) ou se a linha
  do vendedor logado tem `is_admin`; também verdadeiro sem JWT (SQL Editor).
- `app_meu_codigo()` — `codigo` do vendedor ligado a `auth.uid()`.
- `app_criar_vendedor(codigo, nome, senha, anotacao, ativo, is_admin)` — cria `auth.users` +
  `auth.identities` + linha em `vendedores`, já com `auth_user_id`. Mantém os oito campos de
  token como `''` (o GoTrue quebra com NULL — ver comentário na função SMI).
- `app_alterar_senha_vendedor(codigo, senha)`, `app_definir_ativo_vendedor(codigo, ativo)`
  (usa `banned_until = '2999-12-31'`), `app_excluir_vendedor(codigo)` (apaga também o usuário
  do Auth, preferindo `auth_user_id`).
- Senha mínima de 6 caracteres **só** para criar e trocar. A migração dos 4 vendedores atuais
  copia a senha que já existe, inclusive a de 4 dígitos do 0003, gravando direto com
  `crypt()`; o login funciona porque o GoTrue não valida tamanho no `signInWithPassword`.

Políticas (todas `to authenticated`; nada para `anon`):

| Tabela | Ler | Inserir | Alterar | Apagar |
|---|---|---|---|---|
| `clientes` | todos | todos | admin | admin |
| `produtos` | todos | admin | admin | admin |
| `vendedores` | a própria linha; admin tudo | só via RPC | admin (nome, anotação) | só via RPC |
| `pedidos` | os próprios (`vendedor_codigo = app_meu_codigo()`); admin tudo | os próprios | os próprios; admin tudo | admin |

`with check` em `pedidos` garante que o vendedor não grava pedido com código de outro.
`revoke all on all tables in schema public from anon`. Views continuam `security_invoker`.

Constraint `unique (numero, vendedor_codigo)` em `pedidos` — faz o upsert da "Tentativa A" do
app funcionar de primeira.

Saem no fim: coluna `vendedores.senha`, tabela `acesso_admin`, políticas antigas.

### App do funcionário (`app/`)

- Login: `signInWithPassword(email: '<codigo>@milkdim.local', senha)`. Depois do login, busca
  a própria linha em `vendedores` e guarda no SQLite **sem** senha.
- Abertura: se existe sessão salva (o `supabase_flutter` persiste e renova sozinho), vai
  direto para a Home, com ou sem internet. Login só na primeira vez em cada aparelho ou depois
  de "Sair". Botão "Sair" novo na Home.
- Regra dos 7 dias de sync continua, agora checada na abertura em vez de no login.
- **Pedidos presos no celular (bug que já existe hoje).** Quando o vendedor finaliza um pedido
  sem internet, `salvarPedidoSupabase` falha, o pedido fica no SQLite como `finalizado` com id
  ≥ 1e9 e nada tenta de novo: `subirPedidosPendentes()` existe mas ninguém a chama. O app novo
  chama essa função ao abrir com internet, depois do login e depois de cada sync, só para
  pedidos do vendedor logado. A Home mostra "N pedidos aguardando envio" enquanto houver algum.
- **Sessão encerrada pelo servidor** (vendedor desativado, excluído ou com senha trocada): o
  app nunca apaga pedidos locais. Vai para o login; se o mesmo vendedor entrar de novo, os
  pendentes sobem. Se outro vendedor tentar entrar num aparelho com pendentes de alguém,
  o login é recusado com aviso até os pendentes serem enviados pelo dono.
- "Sair" fica bloqueado enquanto houver pedido finalizado sem enviar.
- A sync anônima que hoje roda no `main.dart` antes do login sai; a sync só roda com sessão.
- Sync: clientes e produtos completos; pedidos só do vendedor (o RLS já filtra; o app também
  filtra para não depender só disso). `sincronizarVendedores` deixa de existir.
- Configurações: sem PIN. Ficam "Sincronizar" e "Cadastrar cliente". "Cadastrar vendedor" e
  "Cadastrar produto" saem (passam a ser só do controle). Apagar as telas
  `novo_vendedor_page.dart` e `novo_produto_page.dart`.
- SQLite: `_dbVersion` 16 remove a coluna `senha` de `vendedores` (recriando a tabela) e limpa
  as linhas de outros vendedores. Tabela `pedidos` intocada.

### App de controle (`admin/`)

- Login: campo de usuário + senha, `signInWithPassword`. Aceita as contas de admin e vendedores com
  `is_admin`. Se o login der certo mas `app_is_admin()` for falso, desloga e mostra
  "Sem acesso ao controle". Sai a flag `admin_logged`; vale a sessão do Supabase.
- Aba Vendedores: criar, trocar senha, ativar/desativar e excluir por RPC; editar nome e
  anotação por update direto. Campo de senha só aparece ao criar e em "Trocar senha".
- `supabase_service.dart`: apagar mapas acentuados, `inserirPedido`, `atualizarPedido`,
  `autenticarVendedor`, `autenticarAdmin`; buscas com `q` passam a usar os nomes reais.

### Credenciais e build

Os dois apps já leem `SUPABASE_URL`/`SUPABASE_ANON_KEY` por `--dart-define`. Adicionar
`--dart-define-from-file=dart_defines.json`, com `dart_defines.json` no `.gitignore` e um
`dart_defines.example.json` versionado. As cópias em `D:\AndroidStudioProjects` (com a chave
no código) deixam de ser usadas.

### Implantação em três fases

1. **Banco, sem quebrar nada:** colunas, funções, constraint única, contas Auth dos 4
   vendedores com as senhas atuais e as duas contas de admin. Políticas antigas continuam — apps velhos
   seguem funcionando.
2. **Apps novos:** gerar APK do funcionário e build do controle; instalar por cima (mesmo
   `applicationId`, o SQLite fica). O app velho não sabe reenviar pedidos presos, então quem
   recupera é o app novo, no primeiro login. Conferir no banco que cada vendedor entrou pelo
   app novo (`auth.users.last_sign_in_at`) **e** olhar a Home de cada celular: "0 pedidos
   aguardando envio".
3. **Fechar o banco:** só depois das duas conferências acima em todos os celulares. Trocar
   políticas, revogar `anon`, apagar `senha` e `acesso_admin`. A partir daqui o app velho
   para de funcionar.

Cada fase é um arquivo em `supabase/migrations/` aplicado separadamente, com o SQL mostrado ao
Kaiki antes.

## Decisões minhas (podem ser corrigidas)

- E-mail técnico `<codigo>@milkdim.local`, igual ao padrão SMI.
- **(Kaiki, 18/11)** Cada vendedor tem o próprio celular — um vendedor por aparelho.
- **(Kaiki, 18/11)** As duas senhas de `acesso_admin` são de pessoas diferentes: viram duas
  contas de admin, `<usuario>@milkdim.local`, cada uma com a senha que a pessoa já usa,
  copiada da tabela pelo SQL da fase 1 (nenhuma senha no repositório). O nome de usuário de
  cada uma é parâmetro da fase 1, perguntado ao Kaiki na hora de aplicar. No login do
  controle, quem digita só o usuário (sem `@`) tem `@milkdim.local` completado pelo app.
- Os 4 vendedores são migrados, inclusive 0001 e 700122. A fase 3 espera só pelos celulares
  de 0002 e 0003, que fizeram todos os pedidos dos últimos 30 dias; 0001 (3 pedidos, nenhum
  recente) e 700122 (nenhum pedido) não seguram o fechamento.
- Cadastro de vendedor e produto só no controle.
- Vendedor não altera nem apaga cliente; só cria.
- Vendedor não apaga pedido no servidor (rascunho local continua apagável).
- Manter `com.example.*` como `applicationId`.

- O repositório é público e este documento descreve o banco aberto: nada é publicado
  (`git push`) antes da fase 3.

## Para quem for construir decidir

- Como recriar a tabela `vendedores` no SQLite sem a coluna `senha`.
- Texto das mensagens de erro e da tela "Sem acesso ao controle".
- Se `pedidos_with_created_at` ainda é usada; se não, apagar.
