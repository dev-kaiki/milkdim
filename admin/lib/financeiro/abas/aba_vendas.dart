// lib/financeiro/abas/aba_vendas.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../resumo_financeiro.dart';
import 'barras_horizontais.dart';

class AbaVendas extends StatelessWidget {
  final ResumoMes resumo;
  final List<LinhaValor> clientes;

  const AbaVendas({super.key, required this.resumo, required this.clientes});

  Widget _secao(BuildContext context, String titulo, List<LinhaValor> linhas,
      {String Function(LinhaValor)? detalhe}) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MdSectionHeader(titulo: titulo),
        if (linhas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
            child: Text('Sem registros no mês.',
                style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          )
        else
          BarrasHorizontais(
            linhas: linhas,
            cor: MdColors.primary,
            detalhe: detalhe,
            totalCentavos: resumo.vendasCentavos,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const sep = SizedBox(height: MdSpace.lg);
    return ListView(
      padding: const EdgeInsets.only(top: MdSpace.md, bottom: MdSpace.lg),
      children: [
        _secao(context, 'Melhores clientes', clientes,
            detalhe: (l) =>
                '${l.quantidade} ${l.quantidade == 1 ? 'pedido' : 'pedidos'}'),
        sep,
        _secao(context, 'Vendas por produto', resumo.porProduto,
            detalhe: (l) => '${l.quantidade} un'),
        sep,
        _secao(context, 'Vendas por vendedor', resumo.porVendedor),
      ],
    );
  }
}
