// lib/utils/repetir_pedido.dart
//
// Lógica pura de "repetir pedido": casa os itens de um pedido antigo com o
// catálogo de hoje. Os itens antigos não têm id de produto, só o nome, então o
// casamento é por nome (sem caixa e sem espaços sobrando).
import 'dart:convert';

import 'produto.dart';
import 'regras_pedido.dart' show apagadoNoControle;

/// Resultado de preencher um pedido novo a partir de um antigo.
class Preenchimento {
  /// Só produtos com quantidade > 0.
  final Map<Produto, int> quantidades;

  /// Nomes (como estavam no pedido antigo) que não existem mais no catálogo,
  /// sem repetição e na ordem em que aparecem.
  final List<String> foraDoPedido;

  const Preenchimento({required this.quantidades, required this.foraDoPedido});
}

/// Um item válido do pedido antigo.
class _Item {
  final String nome;
  final int quantidade;
  const _Item(this.nome, this.quantidade);
}

String _normalizar(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

int _quantidade(Object? v) {
  if (v is num) return v.round();
  if (v is String) {
    final n = num.tryParse(v.trim().replaceAll(',', '.'));
    return n == null ? 0 : n.round();
  }
  return 0;
}

/// Lê os itens de um pedido antigo (`List` ou `String` JSON), ignorando
/// itens inválidos ou com quantidade <= 0. Nunca lança.
List<_Item> _lerItens(Object? produtosDoPedido) {
  Object? dados = produtosDoPedido;
  if (dados is String) {
    try {
      dados = jsonDecode(dados);
    } catch (_) {
      return const [];
    }
  }
  if (dados is! List) return const [];

  final itens = <_Item>[];
  for (final raw in dados) {
    if (raw is! Map) continue;
    final nome = (raw['nome'] ?? '').toString().trim();
    final qtd = _quantidade(raw['quantidade']);
    if (nome.isEmpty || qtd <= 0) continue;
    itens.add(_Item(nome, qtd));
  }
  return itens;
}

/// Casa os itens do pedido antigo com os produtos de hoje.
Preenchimento preencherDePedido(Object? produtosDoPedido, List<Produto> produtosDeHoje) {
  final porNome = <String, Produto>{};
  for (final p in produtosDeHoje) {
    porNome.putIfAbsent(_normalizar(p.nome), () => p);
  }

  final quantidades = <Produto, int>{};
  final fora = <String>[];
  for (final item in _lerItens(produtosDoPedido)) {
    final produto = porNome[_normalizar(item.nome)];
    if (produto == null) {
      if (!fora.contains(item.nome)) fora.add(item.nome);
    } else {
      quantidades[produto] = (quantidades[produto] ?? 0) + item.quantidade;
    }
  }
  return Preenchimento(quantidades: quantidades, foraDoPedido: fora);
}

/// Resumo curto dos itens, ex.: "Pote 160g ×40, Copo ×20 …".
String resumoItens(Object? produtosDoPedido, {int max = 3}) {
  final itens = _lerItens(produtosDoPedido);
  if (itens.isEmpty) return 'Sem itens';
  final texto = itens.take(max).map((i) => '${i.nome} ×${i.quantidade}').join(', ');
  return itens.length > max ? '$texto …' : texto;
}

/// Pedidos que vale oferecer para repetir: sem cancelados, sem os apagados no
/// Controle, sem os que não têm itens legíveis, do mais novo para o mais velho (datas ilegíveis no fim) e no máximo 5.
List<Map<String, dynamic>> pedidosParaRepetir(List<Map<String, dynamic>> pedidos) {
  final candidatos = <MapEntry<int, Map<String, dynamic>>>[];
  for (final p in pedidos) {
    if ((p['status'] ?? '').toString() == 'cancelado') continue;
    if (apagadoNoControle(p)) continue;
    if (_lerItens(p['produtos']).isEmpty) continue;
    candidatos.add(MapEntry(candidatos.length, p));
  }

  DateTime? data(Map<String, dynamic> p) =>
      DateTime.tryParse((p['datahora'] ?? '').toString());

  candidatos.sort((a, b) {
    final da = data(a.value);
    final db = data(b.value);
    if (da == null && db == null) return a.key.compareTo(b.key);
    if (da == null) return 1;
    if (db == null) return -1;
    final c = db.compareTo(da);
    return c != 0 ? c : a.key.compareTo(b.key);
  });

  return candidatos.take(5).map((e) => e.value).toList();
}
