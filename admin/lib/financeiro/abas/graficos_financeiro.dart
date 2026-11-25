// lib/financeiro/abas/graficos_financeiro.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../modelos_financeiro.dart';
import '../painel_financeiro.dart';

const Color _corMarca = MdColors.primary;
const Color _corSaidas = Color(0xFFA8A29A);

/// Pontos da curva do resultado: x = índice do mês, y = resultado em reais.
/// Mês sem dado vira [FlSpot.nullSpot] (buraco na linha).
List<FlSpot> pontosResultado(List<MesSerie> serie) => [
      for (var i = 0; i < serie.length; i++)
        serie[i].temDado
            ? FlSpot(i.toDouble(), serie[i].resultadoCentavos / 100)
            : FlSpot.nullSpot,
    ];

String _rotuloMes(List<MesSerie> serie, int i) =>
    i >= 0 && i < serie.length ? mesesAbrev[serie[i].mes - 1] : '';

/// Rótulo compacto do eixo: reais inteiros abaixo de 1000, "N mil" a partir daí.
String rotuloEixoReais(double reais) {
  if (reais.abs() < 1000) return reais.round().toString();
  var t = (reais / 1000).toStringAsFixed(2);
  if (t.contains('.')) {
    t = t.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return '${t.replaceAll('.', ',')} mil';
}

String _reais(double v) => fmtCentavos((v * 100).round());

FlTitlesData _titulos(List<MesSerie> serie, BuildContext context) {
  final estilo = Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(color: MdColors.textMuted, fontSize: 10);
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 22,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(_rotuloMes(serie, v.round()), style: estilo),
        ),
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        getTitlesWidget: (v, meta) {
          if (v == meta.min || v == meta.max) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(rotuloEixoReais(v), style: estilo),
          );
        },
      ),
    ),
  );
}

FlLine _linhaGrade(double _) =>
    const FlLine(color: MdColors.border, strokeWidth: 1);

const FlGridData _grade = FlGridData(
  show: true,
  drawVerticalLine: false,
  getDrawingHorizontalLine: _linhaGrade,
);

class CurvaResultado extends StatelessWidget {
  final List<MesSerie> serie;
  const CurvaResultado({super.key, required this.serie});

  @override
  Widget build(BuildContext context) {
    final pontos = pontosResultado(serie);
    final ys = pontos.where((p) => !p.isNull()).map((p) => p.y);
    var minY = ys.isEmpty ? 0.0 : ys.reduce((a, b) => a < b ? a : b);
    var maxY = ys.isEmpty ? 0.0 : ys.reduce((a, b) => a > b ? a : b);
    if (minY > 0) minY = 0;
    if (maxY < 0) maxY = 0;
    if (maxY - minY < 100) maxY = minY + 100;
    final folga = (maxY - minY) * 0.1;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Resultado nos últimos 12 meses',
            style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
        const SizedBox(height: MdSpace.md),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (serie.length - 1).toDouble().clamp(1, 1000),
              minY: minY - folga,
              maxY: maxY + folga,
              gridData: _grade,
              borderData: FlBorderData(show: false),
              titlesData: _titulos(serie, context),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                    y: 0, color: MdColors.textMuted, strokeWidth: 1.5),
              ]),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${_rotuloMes(serie, s.x.round())}: ${_reais(s.y)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: pontos,
                  color: _corMarca,
                  barWidth: 3,
                  isCurved: false,
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BarrasVendasSaidas extends StatelessWidget {
  final List<MesSerie> serie;
  const BarrasVendasSaidas({super.key, required this.serie});

  Widget _legenda(BuildContext context, Color cor, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: cor),
        const SizedBox(width: MdSpace.xs),
        Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var maxY = 0.0;
    for (final m in serie.where((m) => m.temDado)) {
      final v = (m.vendasCentavos > m.saidasCentavos
              ? m.vendasCentavos
              : m.saidasCentavos) /
          100;
      if (v > maxY) maxY = v;
    }
    if (maxY < 100) maxY = 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _legenda(context, _corMarca, 'Vendas'),
          const SizedBox(width: MdSpace.md),
          _legenda(context, _corSaidas, 'Saídas'),
        ]),
        const SizedBox(height: MdSpace.md),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY * 1.1,
              gridData: _grade,
              borderData: FlBorderData(show: false),
              titlesData: _titulos(serie, context),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${_rotuloMes(serie, group.x)}\n${ri == 0 ? 'Vendas' : 'Saídas'}: ${_reais(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < serie.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: serie[i].temDado
                        ? [
                            BarChartRodData(
                              toY: serie[i].vendasCentavos / 100,
                              color: _corMarca,
                              width: 6,
                              borderRadius: BorderRadius.zero,
                            ),
                            BarChartRodData(
                              toY: serie[i].saidasCentavos / 100,
                              color: _corSaidas,
                              width: 6,
                              borderRadius: BorderRadius.zero,
                            ),
                          ]
                        : const [],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
