// lib/financeiro/abas/barras_horizontais.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../modelos_financeiro.dart';
import '../painel_financeiro.dart';
import '../resumo_financeiro.dart';

/// Lista de barras: largura proporcional ao maior valor. Mostra o rótulo, o
/// detalhe opcional (ex.: "201 un"), o R$ e, com [totalCentavos], o "N%".
class BarrasHorizontais extends StatelessWidget {
  final List<LinhaValor> linhas;
  final Color cor;
  final String Function(LinhaValor)? detalhe;
  final int? totalCentavos;

  const BarrasHorizontais({
    super.key,
    required this.linhas,
    required this.cor,
    this.detalhe,
    this.totalCentavos,
  });

  /// Segunda linha: detalhe (ex.: "201 un") e "N%" do total.
  String _sub(LinhaValor l) {
    final partes = <String>[
      if (detalhe != null) detalhe!(l),
      if (totalCentavos != null && pctDe(l.centavos, totalCentavos!) != null)
        '${pctDe(l.centavos, totalCentavos!)}%',
    ];
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final maior = linhas.fold<int>(0, (m, l) => l.centavos > m ? l.centavos : m);
    return MdCard(
      padding: const EdgeInsets.symmetric(
          horizontal: MdSpace.lg, vertical: MdSpace.sm),
      child: Column(
        children: [
          for (var i = 0; i < linhas.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          linhas[i].rotulo.isEmpty ? '—' : linhas[i].rotulo,
                          style: tt.bodyLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: MdSpace.md),
                      Text(fmtCentavos(linhas[i].centavos), style: tt.bodyLarge),
                    ],
                  ),
                  if (_sub(linhas[i]).isNotEmpty)
                    Text(_sub(linhas[i]),
                        style: tt.bodySmall!.copyWith(color: MdColors.textMuted)),
                  const SizedBox(height: MdSpace.xs),
                  LayoutBuilder(builder: (context, c) {
                    final f = maior == 0
                        ? 0.0
                        : (linhas[i].centavos / maior).clamp(0.0, 1.0);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        key: ValueKey('barra-$i'),
                        height: 8,
                        width: c.maxWidth * f,
                        decoration: BoxDecoration(
                          color: cor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
