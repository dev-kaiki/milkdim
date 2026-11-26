import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/financeiro/painel_financeiro.dart';
import 'package:milkdim_admin/financeiro/resumo_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';

Pedido _p(
  int id,
  DateTime? quando,
  double total, {
  String status = 'finalizado',
  int? clienteId,
  String? nome,
  String? fantasia,
  String? vendedor,
  String? codigo,
}) =>
    Pedido(
      id: id,
      itens: const [],
      total: total,
      status: status,
      finalizadoEm: quando,
      clienteId: clienteId,
      clienteNome: nome,
      clienteNomeFantasia: fantasia,
      vendedorNome: vendedor,
      vendedorCodigo: codigo,
    );

Saida _s(DateTime d, int cent) =>
    Saida(data: d, categoriaId: 1, valorCentavos: cent);

void main() {
  test('período de comparação: mês encerrado = mês anterior inteiro', () {
    final p = periodoComparacaoPedidos(
        ano: 2026, mes: 10, agora: DateTime(2026, 11, 25, 10));
    expect(p.inicio, DateTime(2026, 9, 1));
    expect(p.fim, DateTime(2026, 10, 1));
  });
  test('período de comparação: mês atual = mesmos dias do mês anterior', () {
    final p = periodoComparacaoPedidos(
        ano: 2026, mes: 11, agora: DateTime(2026, 11, 25, 10));
    expect(p.inicio, DateTime(2026, 10, 1));
    expect(p.fim, DateTime(2026, 10, 25, 10));
  });
  test('período de comparação: 31/03 para no fim de fevereiro', () {
    final p = periodoComparacaoPedidos(
        ano: 2027, mes: 3, agora: DateTime(2027, 3, 31, 12));
    expect(p.fim, DateTime(2027, 3, 1));
  });
  test('período de comparação: virada de ano no mês atual', () {
    final p = periodoComparacaoPedidos(
        ano: 2027, mes: 1, agora: DateTime(2027, 1, 1, 0, 10));
    expect(p.inicio, DateTime(2026, 12, 1));
    expect(p.fim, DateTime(2026, 12, 1, 0, 10));
  });
  test('diaLimiteSaidas só no mês atual', () {
    expect(diaLimiteSaidas(ano: 2026, mes: 11, agora: DateTime(2026, 11, 25)),
        25);
    expect(diaLimiteSaidas(ano: 2026, mes: 10, agora: DateTime(2026, 11, 25)),
        isNull);
  });
  test('calcularVariacao', () {
    expect(calcularVariacao(110, 100)!.pct, 10);
    expect(calcularVariacao(110, 100)!.sentido, 1);
    expect(calcularVariacao(110, 100, maiorEhMelhor: false)!.sentido, -1);
    expect(calcularVariacao(100, 100)!.sentido, 0);
    expect(calcularVariacao(50, 0), isNull);
    final neg = calcularVariacao(-500, -1000, trocaDeSinal: true)!;
    expect(neg.pct, 50);
    expect(neg.sentido, 1);
    final virou = calcularVariacao(-200, 500, trocaDeSinal: true)!;
    expect(virou.pct, isNull);
    expect(virou.texto, 'virou negativo');
    expect(virou.sentido, -1);
    expect(calcularVariacao(300, -100, trocaDeSinal: true)!.texto,
        'virou positivo');
  });
  test('calcularVariacao: variação que arredonda para 0% é neutra', () {
    final v = calcularVariacao(100004, 100000)!;
    expect(v.pct, 0);
    expect(v.sentido, 0);
    final s = calcularVariacao(99996, 100000, maiorEhMelhor: false)!;
    expect(s.pct, 0);
    expect(s.sentido, 0);
  });
  test('calcularVariacao: resultado de -500 para 0 não "virou positivo"', () {
    final a = calcularVariacao(0, -500, trocaDeSinal: true)!;
    expect(a.texto, isNull);
    expect(a.pct, 100);
    expect(a.sentido, 1);
    final b = calcularVariacao(0, 500, trocaDeSinal: true)!;
    expect(b.texto, isNull);
    expect(b.pct, -100);
    expect(b.sentido, -1);
  });
  test('compararMes no mês atual usa o recorte nos dois lados', () {
    final r = compararMes(
      ano: 2026,
      mes: 11,
      agora: DateTime(2026, 11, 25, 10),
      entregues: [
        _p(1, DateTime(2026, 10, 10), 1.00),
        _p(2, DateTime(2026, 10, 28), 9.00),
        _p(3, DateTime(2026, 11, 5), 1.50),
      ],
      saidas: [
        _s(DateTime(2026, 10, 20), 40),
        _s(DateTime(2026, 10, 27), 500),
        _s(DateTime(2026, 11, 10), 60),
        _s(DateTime(2026, 11, 30), 999),
      ],
    );
    expect(r.vendas!.pct, 50);
    expect(r.saidas!.pct, 50);
    expect(r.saidas!.sentido, -1);
    expect(r.resultado!.pct, 50);
    expect(r.resultado!.sentido, 1);
  });
  test('compararMes em mês encerrado usa os meses inteiros', () {
    final r = compararMes(
      ano: 2026,
      mes: 10,
      agora: DateTime(2026, 11, 25, 10),
      entregues: [
        _p(1, DateTime(2026, 9, 3), 1.00),
        _p(2, DateTime(2026, 9, 29), 1.00),
        _p(3, DateTime(2026, 10, 28), 3.00),
        _p(4, DateTime(2026, 11, 2), 50.00),
      ],
      saidas: [
        _s(DateTime(2026, 9, 29), 100),
        _s(DateTime(2026, 10, 28), 50),
        _s(DateTime(2026, 11, 2), 999),
      ],
    );
    expect(r.vendas!.pct, 50); // 300 vs 200
    expect(r.saidas!.pct, -50); // 50 vs 100
    expect(r.saidas!.sentido, 1);
    expect(r.resultado!.pct, 150); // 250 vs 100
    expect(r.resultado!.sentido, 1);
  });
  test('compararMes: limite 31/03 cobre fevereiro inteiro', () {
    final r = compararMes(
      ano: 2026,
      mes: 3,
      agora: DateTime(2026, 3, 31, 12),
      entregues: const [],
      saidas: [
        _s(DateTime(2026, 2, 28), 100),
        _s(DateTime(2026, 3, 5), 150),
      ],
    );
    expect(r.saidas!.pct, 50);
    expect(r.saidas!.sentido, -1);
  });
  test('compararMes ignora pedido não finalizado ou sem data', () {
    final r = compararMes(
      ano: 2026,
      mes: 10,
      agora: DateTime(2026, 11, 25),
      entregues: [
        _p(1, DateTime(2026, 9, 3), 1.00),
        _p(2, DateTime(2026, 10, 3), 2.00),
        _p(3, DateTime(2026, 10, 4), 99.00, status: 'cancelado'),
        _p(4, null, 99.00),
      ],
      saidas: const [],
    );
    expect(r.vendas!.pct, 100);
    expect(r.saidas, isNull);
  });
  test('serieDozeMeses cruza o ano e marca meses sem dado', () {
    final s = serieDozeMeses(
      ano: 2025,
      mes: 9,
      entregues: [
        _p(1, DateTime(2025, 8, 10), 5.00),
        _p(2, DateTime(2025, 9, 10), 10.00),
      ],
      saidas: [_s(DateTime(2025, 9, 12), 250)],
    );
    expect(s.length, 12);
    expect((s.first.ano, s.first.mes), (2024, 10));
    expect((s.last.ano, s.last.mes), (2025, 9));
    expect(s.map((m) => m.temDado).toList(),
        [...List.filled(10, false), true, true]);
    expect(s.last.margemPct, 75);
    expect(s.last.resultadoCentavos, 750);
    expect(s.last.pedidos, 1);
    expect(s[10].margemPct, 100);
    expect(s.first.margemPct, isNull);
  });
  test('serieDozeMeses: mês só com saída tem dado e margem nula', () {
    final s = serieDozeMeses(
      ano: 2025,
      mes: 9,
      entregues: const [],
      saidas: [_s(DateTime(2025, 9, 12), 250)],
    );
    expect(s.last.temDado, isTrue);
    expect(s.last.margemPct, isNull);
  });
  test('melhoresClientes agrupa por id, usa o nome mais recente e limita a 10',
      () {
    final lista = <Pedido>[
      _p(1, DateTime(2026, 11, 1), 10, clienteId: 7, nome: 'A'),
      _p(2, DateTime(2026, 11, 9), 10, clienteId: 7, nome: 'A Ltda'),
      _p(3, DateTime(2026, 11, 3), 5),
      for (var i = 0; i < 11; i++)
        _p(10 + i, DateTime(2026, 11, 2), 1.0 + i,
            clienteId: 100 + i, nome: 'C$i'),
    ];
    final r = melhoresClientes(lista);
    expect(r.length, 10);
    expect(r.first.rotulo, 'A Ltda');
    expect(r.first.quantidade, 2);
    expect(r.first.centavos, 2000);
    final todos = melhoresClientes(lista, limite: 50);
    expect(todos.map((l) => l.rotulo), contains('Sem nome'));
    for (var i = 1; i < r.length; i++) {
      expect(r[i - 1].centavos >= r[i].centavos, isTrue);
    }
  });
  test('melhoresClientes sem id agrupa por nome fantasia', () {
    final r = melhoresClientes([
      _p(1, DateTime(2026, 11, 1), 3, nome: 'Zé', fantasia: ' Mercado Zé '),
      _p(2, DateTime(2026, 11, 2), 4, nome: 'Outro', fantasia: 'Mercado Zé'),
    ]);
    expect(r.single.rotulo, 'Mercado Zé');
    expect(r.single.quantidade, 2);
  });
  test('pctDe', () {
    expect(pctDe(1, 3), 33);
    expect(pctDe(5, 0), isNull);
  });
  test('resumirMes: vendedor sem nome e sem código vira Sem vendedor', () {
    final r = resumirMes(
      entregues: [
        _p(1, DateTime(2026, 11, 1), 1, vendedor: '  ', codigo: ' '),
        _p(2, DateTime(2026, 11, 2), 2),
      ],
      prontos: const [],
      saidas: const [],
      nomesCategorias: const {},
    );
    expect(r.porVendedor.single.rotulo, 'Sem vendedor');
    expect(r.porVendedor.single.quantidade, 2);
  });
}
