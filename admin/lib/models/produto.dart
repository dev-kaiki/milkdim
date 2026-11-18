import 'dart:convert';

class Produto {
  final int id;
  final String? codigo;
  final String nome;
  final String? unidade;
  final double preco;
  final bool ativo;
  final String? datahora; // ISO UTC opcional

  const Produto({
    required this.id,
    this.codigo,
    required this.nome,
    this.unidade,
    required this.preco,
    required this.ativo,
    this.datahora,
  });

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 't' || s == 'y' || s == 'sim';
    }
    return true;
  }

  static T? _pick<T>(Map m, String a, String b) => (m[a] ?? m[b]) as T?;

  factory Produto.fromMap(Map<String, dynamic> m) => Produto(
    id     : _toInt(_pick(m, 'id', 'id')),
    codigo : _pick(m, 'codigo', 'codigo'),
    nome   : (_pick(m, 'nome', 'nome') ?? '') as String,
    unidade: _pick(m, 'unidade', 'unidade'),
    preco  : _toDouble(_pick(m, 'preco', 'preco')),
    ativo  : _toBool(_pick(m, 'ativo', 'ativo')),
    datahora: _pick(m, 'datahora', 'datahora'),
  );

  factory Produto.fromJson(Map<String, dynamic> j) => Produto.fromMap(j);

  Map<String, dynamic> toSupabase() => {
    'id'     : id,
    'codigo' : codigo,
    'nome'   : nome,
    'unidade': unidade,
    'preco'  : preco,
    'ativo'  : ativo,
    'datahora': datahora,
  }..removeWhere((k, v) => v == null);
}
