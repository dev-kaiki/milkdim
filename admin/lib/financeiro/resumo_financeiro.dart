// lib/financeiro/resumo_financeiro.dart
import '../models/pedido.dart';
import 'modelos_financeiro.dart';

class LinhaValor {
  final String rotulo;
  final int centavos;
  final int quantidade;
  const LinhaValor({
    required this.rotulo,
    required this.centavos,
    required this.quantidade,
  });
}

class ResumoMes {
  final int vendasCentavos;
  final int pedidos;
  final int saidasCentavos;
  final List<LinhaValor> porVendedor;
  final List<LinhaValor> porProduto;
  final List<LinhaValor> porCategoria;
  final int aReceberPedidos;
  final int aReceberCentavos;

  const ResumoMes({
    required this.vendasCentavos,
    required this.pedidos,
    required this.saidasCentavos,
    required this.porVendedor,
    required this.porProduto,
    required this.porCategoria,
    required this.aReceberPedidos,
    required this.aReceberCentavos,
  });

  int get resultadoCentavos => vendasCentavos - saidasCentavos;
}

List<LinhaValor> ordenarLinhas(Map<String, List<int>> g) {
  final l = [
    for (final e in g.entries)
      LinhaValor(rotulo: e.key, centavos: e.value[0], quantidade: e.value[1]),
  ];
  l.sort((a, b) {
    final c = b.centavos.compareTo(a.centavos);
    return c != 0 ? c : a.rotulo.compareTo(b.rotulo);
  });
  return l;
}

void somarLinha(Map<String, List<int>> g, String rotulo, int cent, int qtd) {
  final v = g.putIfAbsent(rotulo, () => [0, 0]);
  v[0] += cent;
  v[1] += qtd;
}

ResumoMes resumirMes({
  required List<Pedido> entregues,
  required List<Pedido> prontos,
  required List<Saida> saidas,
  required Map<int, String> nomesCategorias,
}) {
  final vendas = entregues.where((p) => p.status == 'finalizado').toList();
  final vendedores = <String, List<int>>{};
  final produtos = <String, List<int>>{};
  var totalVendas = 0;
  for (final p in vendas) {
    final cent = centavos(p.total);
    totalVendas += cent;
    final nome = (p.vendedorNome ?? '').trim();
    final codigo = (p.vendedorCodigo ?? '').trim();
    final rotulo = nome.isNotEmpty
        ? nome
        : (codigo.isNotEmpty ? codigo : 'Sem vendedor');
    somarLinha(vendedores, rotulo, cent, 1);
    for (final it in p.itens) {
      somarLinha(produtos, it.nome.trim(), centavos(it.subtotal), it.quantidade);
    }
  }

  final categorias = <String, List<int>>{};
  var totalSaidas = 0;
  for (final s in saidas) {
    totalSaidas += s.valorCentavos;
    somarLinha(categorias, nomesCategorias[s.categoriaId] ?? 'Sem categoria',
        s.valorCentavos, 1);
  }

  return ResumoMes(
    vendasCentavos: totalVendas,
    pedidos: vendas.length,
    saidasCentavos: totalSaidas,
    porVendedor: ordenarLinhas(vendedores),
    porProduto: ordenarLinhas(produtos),
    porCategoria: ordenarLinhas(categorias),
    aReceberPedidos: prontos.length,
    aReceberCentavos: prontos.fold(0, (s, p) => s + centavos(p.total)),
  );
}
