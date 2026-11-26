// lib/financeiro/modelos_financeiro.dart
import 'package:intl/intl.dart';

/// Reais (num) -> centavos inteiros, sem erro de ponto flutuante acumulado.
int centavos(num v) => (v * 100).round();

num _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim()) ?? 0;
  return 0;
}

DateTime _toData(dynamic v) {
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  final s = (v ?? '').toString().trim();
  final d = DateTime.parse(s.length >= 10 ? s.substring(0, 10) : s);
  return DateTime(d.year, d.month, d.day);
}

class CategoriaSaida {
  final int id;
  final String nome;
  final bool ativa;
  final int ordem;

  const CategoriaSaida({
    required this.id,
    required this.nome,
    required this.ativa,
    required this.ordem,
  });

  factory CategoriaSaida.fromMap(Map<String, dynamic> m) => CategoriaSaida(
        id: _toNum(m['id']).toInt(),
        nome: (m['nome'] ?? '').toString(),
        ativa: m['ativa'] == null ? true : m['ativa'] == true,
        ordem: _toNum(m['ordem']).toInt(),
      );
}

class Saida {
  final int? id;
  final DateTime data;
  final int categoriaId;
  final String descricao;
  final int valorCentavos;
  final String? criadoPor;
  final DateTime? criadoEm;

  const Saida({
    this.id,
    required this.data,
    required this.categoriaId,
    this.descricao = '',
    required this.valorCentavos,
    this.criadoPor,
    this.criadoEm,
  });

  factory Saida.fromMap(Map<String, dynamic> m) {
    final criado = m['criado_em'];
    return Saida(
      id: m['id'] == null ? null : _toNum(m['id']).toInt(),
      data: _toData(m['data']),
      categoriaId: _toNum(m['categoria_id']).toInt(),
      descricao: (m['descricao'] ?? '').toString(),
      valorCentavos: centavos(_toNum(m['valor'])),
      criadoPor: m['criado_por']?.toString(),
      criadoEm: criado is String ? DateTime.tryParse(criado) : null,
    );
  }

  /// Só o que o cliente pode gravar. Sem `id` nem auditoria (o banco preenche).
  Map<String, dynamic> toGravar() => {
        'data': DateFormat('yyyy-MM-dd').format(data),
        'categoria_id': categoriaId,
        'descricao': descricao,
        'valor': valorCentavos / 100,
      };
}

final _fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// 842000 -> "R$ 8.420,00"; negativo -> "-R$ 3.290,00".
String fmtCentavos(int c) {
  final s = _fmt.format(c.abs() / 100).replaceAll(' ', ' ');
  return c < 0 ? '-$s' : s;
}

const int _maxCentavos = 999999999999;

/// Texto digitado (formato brasileiro) -> centavos; null se inválido ou <= 0.
int? parseValorCentavos(String texto) {
  var t = texto.trim();
  if (t.startsWith('R\$')) t = t.substring(2);
  t = t.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;

  String inteiro;
  String frac = '';
  if (t.contains(',')) {
    final limpo = t.replaceAll('.', '');
    final m = RegExp(r'^(\d+),(\d{1,2})$').firstMatch(limpo);
    if (m == null) return null;
    inteiro = m.group(1)!;
    frac = m.group(2)!;
  } else if (RegExp(r'^\d+$').hasMatch(t)) {
    inteiro = t;
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    inteiro = t.replaceAll('.', '');
  } else {
    final m = RegExp(r'^(\d+)\.(\d{1,2})$').firstMatch(t);
    if (m == null) return null;
    inteiro = m.group(1)!;
    frac = m.group(2)!;
  }
  final i = int.tryParse(inteiro);
  final f = int.tryParse(frac.padRight(2, '0'));
  if (i == null || f == null) return null;
  // numeric(12,2): no máximo 9.999.999.999,99.
  if (i > 9999999999) return null;
  final c = i * 100 + f;
  return c > 0 && c <= _maxCentavos ? c : null;
}

/// [inicio, fim) do mês, em hora local.
({DateTime inicio, DateTime fim}) intervaloDoMes(int ano, int mes) =>
    (inicio: DateTime(ano, mes, 1), fim: DateTime(ano, mes + 1, 1));
