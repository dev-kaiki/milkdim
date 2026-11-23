// lib/utils/pedido_da_tela.dart
//
// O mapa que as telas de pedido (novo e edição) entregam a
// `gravarPedidoEEnviar`. Fica fora das telas para o teste montar o pedido
// exatamente como elas montam.

import 'dart:typed_data';

/// Mapa do pedido como a tela grava.
/// - [base]: o que vem antes (vendedor no pedido novo; a linha do SQLite na
///   edição). Os campos da tela sobrescrevem.
/// - [cliente]: os campos `cliente_*` de texto (nome, telefone, ...).
/// - [assinatura]: os bytes da imagem. Vão no mapa para o SQLite guardar e
///   para o envio (e os reenvios) levarem a assinatura ao servidor. Sem
///   bytes novos, fica a de [base].
/// - [assinaturaPath]: o arquivo local da assinatura (só do aparelho).
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
}) =>
    {
      ...base,
      'numero': numero,
      'produtos': produtos,
      'total': total,
      'status': status,
      'datahora': datahora,
      'cliente_id': clienteId,
      ...cliente,
      if (assinatura != null && assinatura.isNotEmpty) 'assinatura': assinatura,
      // caminho local da assinatura
      'assinatura_path': assinaturaPath,
      // salvar daqui sempre envia (abrir e salvar um rascunho antigo o envia)
      'so_local': 0,
    };
