// lib/models/producao.dart
import 'pedido.dart';

class TotalProduto {
  final String nome;
  final int quantidade;
  const TotalProduto({required this.nome, required this.quantidade});
}

/// Total a fabricar por produto, considerando so pedidos em aberto ('salvo').
/// Ordena por quantidade decrescente e, no empate, por nome.
List<TotalProduto> totaisAFabricar(Iterable<Pedido> pedidos) {
  final soma = <String, int>{};
  for (final p in pedidos) {
    if (p.status != 'salvo') continue;
    for (final it in p.itens) {
      final nome = it.nome.trim();
      soma[nome] = (soma[nome] ?? 0) + it.quantidade;
    }
  }
  final lista = soma.entries
      .map((e) => TotalProduto(nome: e.key, quantidade: e.value))
      .toList()
    ..sort((a, b) {
      final c = b.quantidade.compareTo(a.quantidade);
      return c != 0 ? c : a.nome.compareTo(b.nome);
    });
  return lista;
}
