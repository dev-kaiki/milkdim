# Etiqueta por caixa (volumes do pedido)

Data: 25/11/2026. Caminho aprovado pelo Kaiki: o Controle **sugere** as caixas
automaticamente, e a fábrica **ajusta** se quiser.

## Por quê

Em 25/11, o dono da MilkDim aprovou a etiqueta do pedido ("ficou top") e pediu uma mudança, em
áudios. A fábrica entrega em caixas, e cada caixa precisa de sua própria etiqueta.

- **Capacidade da caixa:** cabem 16 potes, 20 copos ou 4 pudins médios (550 g). O pudim
  grande (1100 g) não cabe na caixa e vai solto.
- **Numeração:** um pedido grande vira vários volumes, "Pedido 448 · 1/3", "2/3", "3/3",
  para quem entrega saber que tem que levar todos.
- **Sobra:** o que não fecha uma caixa vira uma etiqueta de **avulsos**, por exemplo
  "10 copos avulsos". Nas palavras dele: "tantas caixas e tantos produtos avulsos".
- **Venda solta:** na venda picada da cidade, o pedido não vai em caixa e pode sair
  **solto**.
- **Montagem manual:** na hora de fabricar, a fábrica quer poder montar as caixas, por
  exemplo misturando sabores.

## Objetivos

1. **Tipos de caixa:** cadastro de tipos de caixa com nome, capacidade e se aceita misturar
   sabores. Os iniciais são **Pote (16)**, **Copo (20)** e **Médio (4)**.
2. **Produto ligado a um tipo de caixa:** cada produto pode ter um tipo de caixa, escolhido
   no cadastro de produtos do Controle. Produto **sem** tipo de caixa, como o grande, o
   geladinho e o pudim de vidro, sempre sai em avulso.
3. **Sugestão automática** ao imprimir a etiqueta de um pedido:
   - os itens são agrupados por tipo de caixa;
   - cada grupo enche caixas cheias, na ordem dos itens do pedido;
   - se o tipo aceita misturar sabores, a caixa completa com o próximo sabor do mesmo tipo;
   - o que sobra, mais os produtos sem tipo de caixa, vai para **um** volume "Avulsos";
   - **exemplo:** 50 copos de leite resultam em Caixa 1/3 (20 copos), Caixa 2/3 (20 copos)
     e Avulsos 3/3 (10 copos).
4. **Tela "Volumes do pedido"** antes de imprimir. Ela mostra a sugestão e deixa a fábrica:
   - mudar quantidades entre volumes;
   - criar ou apagar uma caixa;
   - marcar o pedido como **"Pedido solto (sem caixas)"**, que vira um volume só com tudo.
   - **Conferência obrigatória:** a soma de cada produto nos volumes tem que bater com o
     pedido, senão não imprime.
   - **Aviso sem bloqueio:** a caixa acima da capacidade só gera aviso, porque a fábrica
     sabe o que cabe.
5. **Uma etiqueta por volume.** Cada etiqueta mostra:
   - "Pedido 448" e "Caixa 1/3" (ou "Avulsos 3/3", ou "Pedido solto");
   - **só os itens daquele volume**;
   - o cliente, o endereço e o vendedor, como hoje;
   - o **mesmo QR** do pedido em todas: ler qualquer uma abre o pedido para registrar a
     entrega, como hoje.
6. **Volumes guardados:** os volumes de cada pedido ficam salvos. Reimprimir sai igual, e o
   resto do sistema pode mostrar "3 volumes".
   - Se o pedido for alterado depois de salvo, a tela avisa e sugere de novo, para não
     imprimir caixas de um pedido que mudou.
7. **"Etiqueta impressa":** continua marcada por pedido, como hoje. Ela é perguntada depois
   de imprimir todos os volumes ("As etiquetas saíram certas?").

## Fora do escopo

- **Mudar o app dos vendedores:** o vendedor não monta caixas.
- **Estoque de caixas** ou custo da embalagem.
- **Etiqueta de fabricação** por pote (validade e lote).
- **Dividir a entrega** em dias diferentes. Os volumes são do mesmo pedido e da mesma
  entrega.

## Não pode acontecer

- **Etiqueta que some ou duplica produto:** a soma dos volumes sempre fecha com o pedido.
- **Volumes antigos de um pedido que mudou** impressos sem aviso.
- **Vendedor comum vendo ou mudando volumes e tipos de caixa.** Só administrador, como as
  saídas.
- **Mudança no fluxo de entrega pelo QR:** cada caixa traz o QR do pedido inteiro.

## Caminhos considerados

| Caminho | Por que |
|---|---|
| **Sugestão automática + ajuste (escolhido)** | Resolve o caso comum sem trabalho, e a fábrica só mexe quando quer. |
| Só automático | Não cobre a venda solta nem as caixas misturadas do jeito que a fábrica quer. |
| Só manual | Dá trabalho em todo pedido, até nos simples. |

## Desenho

### Banco: uma migração nova

- **`public.tipos_caixa`:** `id`, `nome` (único, não vazio), `capacidade int > 0`,
  `mistura_sabores boolean default true` e `ativo boolean default true`. Começa com Pote
  16, Copo 20 e Médio 4.
- **`public.produtos.tipo_caixa_id`:** referência a `tipos_caixa`, pode ser nula, `on
  delete set null`.
  - **Preenchimento inicial** pelo nome, só nos casos claros:
    - nomes que começam com "Pote" e têm "160g" → Pote;
    - nomes que começam com "Copo" → Copo;
    - nomes que começam com "550g" → Médio.
  - Os demais ficam sem tipo, para a fábrica conferir no cadastro (Pudim Pote, Pote Pró
    Vida, Geladinho e outros).
- **`public.pedido_volumes`:** uma linha por pedido.
  - **Colunas:** `pedido_id` (chave e referência a `pedidos`), `solto boolean` e `volumes
    jsonb`. Cada volume é `{tipo: "caixa"|"avulso", caixa: "<nome do tipo>"|null, itens:
    [{nome, quantidade}]}`.
  - **Mudança no pedido:** `pedido_alterado_em timestamptz` guarda o `alterado_em` do
    pedido quando os volumes foram salvos, para detectar se o pedido mudou depois.
  - **Auditoria:** `salvo_em` e `salvo_por`, preenchidos pelo gatilho, como nas saídas.
  - **Por que tabela separada:** os gatilhos que protegem `pedidos` contra o app dos
    vendedores ficam como estão.
- **Acesso:** RLS só para administrador nas três partes novas (as duas tabelas e a coluna
  em `produtos`, com a mesma política de escrita que `produtos` já tem). O `anon` não tem
  acesso.
- **Teste SQL** em rollback antes, e aplicação só com o OK do Kaiki.

### Controle

- **Cadastro de produtos:** ganha o campo "Tipo de caixa" (lista com os tipos e "Sem caixa
  (avulso)"), e um botão para gerenciar os tipos de caixa (nome, capacidade, misturar
  sabores, ativo).
- **Sugestão:** é uma função pura e testada, `sugerirVolumes(itens, tiposPorProduto)`.
  - O item do pedido é ligado ao produto **pelo nome**, sem diferenciar maiúsculas e sem os
    espaços das pontas, porque o pedido guarda o nome e não o código do produto.
  - Item sem produto correspondente (produto renomeado ou apagado) vai para os avulsos, e a
    tela avisa.
- **Tela "Volumes do pedido":** abre no lugar da impressão direta, nos dois lugares que
  imprimem etiqueta hoje (Produção e detalhe do pedido).
- **PDF:** um documento com uma página por volume, no tamanho escolhido, num único envio
  para a impressora.

## Perguntas em aberto (com o cliente)

O desenho já aceita qualquer uma das respostas, sem mudar código:

- **Misturar sabores do mesmo tipo:** é o padrão **sim**, e pode ser desligado por tipo no
  cadastro.
- **Pote com copo na mesma caixa:** **não**, porque são tipos diferentes. A fábrica pode
  juntar à mão na tela.
- **Geladinho, pacote com 30 e pudim de vidro:** ficam **sem caixa** (avulso) até a fábrica
  definir no cadastro.

## Deixado para quem constrói

- O layout exato da tela de volumes, desde que funcione em 360 px.
- Como a etiqueta mostra "Caixa 1/3 · Copo", desde que caiba no 60×40.
