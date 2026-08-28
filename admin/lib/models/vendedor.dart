class Vendedor {
  final int id;
  final String codigo;
  final String nome;
  final String senha; // plaintext por enquanto
  final bool ativo;
  final String? anotacao;

  const Vendedor({
    required this.id,
    required this.codigo,
    required this.nome,
    required this.senha,
    required this.ativo,
    this.anotacao,
  });

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

  static String _toStr(dynamic v) => v?.toString() ?? '';
  static T? _pick<T>(Map m, String a, String b) => (m[a] ?? m[b]) as T?;

  factory Vendedor.fromMap(Map<String, dynamic> m) => Vendedor(
    id     : _toInt(_pick(m, 'id', 'id')),
    codigo : _toStr(_pick(m, 'codigo', 'codigo')),
    nome   : _toStr(_pick(m, 'nome', 'nome')),
    senha  : _toStr(_pick(m, 'senha', 'senha')),
    ativo  : _toBool(_pick(m, 'ativo', 'ativo')),
    anotacao: _pick(m, 'anotacao', 'anotacao'),
  );

  factory Vendedor.fromJson(Map<String, dynamic> j) => Vendedor.fromMap(j);

  Map<String, dynamic> toSupabase() => {
    'id'     : id,
    'codigo' : codigo,
    'nome'   : nome,
    'senha'  : senha,
    'ativo'  : ativo,
    'anotacao': anotacao,
  }..removeWhere((k, v) => v == null);
}
