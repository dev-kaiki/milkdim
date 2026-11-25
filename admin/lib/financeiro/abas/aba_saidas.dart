// lib/financeiro/abas/aba_saidas.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../modelos_financeiro.dart';
import '../resumo_financeiro.dart';
import 'barras_horizontais.dart';

String _dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class AbaSaidas extends StatelessWidget {
  final ResumoMes resumo;
  final List<Saida> saidasDoMes;
  final Map<int, String> nomesCategorias;
  final VoidCallback onLancar;
  final VoidCallback onCategorias;
  final void Function(Saida) onEditar;
  final void Function(Saida) onApagar;

  const AbaSaidas({
    super.key,
    required this.resumo,
    required this.saidasDoMes,
    required this.nomesCategorias,
    required this.onLancar,
    required this.onCategorias,
    required this.onEditar,
    required this.onApagar,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(top: MdSpace.md, bottom: MdSpace.lg),
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MdSpace.xs,
          children: [
            IconButton(
              tooltip: 'Categorias',
              onPressed: onCategorias,
              icon: const Icon(Icons.category_outlined),
            ),
            FilledButton.icon(
              onPressed: onLancar,
              icon: const Icon(Icons.add),
              label: const Text('Lançar saída'),
            ),
          ],
        ),
        const MdSectionHeader(titulo: 'Saídas por categoria'),
        if (resumo.porCategoria.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
            child: Text('Sem registros no mês.',
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          )
        else
          BarrasHorizontais(
            linhas: resumo.porCategoria,
            cor: MdColors.textMuted,
            totalCentavos: resumo.saidasCentavos,
          ),
        const SizedBox(height: MdSpace.lg),
        const MdSectionHeader(titulo: 'Saídas do mês'),
        if (saidasDoMes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
            child: Text('Nenhuma saída lançada neste mês.',
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          )
        else
          MdCard(
            padding: const EdgeInsets.symmetric(
                horizontal: MdSpace.lg, vertical: MdSpace.sm),
            child: Column(
              children: [
                for (var i = 0; i < saidasDoMes.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => onEditar(saidasDoMes[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    nomesCategorias[
                                            saidasDoMes[i].categoriaId] ??
                                        'Sem categoria',
                                    style: tt.bodyLarge),
                                Text(_dataBr(saidasDoMes[i].data),
                                    style: tt.bodySmall!
                                        .copyWith(color: MdColors.textMuted)),
                                if (saidasDoMes[i].descricao.trim().isNotEmpty)
                                  Text(saidasDoMes[i].descricao.trim(),
                                      style: tt.bodyMedium!
                                          .copyWith(color: MdColors.textMuted)),
                              ],
                            ),
                          ),
                          Text(fmtCentavos(saidasDoMes[i].valorCentavos),
                              style: tt.bodyLarge),
                          IconButton(
                            tooltip: 'Apagar saída',
                            onPressed: () => onApagar(saidasDoMes[i]),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
