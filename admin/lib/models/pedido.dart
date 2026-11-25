// lib/models/pedido.dart
import 'dart:convert';
import 'dart:typed_data';

double _round2(double v) => (v * 100).round() / 100.0;

/// -------------------------- ITEM --------------------------
class PedidoItem {
  final String nome;
  final double preco; // preço unitário
  final int quantidade;

  const PedidoItem({
    required this.nome,
    required this.preco,
    required this.quantidade,
  });

  double get subtotal => _round2(preco * quantidade);

  // ------- parsing helpers -------
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.trim();
      // aceita "1.234,56", "1,234.56", "12,34" e "12.34"
      final hasComma = s.contains(',');
      final hasDot = s.contains('.');
      if (hasComma && hasDot) {
        final lastComma = s.lastIndexOf(',');
        final lastDot = s.lastIndexOf('.');
        if (lastComma > lastDot) {
          // vírgula decimal; remove pontos de milhar
          return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
        } else {
          // ponto decimal; remove vírgulas de milhar
          return double.tryParse(s.replaceAll(',', '')) ?? 0.0;
        }
      }
      if (hasComma && !hasDot) return double.tryParse(s.replaceAll(',', '.')) ?? 0.0;
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  factory PedidoItem.fromMap(Map<String, dynamic> m) => PedidoItem(
    nome: (m['nome'] ?? '').toString(),
    preco: _toDouble(m['preco']),
    quantidade: _toInt(m['quantidade'] ?? m['qtd'] ?? 0),
  );

  Map<String, dynamic> toMap() => {
    'nome': nome,
    'preco': _round2(preco),
    'quantidade': quantidade,
    'subtotal': subtotal,
  };

  PedidoItem copyWith({String? nome, double? preco, int? quantidade}) => PedidoItem(
    nome: nome ?? this.nome,
    preco: preco ?? this.preco,
    quantidade: quantidade ?? this.quantidade,
  );
}

/// -------------------------- PEDIDO --------------------------
class Pedido {
  final int id;
  final String? numero; // texto (numérico)
  final List<PedidoItem> itens;
  final double total; // total do pedido (2 casas)
  final String status; // 'salvo' | 'pronto' | 'finalizado' | 'cancelado'
  final String? datahora; // ISO-8601 (preferir UTC)
  final String? vendedorCodigo;
  final String? vendedorNome;

  final int? clienteId;
  final String? clienteNome;
  final String? clienteNomeFantasia;
  final String? clienteTelefone;
  final String? clienteWhatsapp;
  final String? clienteEmail;
  final String? clienteEndereco;
  final String? clienteCidade;
  final String? clienteCpfCnpj;
  final String? clienteInscEstadual;
  final String? clienteCep;
  final String? clienteAnotacao;

  // situacao e auditoria (servidor)
  final DateTime? enviadoEm;
  final DateTime? alteradoEm;

  /// `alterado_em` exatamente como o servidor devolveu (texto). É o que se
  /// manda de volta em `pedido_marcar_pronto`: reserializar o DateTime perde
  /// precisão (microssegundos) e o servidor recusaria sempre (MD001).
  final String? alteradoEmBruto;
  final DateTime? prontoEm;
  final String? prontoPor;
  final DateTime? finalizadoEm;
  final String? finalizadoPor;
  final bool finalizadoManual;
  final DateTime? canceladoEm;
  final String? canceladoPor;

  /// Para UI. No Supabase é bytea: o PostgREST devolve "\x" + hex.
  /// Assinatura da ENTREGA (coluna `assinatura`).
  final Uint8List? assinaturaBytes;

  /// Assinatura do PEDIDO, colhida ao enviar (coluna `assinatura_pedido`).
  final Uint8List? assinaturaPedidoBytes;

  const Pedido({
    required this.id,
    this.numero,
    required this.itens,
    required this.total,
    required this.status,
    this.datahora,
    this.vendedorCodigo,
    this.vendedorNome,
    this.clienteId,
    this.clienteNome,
    this.clienteNomeFantasia,
    this.clienteTelefone,
    this.clienteWhatsapp,
    this.clienteEmail,
    this.clienteEndereco,
    this.clienteCidade,
    this.clienteCpfCnpj,
    this.clienteInscEstadual,
    this.clienteCep,
    this.clienteAnotacao,
    this.enviadoEm,
    this.alteradoEm,
    this.alteradoEmBruto,
    this.prontoEm,
    this.prontoPor,
    this.finalizadoEm,
    this.finalizadoPor,
    this.finalizadoManual = false,
    this.canceladoEm,
    this.canceladoPor,
    this.assinaturaBytes,
    this.assinaturaPedidoBytes,
  });

  // ------- helpers -------
  static T? _pick<T>(Map m, String a, String b) => (m[a] ?? m[b]) as T?;

  static List<Map<String, dynamic>> _ensureListOfMap(dynamic v) {
    if (v == null) return <Map<String, dynamic>>[];
    if (v is String) {
      try {
        final d = jsonDecode(v);
        if (d is List) {
          return d.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
      return <Map<String, dynamic>>[];
    }
    if (v is List) {
      return v.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  static List<PedidoItem> _toItens(dynamic v) => _ensureListOfMap(v).map(PedidoItem.fromMap).toList();

  static double _toDouble(dynamic v) => PedidoItem._toDouble(v);
  static int _toInt(dynamic v) => PedidoItem._toInt(v);

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  /// Texto como veio do servidor; null se não era texto não vazio.
  static String? _bruto(dynamic v) => (v is String && v.trim().isNotEmpty) ? v : null;

  static bool _toBoolFlag(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Assinatura em texto: bytea como o PostgREST devolve (`\x` + hex), ou
  /// base64 (com ou sem data URI).
  static Uint8List? _decodeAssinatura(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final t = s.trim();
    if (t.startsWith(r'\x') || t.startsWith(r'\X')) {
      final bytes = _decodeHex(t.substring(2));
      if (bytes == null) return null;
      // bytea gravado a partir de TEXTO base64: o hex traz os caracteres.
      final interno = _base64DeImagemDentro(bytes);
      return interno ?? bytes;
    }
    final raw = t.contains(',') ? t.split(',').last : t; // remove data URI, se houver
    try {
      return Uint8List.fromList(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _decodeHex(String h) {
    if (h.isEmpty || h.length.isOdd) return null;
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final b = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
      if (b == null) return null;
      out[i] = b;
    }
    return out;
  }

  /// [bytes] é texto ASCII com base64 de PNG/JPEG? Devolve a imagem; senão null.
  static Uint8List? _base64DeImagemDentro(Uint8List bytes) {
    if (bytes.any((b) => b < 32 || b > 126)) return null;
    final texto = String.fromCharCodes(bytes).trim();
    if (!(texto.startsWith('iVBORw0') || texto.startsWith('/9j/'))) return null;
    try {
      return Uint8List.fromList(base64Decode(texto));
    } catch (_) {
      return null;
    }
  }

  static String? _encodeBase64(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return base64Encode(bytes);
  }

  static double _calcTotal(List<PedidoItem> itens, double? informado) {
    final soma = itens.fold<double>(0.0, (s, it) => s + it.subtotal);
    final prefer = _toDouble(informado);
    return _round2(prefer == 0.0 ? soma : prefer);
  }

  /// Aceita map de UI, SQLite ou linha do Supabase (jsonb ou texto em `produtos`)
  factory Pedido.fromMap(Map<String, dynamic> m) {
    final produtos = _pick(m, 'produtos', 'itens'); // supabase usa 'produtos'
    final itens = _toItens(produtos);

    // assinatura pode vir como bytes (UI), bytea "\x..." (supabase) ou base64
    final assinaturaBytes = _pick<Uint8List>(m, 'assinatura_bytes', 'assinaturaBytes') ??
        _decodeAssinatura(_pick<String>(m, 'assinatura_base64', 'assinaturaBase64') ??
            _pick<String>(m, 'assinatura', 'signature'));

    final assinaturaPedido =
        _pick<Uint8List>(m, 'assinatura_pedido_bytes', 'assinaturaPedidoBytes') ??
            _decodeAssinatura(_pick<String>(m, 'assinatura_pedido', 'assinaturaPedido'));

    return Pedido(
      id: _toInt(_pick(m, 'id', 'id')),
      numero: _pick(m, 'numero', 'numero')?.toString(),
      itens: itens,
      total: _calcTotal(itens, _pick(m, 'total', 'total')),
      status: (_pick(m, 'status', 'status') ?? 'salvo') as String,
      datahora: _pick(m, 'datahora', 'datahora'),
      vendedorCodigo: _pick(m, 'vendedor_codigo', 'vendedorCodigo')?.toString(),
      vendedorNome: _pick(m, 'vendedor_nome', 'vendedorNome'),
      clienteId: _pick(m, 'cliente_id', 'clienteId'),
      clienteNome: _pick(m, 'cliente_nome', 'clienteNome'),
      clienteNomeFantasia: _pick(m, 'cliente_nome_fantasia', 'clienteNomeFantasia'),
      clienteTelefone: _pick(m, 'cliente_telefone', 'clienteTelefone'),
      clienteWhatsapp: _pick(m, 'cliente_whatsapp', 'clienteWhatsapp'),
      clienteEmail: _pick(m, 'cliente_email', 'clienteEmail'),
      clienteEndereco: _pick(m, 'cliente_endereco', 'clienteEndereco'),
      clienteCidade: _pick(m, 'cliente_cidade', 'clienteCidade'),
      clienteCpfCnpj: _pick(m, 'cliente_cpf_cnpj', 'clienteCpfCnpj'),
      clienteInscEstadual: _pick(m, 'cliente_insc_estadual', 'clienteInscEstadual'),
      clienteCep: _pick(m, 'cliente_cep', 'clienteCep'),
      clienteAnotacao: _pick(m, 'cliente_anotacao', 'clienteAnotacao'),
      enviadoEm: _toDate(_pick(m, 'enviado_em', 'enviadoEm')),
      alteradoEm: _toDate(_pick(m, 'alterado_em', 'alteradoEm')),
      alteradoEmBruto: _bruto(_pick(m, 'alterado_em', 'alteradoEm')),
      prontoEm: _toDate(_pick(m, 'pronto_em', 'prontoEm')),
      prontoPor: _pick(m, 'pronto_por', 'prontoPor')?.toString(),
      finalizadoEm: _toDate(_pick(m, 'finalizado_em', 'finalizadoEm')),
      finalizadoPor: _pick(m, 'finalizado_por', 'finalizadoPor')?.toString(),
      finalizadoManual: _toBoolFlag(_pick(m, 'finalizado_manual', 'finalizadoManual')),
      canceladoEm: _toDate(_pick(m, 'cancelado_em', 'canceladoEm')),
      canceladoPor: _pick(m, 'cancelado_por', 'canceladoPor')?.toString(),
      assinaturaBytes: assinaturaBytes,
      assinaturaPedidoBytes: assinaturaPedido,
    );
  }

  factory Pedido.fromJson(Map<String, dynamic> j) => Pedido.fromMap(j);

  /// JSON para escrever no Supabase (snake_case).
  /// - Não inclui `id` por padrão (deixe o banco gerar). Use `includeId: true` apenas se necessário.
  /// - `produtos`: List JSON
  /// - `assinatura_base64`: texto base64 simples (sem data URI)
  Map<String, dynamic> toSupabase({
    bool includeAssinatura = true,
    bool includeId = false, // <- NÃO enviamos id por padrão
  }) {
    final map = <String, dynamic>{
      // 'id' só entra se includeId==true e id>0
      if (includeId && id > 0) 'id': id,
      'numero': numero,
      'produtos': itens.map((e) => e.toMap()).toList(),
      'total': _round2(total),
      'status': status,
      'datahora': datahora ?? DateTime.now().toUtc().toIso8601String(),
      'vendedor_codigo': vendedorCodigo,
      'vendedor_nome': vendedorNome,
      'cliente_id': clienteId,
      'cliente_nome': clienteNome,
      'cliente_nome_fantasia': clienteNomeFantasia,
      'cliente_telefone': clienteTelefone,
      'cliente_whatsapp': clienteWhatsapp,
      'cliente_email': clienteEmail,
      'cliente_endereco': clienteEndereco,
      'cliente_cidade': clienteCidade,
      'cliente_cpf_cnpj': clienteCpfCnpj,
      'cliente_insc_estadual': clienteInscEstadual,
      'cliente_cep': clienteCep,
      'cliente_anotacao': clienteAnotacao,
    };

    if (includeAssinatura) {
      final b64 = _encodeBase64(assinaturaBytes);
      if (b64 != null) map['assinatura_base64'] = b64;
    }

    map.removeWhere((k, v) => v == null);
    return map;
  }

  /// JSON “neutro” para salvar localmente (mantém bytes como base64 para portabilidade).
  Map<String, dynamic> toJsonLocal() => {
    'id': id,
    'numero': numero,
    'itens': itens.map((e) => e.toMap()).toList(),
    'total': _round2(total),
    'status': status,
    'datahora': datahora,
    'vendedorCodigo': vendedorCodigo,
    'vendedorNome': vendedorNome,
    'clienteId': clienteId,
    'clienteNome': clienteNome,
    'clienteNomeFantasia': clienteNomeFantasia,
    'clienteTelefone': clienteTelefone,
    'clienteWhatsapp': clienteWhatsapp,
    'clienteEmail': clienteEmail,
    'clienteEndereco': clienteEndereco,
    'clienteCidade': clienteCidade,
    'clienteCpfCnpj': clienteCpfCnpj,
    'clienteInscEstadual': clienteInscEstadual,
    'clienteCep': clienteCep,
    'clienteAnotacao': clienteAnotacao,
    'assinatura_base64': _encodeBase64(assinaturaBytes),
  }..removeWhere((k, v) => v == null);

  Pedido copyWith({
    int? id,
    String? numero,
    List<PedidoItem>? itens,
    double? total,
    String? status,
    String? datahora,
    String? vendedorCodigo,
    String? vendedorNome,
    int? clienteId,
    String? clienteNome,
    String? clienteNomeFantasia,
    String? clienteTelefone,
    String? clienteWhatsapp,
    String? clienteEmail,
    String? clienteEndereco,
    String? clienteCidade,
    String? clienteCpfCnpj,
    String? clienteInscEstadual,
    String? clienteCep,
    String? clienteAnotacao,
    DateTime? enviadoEm,
    DateTime? alteradoEm,
    String? alteradoEmBruto,
    DateTime? prontoEm,
    String? prontoPor,
    DateTime? finalizadoEm,
    String? finalizadoPor,
    bool? finalizadoManual,
    DateTime? canceladoEm,
    String? canceladoPor,
    Uint8List? assinaturaBytes,
    Uint8List? assinaturaPedidoBytes,
  }) {
    final newItens = itens ?? this.itens;
    final newTotal = total ?? _calcTotal(newItens, this.total);
    return Pedido(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      itens: newItens,
      total: _round2(newTotal),
      status: status ?? this.status,
      datahora: datahora ?? this.datahora,
      vendedorCodigo: vendedorCodigo ?? this.vendedorCodigo,
      vendedorNome: vendedorNome ?? this.vendedorNome,
      clienteId: clienteId ?? this.clienteId,
      clienteNome: clienteNome ?? this.clienteNome,
      clienteNomeFantasia: clienteNomeFantasia ?? this.clienteNomeFantasia,
      clienteTelefone: clienteTelefone ?? this.clienteTelefone,
      clienteWhatsapp: clienteWhatsapp ?? this.clienteWhatsapp,
      clienteEmail: clienteEmail ?? this.clienteEmail,
      clienteEndereco: clienteEndereco ?? this.clienteEndereco,
      clienteCidade: clienteCidade ?? this.clienteCidade,
      clienteCpfCnpj: clienteCpfCnpj ?? this.clienteCpfCnpj,
      clienteInscEstadual: clienteInscEstadual ?? this.clienteInscEstadual,
      clienteCep: clienteCep ?? this.clienteCep,
      clienteAnotacao: clienteAnotacao ?? this.clienteAnotacao,
      enviadoEm: enviadoEm ?? this.enviadoEm,
      alteradoEm: alteradoEm ?? this.alteradoEm,
      alteradoEmBruto: alteradoEmBruto ?? this.alteradoEmBruto,
      prontoEm: prontoEm ?? this.prontoEm,
      prontoPor: prontoPor ?? this.prontoPor,
      finalizadoEm: finalizadoEm ?? this.finalizadoEm,
      finalizadoPor: finalizadoPor ?? this.finalizadoPor,
      finalizadoManual: finalizadoManual ?? this.finalizadoManual,
      canceladoEm: canceladoEm ?? this.canceladoEm,
      canceladoPor: canceladoPor ?? this.canceladoPor,
      assinaturaBytes: assinaturaBytes ?? this.assinaturaBytes,
      assinaturaPedidoBytes: assinaturaPedidoBytes ?? this.assinaturaPedidoBytes,
    );
  }

  /// Foi alterado depois de enviado.
  bool get alteradoDepoisDeEnviar =>
      alteradoEm != null && enviadoEm != null && alteradoEm!.isAfter(enviadoEm!);

  /// Em aberto, marcado pronto antes e alterado depois disso: a fábrica
  /// precisa conferir o que mudou.
  bool get alteradoDepoisDePronto =>
      status == 'salvo' &&
      prontoEm != null &&
      alteradoEm != null &&
      alteradoEm!.isAfter(prontoEm!);

  String get situacaoTexto {
    switch (status) {
      case 'salvo':
        return 'Em aberto';
      case 'pronto':
        return 'Pronto para entrega';
      case 'finalizado':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  // opcional: utilitários
  bool get temAssinatura => (assinaturaBytes != null && assinaturaBytes!.isNotEmpty);
  int get totalItens => itens.fold<int>(0, (s, it) => s + it.quantidade);
}
