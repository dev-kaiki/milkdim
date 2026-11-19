// lib/utils/produto.dart
//
// Correções:
// • factory aceita Map genérico (evita erro de tipo do analyzer ao vir Map<dynamic, dynamic> do SQLite)
// • Parsing robusto de id e preco (aceita num ou String com vírgula/ponto)
// • toMap() só inclui 'id' quando não-nulo
// • Igualdade/hashCode estáveis

class Produto {
  final int? id;
  final String nome;
  final double preco;

  const Produto({
    this.id,
    required this.nome,
    required this.preco,
  });

  Produto copyWith({
    int? id,
    String? nome,
    double? preco,
  }) {
    return Produto(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      preco: preco ?? this.preco,
    );
  }

  /// Aceita Map genérico (Map<dynamic, dynamic> ou Map<String, dynamic>)
  factory Produto.fromMap(Map map) {
    // id
    final rawId = map['id'];
    int? id;
    if (rawId is int) {
      id = rawId;
    } else if (rawId is String) {
      id = int.tryParse(rawId);
    }

    // nome (fallbacks comuns)
    final nome = (map['nome'] ?? map['descricao'] ?? map['titulo'] ?? '').toString();

    // preço (aceita num ou String com vírgula)
    final rawPreco = map['preco'] ?? map['valor'] ?? 0;
    double preco;
    if (rawPreco is num) {
      preco = rawPreco.toDouble();
    } else if (rawPreco is String) {
      preco = double.tryParse(rawPreco.replaceAll(',', '.')) ?? 0.0;
    } else {
      preco = 0.0;
    }

    return Produto(id: id, nome: nome, preco: preco);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nome': nome,
      'preco': preco,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Produto &&
        other.id == id &&
        other.nome == nome &&
        other.preco == preco;
  }

  @override
  int get hashCode => Object.hash(id, nome, preco);

  @override
  String toString() => 'Produto(id: $id, nome: $nome, preco: $preco)';
}
