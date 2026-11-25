// lib/financeiro/abas/aba_ano.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../modelos_financeiro.dart';
import '../painel_financeiro.dart';
import 'graficos_financeiro.dart';

/// Largura única das colunas de valor (Vendas, Saídas, Resultado).
const double _wValor = 120;

class AbaAno extends StatelessWidget {
  final List<MesSerie> serie;

  const AbaAno({super.key, required this.serie});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final erro = Theme.of(context).colorScheme.error;
    final comDado = serie.where((m) => m.temDado).toList();
    final vendas = comDado.fold<int>(0, (s, m) => s + m.vendasCentavos);
    final saidas = comDado.fold<int>(0, (s, m) => s + m.saidasCentavos);
    final pedidos = comDado.fold<int>(0, (s, m) => s + m.pedidos);
    final resultado = vendas - saidas;
    final margem = pctDe(resultado, vendas);

    Widget cel(String t, double w,
            {bool direita = true, TextStyle? estilo}) =>
        SizedBox(
          width: w,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: direita ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(t,
                maxLines: 1,
                softWrap: false,
                textAlign: direita ? TextAlign.right : TextAlign.left,
                style: estilo ?? tt.bodyMedium),
          ),
        );

    Widget linha(List<Widget> filhos) => Padding(
          padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
          child: Row(children: filhos),
        );

    final cab = tt.bodyMedium!.copyWith(fontWeight: FontWeight.w600);
    final mudo = tt.bodyMedium!.copyWith(color: MdColors.textMuted);
    TextStyle? corRes(int v) =>
        v < 0 ? tt.bodyMedium!.copyWith(color: erro) : null;

    final linhas = <Widget>[
      linha([
        cel('Mês', 80, direita: false, estilo: cab),
        cel('Vendas', _wValor, estilo: cab),
        cel('Saídas', _wValor, estilo: cab),
        cel('Resultado', _wValor, estilo: cab),
        cel('Margem', 70, estilo: cab),
        cel('Pedidos', 70, estilo: cab),
      ]),
      const Divider(height: 1),
      for (final m in serie) ...[
        if (m.temDado)
          linha([
            cel('${mesesAbrev[m.mes - 1]}/${m.ano % 100}', 80, direita: false),
            cel(fmtCentavos(m.vendasCentavos), _wValor),
            cel(fmtCentavos(m.saidasCentavos), _wValor),
            cel(fmtCentavos(m.resultadoCentavos), _wValor,
                estilo: corRes(m.resultadoCentavos)),
            cel(m.margemPct == null ? '—' : '${m.margemPct}%', 70),
            cel('${m.pedidos}', 70),
          ])
        else
          linha([
            cel('${mesesAbrev[m.mes - 1]}/${m.ano % 100}', 80,
                direita: false, estilo: mudo),
            for (final w in [_wValor, _wValor, _wValor, 70.0, 70.0])
              cel('—', w, estilo: mudo),
          ]),
        const Divider(height: 1),
      ],
      linha([
        cel('Total', 80, direita: false, estilo: cab),
        cel(fmtCentavos(vendas), _wValor, estilo: cab),
        cel(fmtCentavos(saidas), _wValor, estilo: cab),
        cel(fmtCentavos(resultado), _wValor,
            estilo: cab.copyWith(color: resultado < 0 ? erro : null)),
        cel(margem == null ? '—' : '$margem%', 70, estilo: cab),
        cel('$pedidos', 70, estilo: cab),
      ]),
    ];

    return ListView(
      padding: const EdgeInsets.only(top: MdSpace.md, bottom: MdSpace.lg),
      children: [
        MdCard(
          key: const ValueKey('grafico-ano'),
          child: BarrasVendasSaidas(serie: serie),
        ),
        const SizedBox(height: MdSpace.lg),
        MdCard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: linhas),
          ),
        ),
      ],
    );
  }
}
