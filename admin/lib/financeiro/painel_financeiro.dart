// lib/financeiro/painel_financeiro.dart
// Contas do painel financeiro (Dart puro, sem Flutter).
import '../models/pedido.dart';
import 'modelos_financeiro.dart';
import 'resumo_financeiro.dart';

/// Vendas válidas: finalizadas e com data. Devolve (pedido, data local).
Iterable<(Pedido, DateTime)> _vendasComData(List<Pedido> entregues) sync* {
  for (final p in entregues) {
    if (p.status != 'finalizado' || p.finalizadoEm == null) continue;
    yield (p, p.finalizadoEm!.toLocal());
  }
}

int _somaVendas(List<Pedido> entregues, DateTime inicio, DateTime fim) {
  var t = 0;
  for (final (p, d) in _vendasComData(entregues)) {
    if (!d.isBefore(inicio) && d.isBefore(fim)) t += centavos(p.total);
  }
  return t;
}

int _somaSaidas(List<Saida> saidas, DateTime inicio, DateTime fim,
    {int? diaLimite}) {
  var t = 0;
  for (final s in saidas) {
    if (s.data.isBefore(inicio) || !s.data.isBefore(fim)) continue;
    if (diaLimite != null && s.data.day > diaLimite) continue;
    t += s.valorCentavos;
  }
  return t;
}

bool _ehMesAtual(int ano, int mes, DateTime agora) =>
    ano == agora.year && mes == agora.month;

/// Período dos pedidos usado como base de comparação.
/// Mês encerrado ou futuro: o mês anterior inteiro. Mês atual: do dia 1 do
/// mês anterior até o mesmo ponto do mês (limitado ao início do mês atual).
({DateTime inicio, DateTime fim}) periodoComparacaoPedidos({
  required int ano,
  required int mes,
  required DateTime agora,
}) {
  final inicioAnterior = DateTime(ano, mes - 1, 1);
  final inicioMes = DateTime(ano, mes, 1);
  if (!_ehMesAtual(ano, mes, agora)) {
    return (inicio: inicioAnterior, fim: inicioMes);
  }
  final fim = inicioAnterior.add(agora.difference(inicioMes));
  return (inicio: inicioAnterior, fim: fim.isAfter(inicioMes) ? inicioMes : fim);
}

/// Dia até o qual as saídas entram na comparação: só no mês atual.
int? diaLimiteSaidas({
  required int ano,
  required int mes,
  required DateTime agora,
}) =>
    _ehMesAtual(ano, mes, agora) ? agora.day : null;

class Variacao {
  /// Variação percentual arredondada; null quando há [texto] no lugar.
  final int? pct;

  /// Só na troca de sinal: 'virou positivo' / 'virou negativo'.
  final String? texto;

  /// 1 = melhora, -1 = piora, 0 = neutro.
  final int sentido;

  const Variacao({this.pct, this.texto, required this.sentido});
}

Variacao? calcularVariacao(
  int atual,
  int anterior, {
  bool maiorEhMelhor = true,
  bool trocaDeSinal = false,
}) {
  if (anterior == 0) return null;
  if (trocaDeSinal) {
    if (anterior < 0 && atual > 0) {
      return const Variacao(texto: 'virou positivo', sentido: 1);
    }
    if (anterior > 0 && atual < 0) {
      return const Variacao(texto: 'virou negativo', sentido: -1);
    }
  }
  final pct = ((atual - anterior) * 100 / anterior.abs()).round();
  final int sentido;
  if (atual == anterior || pct == 0) {
    sentido = 0;
  } else {
    final melhorou = maiorEhMelhor ? atual > anterior : atual < anterior;
    sentido = melhorou ? 1 : -1;
  }
  return Variacao(pct: pct, sentido: sentido);
}

class ComparacaoMes {
  final Variacao? vendas;
  final Variacao? saidas;
  final Variacao? resultado;
  const ComparacaoMes({this.vendas, this.saidas, this.resultado});
}

ComparacaoMes compararMes({
  required int ano,
  required int mes,
  required DateTime agora,
  required List<Pedido> entregues,
  required List<Saida> saidas,
}) {
  final atual = intervaloDoMes(ano, mes);
  final anterior = intervaloDoMes(ano, mes - 1);
  final comp = periodoComparacaoPedidos(ano: ano, mes: mes, agora: agora);
  final limite = diaLimiteSaidas(ano: ano, mes: mes, agora: agora);

  final vendasAtual = _somaVendas(entregues, atual.inicio, atual.fim);
  final vendasAnt = _somaVendas(entregues, comp.inicio, comp.fim);
  final saidasAtual =
      _somaSaidas(saidas, atual.inicio, atual.fim, diaLimite: limite);
  final saidasAnt =
      _somaSaidas(saidas, anterior.inicio, anterior.fim, diaLimite: limite);

  return ComparacaoMes(
    vendas: calcularVariacao(vendasAtual, vendasAnt),
    saidas: calcularVariacao(saidasAtual, saidasAnt, maiorEhMelhor: false),
    resultado: calcularVariacao(
      vendasAtual - saidasAtual,
      vendasAnt - saidasAnt,
      trocaDeSinal: true,
    ),
  );
}

/// Nomes de mês com 3 letras, índice 0 = Jan.
const List<String> mesesAbrev = [
  'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
  'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
];

class MesSerie {
  final int ano;
  final int mes;
  final int vendasCentavos;
  final int saidasCentavos;
  final int pedidos;
  const MesSerie({
    required this.ano,
    required this.mes,
    required this.vendasCentavos,
    required this.saidasCentavos,
    required this.pedidos,
  });

  bool get temDado => pedidos > 0 || saidasCentavos > 0;
  int get resultadoCentavos => vendasCentavos - saidasCentavos;
  int? get margemPct => vendasCentavos > 0
      ? (resultadoCentavos * 100 / vendasCentavos).round()
      : null;
}

/// Os 12 meses que terminam em [ano]/[mes], do mais antigo para o mais novo.
List<MesSerie> serieDozeMeses({
  required int ano,
  required int mes,
  required List<Pedido> entregues,
  required List<Saida> saidas,
}) {
  final vendas = <(Pedido, DateTime)>[..._vendasComData(entregues)];
  return [
    for (var k = -11; k <= 0; k++)
      () {
        final ini = DateTime(ano, mes + k, 1);
        final fim = DateTime(ano, mes + k + 1, 1);
        var v = 0;
        var n = 0;
        for (final (p, d) in vendas) {
          if (!d.isBefore(ini) && d.isBefore(fim)) {
            v += centavos(p.total);
            n++;
          }
        }
        return MesSerie(
          ano: ini.year,
          mes: ini.month,
          vendasCentavos: v,
          saidasCentavos: _somaSaidas(saidas, ini, fim),
          pedidos: n,
        );
      }(),
  ];
}

String _nomeExibido(Pedido p) {
  final f = (p.clienteNomeFantasia ?? '').trim();
  return f.isNotEmpty ? f : (p.clienteNome ?? '').trim();
}

/// Melhores clientes em R$. Agrupa por clienteId; sem id, pelo nome exibido.
/// O rótulo vem do pedido mais recente do grupo.
List<LinhaValor> melhoresClientes(List<Pedido> entregues, {int limite = 10}) {
  final totais = <String, List<int>>{};
  final recente = <String, (DateTime, String)>{};
  for (final (p, d) in _vendasComData(entregues)) {
    final nome = _nomeExibido(p);
    final chave = p.clienteId != null ? 'id:${p.clienteId}' : 'nome:$nome';
    somarLinha(totais, chave, centavos(p.total), 1);
    final r = recente[chave];
    if (r == null || d.isAfter(r.$1)) recente[chave] = (d, nome);
  }
  final l = [
    for (final e in totais.entries)
      LinhaValor(
        rotulo: recente[e.key]!.$2.isEmpty ? 'Sem nome' : recente[e.key]!.$2,
        centavos: e.value[0],
        quantidade: e.value[1],
      ),
  ]..sort((a, b) {
      final c = b.centavos.compareTo(a.centavos);
      return c != 0 ? c : a.rotulo.compareTo(b.rotulo);
    });
  return l.length > limite ? l.sublist(0, limite) : l;
}

int? pctDe(int parte, int total) =>
    total == 0 ? null : (parte * 100 / total).round();
