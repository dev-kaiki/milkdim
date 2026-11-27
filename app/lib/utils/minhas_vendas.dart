// lib/utils/minhas_vendas.dart
//
// Lógica pura de "Minhas vendas": resumo do mês do vendedor, a partir dos
// pedidos que já estão no aparelho. Só lê; não grava nada.
import 'clientes_sumidos.dart' show nomeExibicao;
import 'entregas.dart' show clienteDoPedido;
import 'regras_pedido.dart' show apagadoNoControle;
import 'repetir_pedido.dart' show lerItensDoPedido;

class VendaProduto {
  final String nome;
  final int unidades;
  final double valor;
  const VendaProduto({required this.nome, required this.unidades, required this.valor});
}

class VendaCliente {
  final String nome;
  final int pedidos;
  final double valor;
  const VendaCliente({required this.nome, required this.pedidos, required this.valor});
}

class ResumoVendas {
  final double vendido;
  final int pedidos;

  /// `null` quando não há pedido no mês.
  final double? ticketMedio;

  /// Pedidos `salvo`/`pronto` do vendedor (qualquer mês). Quem decide mostrar
  /// só no mês atual é a tela.
  final double aEntregarValor;
  final int aEntregarPedidos;
  final List<VendaProduto> porProduto;
  final List<VendaCliente> melhoresClientes;

  const ResumoVendas({
    required this.vendido,
    required this.pedidos,
    required this.ticketMedio,
    required this.aEntregarValor,
    required this.aEntregarPedidos,
    required this.porProduto,
    required this.melhoresClientes,
  });
}

/// Número de um campo que pode vir como número ou texto ("12,50"); null se
/// ilegível.
double? _dinheiro(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

String _status(Map p) => '${p['status'] ?? ''}'.trim().toLowerCase();

String _chave(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class _AcumuladoProduto {
  final String nome;
  int unidades = 0;
  double valor = 0;
  _AcumuladoProduto(this.nome);
}

class _AcumuladoCliente {
  String nome;
  DateTime recente;
  int pedidos = 0;
  double valor = 0;
  _AcumuladoCliente(this.nome, this.recente);
}

/// Resumo de [mes]/[ano] (hora local) para [vendedorCodigo].
ResumoVendas resumoDoMes(
  List<Map<String, dynamic>> pedidos, {
  required String vendedorCodigo,
  required int ano,
  required int mes,
}) {
  var vendido = 0.0;
  var contados = 0;
  var aEntregarValor = 0.0;
  var aEntregarPedidos = 0;
  final produtos = <String, _AcumuladoProduto>{};
  final clientes = <String, _AcumuladoCliente>{};

  for (final p in pedidos) {
    if ('${p['vendedor_codigo'] ?? ''}' != vendedorCodigo) continue;
    if (apagadoNoControle(p)) continue;
    final status = _status(p);

    if (status == 'salvo' || status == 'pronto') {
      aEntregarPedidos++;
      aEntregarValor += _dinheiro(p['total']) ?? 0;
      continue;
    }
    if (status != 'finalizado') continue;

    final quando = DateTime.tryParse('${p['finalizado_em'] ?? ''}'.trim())?.toLocal();
    if (quando == null || quando.year != ano || quando.month != mes) continue;

    final total = _dinheiro(p['total']) ?? 0;
    vendido += total;
    contados++;

    for (final item in lerItensDoPedido(p['produtos'])) {
      final valor = _dinheiro(item.subtotal) ??
          (_dinheiro(item.preco) ?? 0) * item.quantidade;
      final a = produtos.putIfAbsent(_chave(item.nome), () => _AcumuladoProduto(item.nome));
      a.unidades += item.quantidade;
      a.valor += valor;
    }

    final nome = nomeExibicao(clienteDoPedido(p));
    final id = p['cliente_id'];
    final chave = id != null && '$id'.trim().isNotEmpty ? 'id:$id' : 'nome:${_chave(nome)}';
    final c = clientes.putIfAbsent(chave, () => _AcumuladoCliente(nome, quando));
    c.pedidos++;
    c.valor += total;
    if (c.pedidos == 1 || quando.isAfter(c.recente)) {
      c.recente = quando;
      c.nome = nome;
    }
  }

  final porProduto = [
    for (final a in produtos.values)
      VendaProduto(nome: a.nome, unidades: a.unidades, valor: a.valor),
  ]..sort((a, b) {
      final c = b.valor.compareTo(a.valor);
      return c != 0 ? c : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

  final melhores = [
    for (final c in clientes.values)
      VendaCliente(nome: c.nome, pedidos: c.pedidos, valor: c.valor),
  ]..sort((a, b) {
      final c = b.valor.compareTo(a.valor);
      return c != 0 ? c : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

  return ResumoVendas(
    vendido: vendido,
    pedidos: contados,
    ticketMedio: contados == 0 ? null : vendido / contados,
    aEntregarValor: aEntregarValor,
    aEntregarPedidos: aEntregarPedidos,
    porProduto: porProduto,
    melhoresClientes: melhores.take(5).toList(),
  );
}

/// "▲ N%", "▼ N%" ou "= 0%" em relação ao mês anterior; `null` quando o
/// anterior é zero (não há base de comparação).
String? textoVariacao(double atual, double anterior) {
  if (anterior == 0) return null;
  final n = ((atual - anterior) / anterior * 100).round();
  if (n > 0) return '▲ $n%';
  if (n < 0) return '▼ ${-n}%';
  return '= 0%';
}
