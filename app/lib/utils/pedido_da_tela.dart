// lib/utils/pedido_da_tela.dart
//
// O mapa que as telas de pedido (novo e edição) entregam a
// `gravarPedidoEEnviar`. Fica fora das telas para o teste montar o pedido
// exatamente como elas montam.

import 'dart:typed_data';

import 'regras_pedido.dart' show estaPronto, itensOuClienteMudaram, mesmosItens;

/// Mapa do pedido como a tela grava.
/// - [base]: o que vem antes (vendedor no pedido novo; a linha do SQLite na
///   edição). Os campos da tela sobrescrevem.
/// - [produtos]: os itens da tela. Se forem os mesmos da [base] (nome,
///   quantidade e preço; veja `mesmosItens`), vão os itens e o total da
///   [base] **como estão**: o servidor compara o `produtos` jsonb, e um
///   subtotal recalculado com ruído de ponto flutuante, outra ordem ou outra
///   chave tirariam o pedido de `pronto`.
/// - [status]: `salvo` ou `pronto` viram a situação que o servidor vai
///   gravar: `pronto` só se a [base] já está `pronto` e não mudaram itens nem
///   cliente (`itensOuClienteMudaram`); senão `salvo` (o vendedor nunca grava
///   `pronto`). As outras situações passam como vieram.
/// - [cliente]: os campos `cliente_*` de texto (nome, telefone, ...).
/// - [assinatura]: os bytes da imagem da assinatura da **entrega**. Vão no
///   mapa para o SQLite guardar e para o envio (e os reenvios) levarem a
///   assinatura ao servidor. Sem bytes novos, fica a de [base].
/// - [assinaturaPath]: o arquivo local da assinatura da entrega (só do aparelho).
/// - [assinaturaPedido]: os bytes da assinatura **do pedido** (gravados em
///   `assinatura_pedido`). Sem bytes novos, fica a de [base].
/// - [assinaturaPedidoPath]: o arquivo local da assinatura do pedido. Sem
///   caminho novo, fica o de [base], a não ser que vieram bytes novos (aí o
///   caminho antigo seria de outra assinatura e é limpo).
Map<String, dynamic> pedidoDaTela({
  Map<String, dynamic> base = const {},
  required String numero,
  required List<Map<String, dynamic>> produtos,
  required double total,
  required String status,
  required String datahora,
  required int? clienteId,
  required Map<String, String> cliente,
  required Uint8List? assinatura,
  required String? assinaturaPath,
  Uint8List? assinaturaPedido,
  String? assinaturaPedidoPath,
}) {
  final temAssinaturaPedido = assinaturaPedido != null && assinaturaPedido.isNotEmpty;
  final mesmosDaBase =
      base.containsKey('produtos') && mesmosItens(base['produtos'], produtos);
  final pedido = <String, dynamic>{
    ...base,
    'numero': numero,
    'produtos': mesmosDaBase ? base['produtos'] : produtos,
    'total': mesmosDaBase && base['total'] is num ? (base['total'] as num).toDouble() : total,
    'status': status,
    'datahora': datahora,
    'cliente_id': clienteId,
    ...cliente,
    if (assinatura != null && assinatura.isNotEmpty) 'assinatura': assinatura,
    // caminho local da assinatura
    'assinatura_path': assinaturaPath,
    if (temAssinaturaPedido) 'assinatura_pedido': assinaturaPedido,
    if (assinaturaPedidoPath != null || temAssinaturaPedido)
      'assinatura_pedido_path': assinaturaPedidoPath,
    // salvar daqui sempre envia (abrir e salvar um rascunho antigo o envia)
    'so_local': 0,
  };
  if (status == 'salvo' || status == 'pronto') {
    pedido['status'] =
        estaPronto(base) && !itensOuClienteMudaram(base, pedido) ? 'pronto' : 'salvo';
  }
  return pedido;
}
