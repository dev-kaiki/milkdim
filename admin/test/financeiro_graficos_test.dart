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
}
