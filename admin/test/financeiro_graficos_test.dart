import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:milkdim_admin/financeiro/abas/graficos_financeiro.dart';
import 'package:milkdim_admin/financeiro/painel_financeiro.dart';

List<MesSerie> _serie() => [
      for (var i = 0; i < 12; i++)
        MesSerie(
          ano: 2026,
          mes: i + 1,
          vendasCentavos: i >= 10 ? (i == 10 ? 500000 : 120000) : 0,
          saidasCentavos: i >= 10 ? (i == 10 ? 200000 : 300000) : 0,
          pedidos: i >= 10 ? 3 : 0,
        ),
    ];

void main() {
  test('pontosResultado: mês sem dado vira nullSpot', () {
    final p = pontosResultado(_serie());
    expect(p.length, 12);
    expect(p.take(10).every((s) => s == FlSpot.nullSpot), isTrue);
    expect(p[10].x, 10);
    expect(p[10].y, 3000.0);
    expect(p[11].y, -1800.0);
  });

  for (final w in [360.0, 1000.0]) {
    testWidgets('gráficos renderizam sem exceção em ${w.toInt()} px',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: w,
              child: Column(children: [
                CurvaResultado(serie: _serie()),
                BarrasVendasSaidas(serie: _serie()),
              ]),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Vendas'), findsOneWidget);
      expect(find.text('Saídas'), findsOneWidget);
    });
  }

  test('rotuloEixoReais', () {
    expect(rotuloEixoReais(0), '0');
    expect(rotuloEixoReais(50), '50');
    expect(rotuloEixoReais(250), '250');
    expect(rotuloEixoReais(-300), '-300');
    expect(rotuloEixoReais(1000), '1 mil');
    expect(rotuloEixoReais(1500), '1,5 mil');
    expect(rotuloEixoReais(1250), '1,25 mil');
    expect(rotuloEixoReais(12000), '12 mil');
  });

  MesSerie mes(int i, int v, int s, int p) => MesSerie(
      ano: 2026, mes: i + 1, vendasCentavos: v, saidasCentavos: s, pedidos: p);
  final casos = <String, List<MesSerie>>{
    'sem nenhum dado': [for (var i = 0; i < 12; i++) mes(i, 0, 0, 0)],
    'só saídas': [for (var i = 0; i < 12; i++) mes(i, 0, 5000 * (i + 1), 0)],
    'só resultados negativos': [
      for (var i = 0; i < 12; i++) mes(i, 1000, 30000 + i * 100, 1)
    ],
    'resultado minúsculo': [for (var i = 0; i < 12; i++) mes(i, 100, 0, 1)],
  };
  for (final e in casos.entries) {
    for (final w in [360.0, 1000.0]) {
      testWidgets('${e.key} em ${w.toInt()} px sem exceção', (t) async {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: w,
                child: Column(children: [
                  CurvaResultado(serie: e.value),
                  BarrasVendasSaidas(serie: e.value),
                ]),
              ),
            ),
          ),
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
