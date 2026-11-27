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

  /// Entregues sem internet: `finalizado` sem `finalizado_em` legível (o
  /// servidor ainda não devolveu a data). Não entram em "Vendido".
  final int aguardandoEnvioPedidos;
  final double aguardandoEnvioValor;

  const ResumoVendas({
    required this.vendido,
    required this.pedidos,
    required this.ticketMedio,
    required this.aEntregarValor,
    required this.aEntregarPedidos,
    required this.porProduto,
    required this.melhoresClientes,
    this.aguardandoEnvioPedidos = 0,
    this.aguardandoEnvioValor = 0,
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

bool _soLocal(Map p) {
  final v = p['so_local'];
  return v == true || v == 1 || v == '1';
}

/// Quando a venda foi entregue (hora local), ou `null` se o pedido não é venda
/// deste vendedor (outro vendedor, apagado, fora de `finalizado`) ou a data é
/// ilegível. Regra única de "venda", usada pelo resumo e pela tela inicial.
DateTime? _quandoVendeu(Map p, String vendedorCodigo) {
  if ('${p['vendedor_codigo'] ?? ''}' != vendedorCodigo) return null;
  if (apagadoNoControle(p)) return null;
  if (_status(p) != 'finalizado') return null;
  return DateTime.tryParse('${p['finalizado_em'] ?? ''}'.trim())?.toLocal();
}

/// Total vendido em [mes]/[ano] (hora local); a mesma regra do resumo, sem
/// montar produtos nem clientes (para a tela inicial).
double vendidoNoMes(
  List<Map<String, dynamic>> pedidos, {
  required String vendedorCodigo,
  required int ano,
  required int mes,
}) {
  var soma = 0.0;
  for (final p in pedidos) {
    final q = _quandoVendeu(p, vendedorCodigo);
    if (q == null || q.year != ano || q.month != mes) continue;
    soma += _dinheiro(p['total']) ?? 0;
  }
  return soma;
}

/// Resumo de [mes]/[ano] (hora local) para [vendedorCodigo]. Com [ate], só
/// conta venda entregue até esse instante (hora local), para comparar o mês
/// atual com o mesmo trecho do mês anterior.
ResumoVendas resumoDoMes(
  List<Map<String, dynamic>> pedidos, {
  required String vendedorCodigo,
  required int ano,
  required int mes,
  DateTime? ate,
}) {
  var vendido = 0.0;
  var aguardandoPedidos = 0;
  var aguardandoValor = 0.0;
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
      // Rascunho só do aparelho não é pedido para entregar.
      if (_soLocal(p)) continue;
      aEntregarPedidos++;
      aEntregarValor += _dinheiro(p['total']) ?? 0;
      continue;
    }
    if (status != 'finalizado') continue;

    final quando = _quandoVendeu(p, vendedorCodigo);
    if (quando == null) {
      if (!_soLocal(p)) {
        aguardandoPedidos++;
        aguardandoValor += _dinheiro(p['total']) ?? 0;
      }
      continue;
    }
    if (quando.year != ano || quando.month != mes) continue;
    if (ate != null && quando.isAfter(ate)) continue;

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

    final exibido = nomeExibicao(clienteDoPedido(p));
    final nome = exibido.isEmpty ? 'Cliente sem nome' : exibido;
    final id = p['cliente_id'];
    final chave = id != null && '$id'.trim().isNotEmpty ? 'id:$id' : 'nome:${_chave(nome)}';
    final c = clientes.putIfAbsent(chave, () => _AcumuladoCliente(nome, quando));
    c.pedidos++;
    c.valor += total;
    // Empate no horário: fica o nome menor (sem caixa), para não depender da
    // ordem em que os pedidos chegam.
    final empate = quando.isAtSameMomentAs(c.recente) &&
        nome.toLowerCase().compareTo(c.nome.toLowerCase()) < 0;
    if (c.pedidos == 1 || quando.isAfter(c.recente) || empate) {
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
    aguardandoEnvioPedidos: aguardandoPedidos,
    aguardandoEnvioValor: aguardandoValor,
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

/// Limite da comparação do mês atual: o mesmo dia e hora de [agora] no mês
/// anterior; se o mês anterior for mais curto, o fim dele.
DateTime limiteMesAnterior(DateTime agora) {
  final ano = agora.month == 1 ? agora.year - 1 : agora.year;
  final mes = agora.month == 1 ? 12 : agora.month - 1;
  final fim = DateTime(ano, mes + 1, 1).subtract(const Duration(microseconds: 1));
  if (agora.day > fim.day) return fim;
  return DateTime(ano, mes, agora.day, agora.hour, agora.minute, agora.second,
      agora.millisecond, agora.microsecond);
}
