import 'dart:convert';

class Cliente {
  final int id;
  final String? nome;
  final String? nomeFantasia;
  final String? cpfCnpj;
  final String? telefone;
  final String? whatsapp;
  final String? email;
  final String? endereco;
  final String? cidade;
  final String? cep;
  final String? inscEstadual;
  final String? anotacao;
  final bool ativo;
  /// ISO-8601 (UTC) no Supabase
  final String? datahora;

  /// Opcional: última data de pedido (ISO) vinda de view/join; no cliente usamos para badge
  final String? ultimoPedido;

  const Cliente({
    required this.id,
    this.nome,
    this.nomeFantasia,
    this.cpfCnpj,
    this.telefone,
    this.whatsapp,
    this.email,
    this.endereco,
    this.cidade,
    this.cep,
    this.inscEstadual,
    this.anotacao,
    required this.ativo,
    this.datahora,
    this.ultimoPedido,
  });

  // ---------- helpers ----------
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
    return true; // default ativo
  }

  static String? _toStrN(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static T? _pick<T>(Map m, String a, String b) => (m[a] ?? m[b]) as T?;

  // ---------- factories ----------
  factory Cliente.fromMap(Map<String, dynamic> m) => Cliente(
    id            : _toInt(_pick(m, 'id', 'id')),
    nome          : _pick(m, 'nome', 'nome'),
    nomeFantasia  : _pick(m, 'nome_fantasia', 'nomeFantasia'),
    cpfCnpj       : _pick(m, 'cpf_cnpj', 'cpfCnpj'),
    telefone      : _pick(m, 'telefone', 'telefone'),
    whatsapp      : _pick(m, 'whatsapp', 'whatsapp'),
    email         : _pick(m, 'email', 'email'),
    endereco      : _pick(m, 'endereco', 'endereco'),
    cidade        : _pick(m, 'cidade', 'cidade'),
    cep           : _pick(m, 'cep', 'cep'),
    inscEstadual  : _pick(m, 'insc_estadual', 'inscEstadual'),
    anotacao      : _pick(m, 'anotacao', 'anotacao'),
    ativo         : _toBool(_pick(m, 'ativo', 'ativo')),
    datahora      : _pick(m, 'datahora', 'datahora'),
    ultimoPedido  : _pick(m, 'ultimo_pedido', 'ultimoPedido'),
  );

  factory Cliente.fromJson(Map<String, dynamic> j) => Cliente.fromMap(j);

  // ---------- serialize p/ Supabase (snake_case) ----------
  Map<String, dynamic> toSupabase() => {
    'id'             : id,
    'nome'           : _toStrN(nome),
    'nome_fantasia'  : _toStrN(nomeFantasia),
    'cpf_cnpj'       : _toStrN(cpfCnpj),
    'telefone'       : _toStrN(telefone),
    'whatsapp'       : _toStrN(whatsapp),
    'email'          : _toStrN(email),
    'endereco'       : _toStrN(endereco),
    'cidade'         : _toStrN(cidade),
    'cep'            : _toStrN(cep),
    'insc_estadual'  : _toStrN(inscEstadual),
    'anotacao'       : _toStrN(anotacao),
    'ativo'          : ativo,
    'datahora'       : _toStrN(datahora),
  }..removeWhere((k, v) => v == null);
}
