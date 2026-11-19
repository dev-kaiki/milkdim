# Novo visual — app do funcionário e Controle

Data: 19/11/2026 · Escopo: `app/`, `admin/` e um pacote novo `packages/milkdim_ui/`

## Por quê

O Kaiki quer que os dois apps pareçam mais profissionais e modernos. Ele deixou as decisões
de visual com o Claude ("pode começar por conta própria"). Tudo abaixo que não é citação
dele é decisão do Claude.

## Objetivos

- Uma identidade só nos dois apps: as mesmas cores, a mesma fonte e os mesmos componentes.
- Mais clareza para o vendedor na rua: ações grandes, status legível e o aviso de
  "aguardando envio" bem visível.
- No Windows, o Controle deve aproveitar a tela larga.

## Não-objetivos

- Nenhuma mudança de comportamento: login, envio, pendentes, sincronização, RPCs e regras
  continuam como estão. Os testes atuais têm que passar sem mexer na lógica.
- Sem tema escuro, sem logo novo, sem ícone novo do app e sem mudar o PDF do pedido.
- Sem funcionalidade nova (as etiquetas são outro projeto).

## Anti-objetivos (falha mesmo se "funcionar")

- Perder ou mudar texto que o vendedor já conhece em mensagens de erro e avisos, como
  "Pedido salvo. Será enviado quando houver internet.", que os testes conferem.
- Botões menores ou mais difíceis de tocar no celular.
- Cor sem contraste: texto laranja-claro sobre amarelo ou branco.

## Abordagens consideradas

1. **Só trocar o `ThemeData`.** Barato, mas as telas têm cerca de 600 cores e estilos
   escritos à mão, e quase nada mudaria. Descartada.
2. **Tema por app, telas revisadas.** Resolve, mas duplica o tema e os dois apps voltam a
   divergir. Descartada.
3. **Pacote `packages/milkdim_ui` (path dependency) com tokens, tema e componentes, e telas
   revisadas para usar só o pacote.** Escolhida: uma fonte de verdade, e os dois apps já
   são irmãos no monorepo.

## Direção visual (decisões do Claude)

**Cores (tokens em `MdColors`):**

| Uso | Token | Hex |
|---|---|---|
| Primária (laranja da marca) | `primary` | `#E38A1D` |
| Texto/ícone laranja sobre claro (contraste) | `primaryStrong` | `#A85C0C` |
| Destaque da marca (amarelo), só em fundos e realces, nunca com texto claro | `accent` | `#FFE066` |
| Fundo de tela | `background` | `#F7F5F2` |
| Superfície (cartões) | `surface` | `#FFFFFF` |
| Borda | `border` | `#E7E2DA` |
| Texto principal | `text` | `#1F1B16` |
| Texto secundário | `textMuted` | `#6B645B` |
| Sucesso | `success` | `#1E8E4E` |
| Atenção | `warning` | `#B7791F` |
| Erro | `danger` | `#C9372C` |
| Informação | `info` | `#2D6CDF` |

Os status de recência do cliente (verde, laranja, vermelho, cinza) passam a usar
success, warning, danger e textMuted.

**Tipografia:** Noto Sans, empacotada no `milkdim_ui`; os .ttf já existem em
`app/assets/fonts`. A escala vem do Material 3, com títulos em w700 e corpo em w400/w500.
Nada abaixo de 13 px em texto de leitura.

**Formas:**
- Raio 12 em campos e botões, 16 em cartões e 20 em diálogos.
- Cartões sem sombra (elevation 0) e com borda de 1 px.
- Espaçamento em múltiplos de 4: 8, 12, 16, 24, 32.

**Barra superior:** fundo branco, título escuro, logo pequeno à esquerda e uma linha de
borda embaixo. A barra deixa de ser amarela.

**Botões:**
- Principal: `FilledButton` laranja com texto branco, altura mínima de 48 (56 nas ações
  grandes do vendedor).
- Secundário: `OutlinedButton` com borda `border` e texto `primaryStrong`.
- Destrutivo: `danger`.

**Componentes do pacote:**
- `MdLogoTitle`: logo + "MilkDim".
- `MdCard`.
- `MdStatusChip(tipo, texto)`.
- `MdBanner(tipo, texto, acao)`: o aviso de pendentes usa este.
- `MdEmptyState(icone, titulo, texto)`.
- `MdSectionHeader`.
- `MdActionTile`: a ação grande do início do vendedor.
- `showMdSnack(context, texto, tipo)`.
- `MdSearchField`.

**App do funcionário:**
- **Início:** cartão de saudação com o nome e o código do vendedor, depois o banner de
  pendentes (quando houver), depois as duas ações grandes ("Novo pedido" e "Meus pedidos")
  e a linha de sincronização. A versão fica no rodapé.
- **Demais telas:** login, lista de pedidos, pedido, edição, assinatura, novo cliente e
  configurações. Todas passam a usar só tema e componentes do pacote. A lógica fica igual.

**Controle:**
- **Navegação:**
  - Tela com 900 px ou mais: `NavigationRail` à esquerda com o logo, estendida a partir de
    1200 px.
  - Tela menor: `NavigationBar` embaixo.
- **Conteúdo:** fica limitado a 1100 px de largura e centralizado nas telas largas.
- **Abas:** as quatro (vendedores, produtos, pedidos, clientes) usam cartões ou linhas
  limpas, busca no topo, `MdStatusChip` para status e `MdEmptyState` quando a lista está
  vazia.

## Conferência visual

Teste de captura em `test/visual/` em cada app e no pacote. Ele gera PNGs das telas que dá
para montar sem rede (galeria de componentes, logins, início do vendedor com dados falsos),
com a Noto Sans e os ícones carregados de verdade. As imagens saem em `build/visual/`
(ignorado pelo git) e servem só para revisão, sem golden comparado.

## Deixado para quem constrói

- Detalhes de cada tela e a ordem dos campos, desde que nenhum campo some.
- Os nomes internos dos widgets locais.
