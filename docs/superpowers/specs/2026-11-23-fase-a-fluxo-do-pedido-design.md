# Fase A: novo fluxo do pedido (solicitação → produção → entrega)

Data: 23/11/2026 · Escopo: `app/` (vendedor), `admin/` (Controle), banco Supabase.

## Por quê

O dono da MilkDim mandou uma lista e áudios em 20/11/2026. O vendedor tira o
pedido, mas a fábrica (a esposa do dono, no Controle) só vê o pedido quando ele já foi
assinado e finalizado. Isso acontece na entrega, ou seja, tarde demais para fabricar.

Ele quer o pedido como uma **solicitação de venda**:
1. O vendedor solicita.
2. O pedido aparece na hora para ela fabricar.
3. Na entrega, o cliente assina e o vendedor finaliza.
4. O pedido só sai da tela dela quando for finalizado.

O Kaiki aprovou o roteiro em 23/11, e esta é a Fase A. As fases seguintes (etiqueta com QR,
forma de cobrança, financeiro, emissão fiscal) dependem desta.

## Decisões do Kaiki

- **Total a fabricar:** é por produto, em unidades ("15 Pudim tradicional, 10 Leite ninho").
  Não é por kg.
- **Alteração pelo vendedor:** ele pode alterar o pedido depois de enviado, até finalizar.
  Isso inclui ajustar a quantidade na entrega, antes da assinatura.

## Objetivos

- **Envio do pedido aberto:** o pedido salvo sem assinatura vai para o servidor como "em
  aberto". Sem internet, fica no aparelho e é reenviado depois, como o finalizado já é hoje.
- **Entrega:** o vendedor reabre o pedido aberto, colhe a assinatura e finaliza. O fluxo de
  edição e assinatura existe hoje e continua.
- **Cancelamento:** o vendedor pode cancelar um pedido aberto, e ela também pode, no
  Controle.
- **Controle, aba nova "Produção":**
  - **total por produto** dos pedidos em aberto;
  - logo abaixo, a lista desses pedidos, do mais antigo para o mais novo;
  - destaque "alterado às HH:MM" quando o vendedor mudou o pedido depois de enviar;
  - a tela se atualiza sozinha.
- **Finalização manual no Controle:** grava quem finalizou e quando. Não exige assinatura.
- **Acompanhamento:** a aba Pedidos do Controle filtra por situação (em aberto, finalizado,
  cancelado).

## Não-objetivos

- **Etiqueta, QR e situação "em produção":** ficam para a Fase B.
- **Forma de cobrança e financeiro:** ficam para as Fases C e D.
- **Nota e cupom:** ficam para a Fase E.
- **Estoque:** fica para depois.
- **Contagem por peso (kg):** não entra.
- **PDF do pedido:** não muda.
- **Login:** não muda.
- **Tema visual:** não muda. Tudo usa o `milkdim_ui`.

## Anti-objetivos (falha mesmo se "funcionar")

- Perder um pedido do vendedor, aberto ou finalizado, em qualquer caminho: sem internet,
  edição com envio no ar, sincronização, cancelamento ou finalização manual pelo Controle.
- **Pedido duplicado** no celular ou no servidor. A mesma solicitação nunca pode aparecer
  duas vezes na Produção.
- **Pedido finalizado ou cancelado que volta a "em aberto"** porque um celular sem internet
  reenviou uma versão antiga.
- **Encher a Produção** com rascunhos antigos que já estavam guardados nos celulares antes
  desta versão.
- **Quebrar o vendedor que ainda está com o APK atual.** Ele tem que continuar enviando
  finalizados normalmente.

## Restrições

- **Credenciais:** nenhuma senha, chave ou URL do Supabase entra em arquivo versionado. O
  repositório é público.
- **Migração do banco:** nada é aplicado ao banco real sem mostrar o SQL ao Kaiki e receber
  OK. Até agora as fases foram aplicadas via `execute_sql` em `begin/commit`, e o arquivo
  correspondente fica em `supabase/migrations/`.
- **RLS:** a regra atual continua.
  - O vendedor lê, insere e altera só os pedidos com o `vendedor_codigo` dele.
  - O admin (`app_is_admin()`) faz tudo.
  - Só o admin apaga.
- **O que já existe e deve ser reaproveitado:**
  - **App:** a situação local `salvo` (rascunho), as abas "Em aberto" e "Finalizados" de
    Meus pedidos, a `pedido_edit_page` com assinatura, e `pendente_envio`.
  - **Envio:** o upsert por `(numero, vendedor_codigo)` em `salvarPedidoSupabase`, com o
    eco do servidor aplicado no SQLite (`aplicarEcoDoServidor`).
  - **Banco:** a constraint única `pedidos_numero_vendedor_key` (numero, vendedor_codigo).
- **Itens do pedido:** cada item do `produtos` (jsonb) traz só `nome`, `preco`, `quantidade`
  e `subtotal`, sem o id do produto. O total da Produção agrupa pelo `nome`.

## Abordagens consideradas

1. **Mesma tabela `pedidos`, com situação.** Escolhida.
   - O pedido aberto é a mesma linha que depois vira finalizada.
   - O upsert por número e vendedor e o eco no SQLite já tratam esse caminho.
   - O APK antigo continua compatível, porque só manda finalizados.
2. **Tabela separada `solicitacoes`, convertida em pedido na entrega.** Descartada. Seriam
   dois registros do mesmo pedido e uma conversão que pode falhar no meio, sem ganho para a
   fábrica.
3. **Rascunho local mais um botão separado "Enviar para produção".** Descartada. É mais um
   passo para o vendedor lembrar. Foi justamente o que ele deixou de fazer: os pedidos ficam
   esquecidos no celular.

## Desenho

### Banco

- **Situação:** o valor gravado para "em aberto" continua `salvo`, que é o que o app já
  usa. Entra `cancelado`. Na tela aparece "Em aberto", "Finalizado" e "Cancelado".
  - Antes de criar a constraint `check (status in ('salvo','finalizado','cancelado'))`, é
    preciso conferir no banco que não existem outros valores. Hoje os 372 pedidos são
    `finalizado`.
- **Colunas novas em `pedidos`:**
  - `enviado_em timestamptz`: primeira chegada ao servidor, com `default now()`.
  - `alterado_em timestamptz`: última alteração **dos produtos/quantidades ou do cliente**
    (`produtos`, `cliente_id`, `cliente_nome`) feita enquanto o pedido estava aberto.
    Reenvio, troca de `datahora` e a própria finalização não contam. *(Decisão do Claude:
    a fábrica só precisa saber se mudou o que fabricar ou para quem.)*
  - `finalizado_em timestamptz` e `finalizado_por text`: código de quem finalizou, seja o
    vendedor ou o admin.
  - `finalizado_manual boolean default false`.
  - `cancelado_em timestamptz` e `cancelado_por text`.
- **Gatilho de proteção (BEFORE UPDATE, SECURITY DEFINER, como os outros gatilhos de
  pedidos):**
  - **Pedido já finalizado ou cancelado:** quem não é admin não consegue alterar. A
    alteração é ignorada e a linha volta como estava, sem erro, para o app receber o eco e
    se corrigir. Isso cobre o celular sem internet reenviando uma versão velha depois que o
    Controle finalizou.
    - **Exceção (decisão do Claude): a entrega assinada sempre vence.** Se o vendedor
      envia o pedido como `finalizado` **com assinatura**, e o servidor o tem como
      finalizado **manualmente** ou como **cancelado**, a versão do vendedor substitui a do
      servidor: produtos, quantidades, total, assinatura e situação. O motivo é que a
      assinatura prova que a entrega aconteceu, e assim a assinatura e as quantidades
      corrigidas na rua nunca se perdem.
      - Os campos `finalizado_por` e `finalizado_em` passam a ser os do vendedor, e
        `finalizado_manual` volta a `false`.
      - Se vence um pedido cancelado, `cancelado_em` e `cancelado_por` ficam preenchidos.
        Assim dá para ver que o pedido foi cancelado e depois entregue.
      - Um pedido já finalizado **com assinatura** não é substituído por outro envio.
  - Isso também vale para a Tentativa C do envio (INSERT), que cai no erro da constraint
    única: o app trata como "já existe" e busca a versão do servidor.
  - **Admin:** pode finalizar e cancelar pedidos abertos.
  - **Reabrir:** fica fora da Fase A. Não há botão para isso, e o gatilho não precisa
    tratar a volta de finalizado ou cancelado para aberto. *(Decisão do Claude.)*
- **Finalizar manual no Controle:** é para o caso em que o vendedor não vai finalizar pelo
  app (esqueceu, entregou sem o celular, pedido de balcão). O Controle avisa na confirmação:
  "Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale
  a dele."
  - **Datas e autores:** o gatilho preenche `alterado_em`, `finalizado_em`/`finalizado_por`
    e `cancelado_em`/`cancelado_por` conforme a transição. O cliente não escolhe esses
    valores.
- **Gatilhos de último pedido do cliente (`trg_atualizar_ultimo_pedido` e
  `trg_pedidos_update_cliente_ultimo`):** continuam no INSERT. Um pedido aberto também conta
  como "último pedido" do cliente, e isso é aceitável.
- **Pedidos antigos:** os 372 ficam como estão. O backfill preenche `finalizado_em = datahora`
  e `enviado_em = datahora`.

### App do vendedor

- **Salvar sem assinatura:** grava `salvo` com `pendente_envio = 1` e tenta enviar na hora,
  como já acontece com o finalizado.
  - Mensagem de sucesso: "Pedido enviado para produção."
  - Sem internet: "Pedido salvo. Será enviado quando houver internet." Esse texto não muda.
- **Editar um pedido aberto** (inclusive na entrega): regrava e reenvia pelo mesmo upsert.
  Ao finalizar com assinatura, vale o fluxo de hoje.
- **Número do pedido:** hoje é um campo livre nas duas telas, e o upsert usa
  `(numero, vendedor_codigo)` como chave. *(Decisões do Claude:)*
  - **Travado depois do envio:** quando o pedido já chegou ao servidor uma vez, o número
    vira só leitura na edição. Trocar o número de um pedido já enviado criaria uma segunda
    linha no servidor e duplicaria o pedido na Produção.
  - **Pedido novo:** antes de salvar, se houver internet, o app confere se o número já
    existe no servidor para esse vendedor. Se existir, avisa e sugere o próximo livre.
  - **Identificador por aparelho:** cada pedido ganha um identificador gerado no celular
    (`id_aparelho`, UUID), que vai junto para o servidor. É ele que separa os dois casos:
    - "o mesmo pedido reenviado porque a resposta se perdeu": mesmo identificador;
    - "outro pedido com o mesmo número": identificador diferente.

    *(Decisão do Claude no plano.)*
  - **Sem internet:** vale o número local de hoje (maior número do aparelho + 1). Se no
    envio der conflito com um pedido de outro aparelho do mesmo vendedor, o pedido fica
    pendente com o aviso "Número já usado; troque o número". Nesse caso, e só nesse, o
    número volta a ser editável. Ele nunca é descartado.
- **Cancelar:** a ação "remover do aparelho" do pedido aberto vira **"Cancelar pedido"**,
  com confirmação.
  - Grava `cancelado` e envia.
  - O pedido sai de "Em aberto" e vai para uma aba ou filtro "Cancelados" em Meus pedidos.
  - Um rascunho que nunca foi enviado (veja abaixo) pode continuar sendo apagado do
    aparelho.
- **Pendentes:** `pendente_envio` passa a valer para qualquer situação, não só
  `finalizado`.
  - O banner "N pedidos aguardando envio" e o reenvio automático passam a contar os abertos
    também.
- **Sincronização: corrigir a proteção de rascunhos em `aplicarPedidosRemotos`.**
  - Hoje um `salvo` local cujo id coincide com um id remoto é realocado, porque se supunha
    que todo `salvo` era só local.
  - Agora um `salvo` com o mesmo id **e** o mesmo (numero, vendedor_codigo) do remoto é o
    próprio pedido, e não deve ser realocado.
  - Só realoca quando é outro pedido.
  - Sem essa correção, cada sincronização duplica os pedidos abertos.
- **Eco do servidor:** se o servidor devolve um pedido finalizado ou cancelado diferente do
  que foi enviado (o gatilho de proteção agiu), o SQLite fica com a versão do servidor e o
  app avisa: "Este pedido já foi finalizado no Controle."
  - Pela regra de que a entrega assinada vence, isso só acontece quando o vendedor enviou
    uma edição **sem** assinatura de um pedido que o Controle já fechou.
  - Mesmo assim, a versão local que perdeu não é apagada em silêncio: ela é guardada numa
    tabela local de "versões descartadas" (no próprio SQLite, sem tela nesta fase). Assim
    dá para recuperar se alguém reclamar.
- **Rascunhos antigos (antes desta versão):**
  - A migração SQLite v17 marca os `salvo` que existem no aparelho como "rascunho local"
    (coluna nova, por exemplo `so_local = 1`). Eles **não** são enviados sozinhos.
  - Na lista aparecem com o selo "Não enviado".
  - Ao abrir e salvar um deles, ele é enviado normalmente.
  - Ao apagar, sai só do aparelho, como hoje.

### Controle

- **Aba nova "Produção"**, primeira ou segunda no menu, a critério de quem constrói.
  - **Total por produto:** soma `quantidade` por `nome` nos pedidos `salvo`, em ordem
    decrescente.
  - **Lista de pedidos em aberto:**
    - campos: número, vendedor, cliente, enviado há quanto tempo, itens resumidos e o selo
      "alterado às HH:MM" quando `alterado_em` > `enviado_em`;
    - ações: **Finalizar** (confirmação; grava finalizado manual) e **Cancelar**
      (confirmação);
    - tocar no pedido abre o detalhe que já existe.
  - **Atualização:** automática a cada 30 s enquanto a aba está visível, mais um botão
    "Atualizar".
  - **Estado vazio:** "Nenhum pedido em aberto".
- **Aba Pedidos:** filtro por situação (Todos, Em aberto, Finalizados, Cancelados). O chip
  de situação usa os textos novos.
- **Detalhe do pedido:** mostra enviado em, alterado em, finalizado em/por (e se foi manual)
  e cancelado em/por.

## Instalação

- **Ordem:**
  1. Migração do banco (com OK do Kaiki).
  2. Controle novo.
  3. APK novo dos vendedores.
- **Compatibilidade:** o APK antigo continua funcionando com o banco novo; só não envia
  pedidos abertos. O roteiro de instalação vai no mesmo estilo do `docs/implantacao-auth.md`.
- **Conta da fábrica:** a esposa do dono precisa de uma conta admin no Controle. Ainda
  não se sabe se ela usa um dos códigos de admin atuais (0001, 0002, 700122) ou se é preciso
  criar outro. Isso não muda o desenho.

## Deixado para quem constrói

- A posição da aba Produção no menu, o layout exato e os ícones.
- O nome da coluna local de "rascunho antigo" e o nome das funções.
- Se a atualização automática da Produção usa intervalo ou Supabase Realtime. O padrão é o
  intervalo de 30 s, que é mais simples e suficiente.
- **Testes:**
  - os caminhos dos anti-objetivos têm teste automático;
  - o gatilho de proteção é testado no banco em transação com rollback, como foi feito nas
    fases de Auth.
