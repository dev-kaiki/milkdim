// lib/utils/json_utils.dart
import 'dart:convert';
import 'dart:typed_data';

/// Exporta o pedido como JSON (pretty por padrão),
/// normalizando campos e incluindo **todos** os relevantes.
/// Observação: a assinatura **não vai para o banco**; aqui exportamos
/// opcionalmente para o JSON como `assinatura_base64` (texto), obtida de
/// qualquer formato salvo (bytes/base64/hex/data-uri).
String exportarPedidoParaJson(
    Map<String, dynamic> pedido, {
      bool pretty = true,
      bool incluirAssinatura = true,
      bool incluirId = false,
    }) {
  final camposBase = <String>[
    'numero',
    'produtos',
    'total',
    'status',
    'datahora',
    'vendedor_codigo',
    'vendedor_nome',
    'cliente_id',
    'cliente_nome',
    'cliente_nome_fantasia',
    'cliente_telefone',
    'cliente_whatsapp',
    'cliente_email',
    'cliente_endereco',
    'cliente_cidade',
    'cliente_cpf_cnpj',
    'cliente_insc_estadual',
    'cliente_cep',
    'cliente_anotacao',
  ];

  if (incluirId) camposBase.add('id');

  final out = <String, dynamic>{};
  for (final k in camposBase) {
    if (pedido.containsKey(k)) out[k] = pedido[k];
  }

  // datahora -> ISO UTC
  final dh = out['datahora'];
  if (dh != null) out['datahora'] = _toIsoUtcString(dh) ?? dh;

  // total -> double
  out['total'] = _toDouble(out['total']);

  // produtos -> lista normalizada
  dynamic produtos = out['produtos'];
  if (produtos is String) {
    try {
      produtos = jsonDecode(produtos);
    } catch (_) {
      produtos = [];
    }
  }
  if (produtos is! List) produtos = <Map<String, dynamic>>[];
  out['produtos'] = (produtos as List)
      .whereType<Map>()
      .map((p0) {
    final p = Map<String, dynamic>.from(p0);
    final preco = _toDouble(p['preco']);
    final qtd = _toInt(p['quantidade']);
    final subtotal =
    p.containsKey('subtotal') ? _toDouble(p['subtotal']) : (preco * qtd);
    return <String, dynamic>{
      'nome': p['nome'],
      'preco': preco,
      'quantidade': qtd,
      'subtotal': subtotal,
    };
  })
      .toList();

  // Assinatura apenas no JSON exportado, nunca para DB:
  // produzimos `assinatura_base64` a partir de qualquer campo legado.
  if (incluirAssinatura) {
    final dynamic anySig = pedido['assinatura'] ??
        pedido['assinatura_base64'] ??
        pedido['assinaturaBytes'] ??
        pedido['signature'] ??
        pedido['signature_base64'];
    final bytes = _toBytes(anySig);
    if (bytes != null && bytes.isNotEmpty) {
      out['assinatura_base64'] = base64Encode(bytes);
    }
  }

  final encoder =
  pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
  return encoder.convert(out);
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').trim()) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

String? _toIsoUtcString(dynamic v) {
  DateTime? dt;
  if (v is DateTime) {
    dt = v;
  } else if (v is String && v.isNotEmpty) {
    try {
      dt = DateTime.parse(v);
    } catch (_) {}
  }
  return dt?.toUtc().toIso8601String();
}

Uint8List? _toBytes(dynamic v) {
  if (v == null) return null;
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);

  if (v is String) {
    var s = v.trim();
    if (s.isEmpty) return null;

    // data-uri base64
    final m =
    RegExp(r'^data:.*;base64,', caseSensitive: false).firstMatch(s);
    if (m != null) s = s.substring(m.end);

    // tenta base64
    try {
      final b64 = base64.decode(s);
      if (b64.isNotEmpty) return Uint8List.fromList(b64);
    } catch (_) {
      // tenta HEX (aceita 0x, \x, \X, \\x, espaços etc.)
      var hexStr = s;
      if (hexStr.startsWith(r'\\x')) hexStr = hexStr.substring(3); // remove \\x
      if (hexStr.startsWith(r'\x') || hexStr.startsWith(r'\X')) {
        hexStr = hexStr.substring(2);
      }
      if (hexStr.startsWith('0x') || hexStr.startsWith('0X')) {
        hexStr = hexStr.substring(2);
      }
      hexStr = hexStr.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (hexStr.isEmpty) return null;
      if (hexStr.length.isOdd) hexStr = '0$hexStr';
      final out = Uint8List(hexStr.length ~/ 2);
      for (int i = 0, j = 0; i < hexStr.length; i += 2, j++) {
        out[j] = int.parse(hexStr.substring(i, i + 2), radix: 16);
      }
      return out;
    }
  }
  return null;
}
