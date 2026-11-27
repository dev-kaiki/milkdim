// lib/widgets/pedidos_anteriores.dart
//
// Quadro "Partir de um pedido anterior": lista os últimos pedidos do cliente
// com um botão "Usar" em cada um.
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/moeda.dart';
import '../utils/repetir_pedido.dart';

class QuadroPedidosAnteriores extends StatelessWidget {
  final List<Map<String, dynamic>> pedidos;
  final void Function(Map<String, dynamic> pedido) onUsar;

  const QuadroPedidosAnteriores({super.key, required this.pedidos, required this.onUsar});

  /// `dd/MM` na hora local, ou "—" se a data não puder ser lida.
  static String _data(Object? datahora) {
    final d = DateTime.tryParse((datahora ?? '').toString())?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// Total do pedido (número ou texto), ou "—" se faltar.
  static String _total(Object? total) {
    final n = total is num ? total : num.tryParse((total ?? '').toString().trim());
    return n == null ? '—' : formatarReais(n);
  }

  @override
  Widget build(BuildContext context) {
    if (pedidos.isEmpty) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MdSpace.xl),
        const MdSectionHeader(titulo: 'Partir de um pedido anterior'),
        MdCard(
          child: Column(
            children: [
              for (final p in pedidos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MdSpace.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_data(p['datahora'])}  ·  ${_total(p['total'])}',
                                style: tt.titleSmall),
                            Text(resumoItens(p['produtos']), style: tt.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: MdSpace.md),
                      OutlinedButton(onPressed: () => onUsar(p), child: const Text('Usar')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
