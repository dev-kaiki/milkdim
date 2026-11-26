// lib/financeiro/abas/aba_resumo.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../modelos_financeiro.dart';
import '../painel_financeiro.dart';
import '../resumo_financeiro.dart';
import 'graficos_financeiro.dart';

Color _corVariacao(Variacao v, BuildContext context) => switch (v.sentido) {
      1 => MdColors.success,
      -1 => Theme.of(context).colorScheme.error,
      _ => MdColors.textMuted,
    };

String _textoVariacao(Variacao v) {
  if (v.texto != null) return v.texto!;
  final pct = v.pct ?? 0;
  if (pct > 0) return '▲ $pct%';
  if (pct < 0) return '▼ ${-pct}%';
  return '= 0%';
}

class AbaResumo extends StatelessWidget {
  final ResumoMes resumo;
  final ComparacaoMes comparacao;
  final List<MesSerie> serie;
  final bool mesAtual;

  const AbaResumo({
    super.key,
    required this.resumo,
    required this.comparacao,
    required this.serie,
    required this.mesAtual,
  });

  Widget _numero(BuildContext context, String rotulo, String valor,
      {Color? cor, String? extra, Variacao? variacao}) {
    final tt = Theme.of(context).textTheme;
    return MdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo,
              style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          const SizedBox(height: MdSpace.xs),
          Text(valor, style: tt.titleLarge!.copyWith(color: cor)),
          if (extra != null)
            Text(extra,
                style: tt.bodySmall!.copyWith(color: MdColors.textMuted)),
          if (variacao != null)
            Text(_textoVariacao(variacao),
                style: tt.bodyMedium!
                    .copyWith(color: _corVariacao(variacao, context))),
        ],
      ),
    );
  }

  Widget _destaque(BuildContext context, String titulo, String? nome,
      String? detalhe) {
    final tt = Theme.of(context).textTheme;
    return MdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          const SizedBox(height: MdSpace.xs),
          Text(nome ?? '—', style: tt.titleMedium),
          if (nome != null && detalhe != null)
            Text(detalhe,
                style: tt.bodySmall!.copyWith(color: MdColors.textMuted)),
        ],
      ),
    );
  }

  Widget _grade(List<Widget> cards, double largura) {
    if (largura < 560) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: MdSpace.md),
            cards[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: MdSpace.md),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final r = resumo;
    final ticket = r.pedidos > 0
        ? fmtCentavos((r.vendasCentavos / r.pedidos).round())
        : '—';
    final margem = pctDe(r.resultadoCentavos, r.vendasCentavos);
    final produto = r.porProduto.isEmpty ? null : r.porProduto.first;
    final vendedor = r.porVendedor.isEmpty ? null : r.porVendedor.first;
    final gasto = r.porCategoria.isEmpty ? null : r.porCategoria.first;
    String pctTxt(int parte, int total, String de) {
      final p = pctDe(parte, total);
      return p == null ? '' : '$p% $de';
    }

    return LayoutBuilder(builder: (context, c) {
      final l = c.maxWidth;
      const sep = SizedBox(height: MdSpace.lg);
      return ListView(
        padding: const EdgeInsets.only(top: MdSpace.md, bottom: MdSpace.lg),
        children: [
          _grade([
            _numero(context, 'Vendas', fmtCentavos(r.vendasCentavos),
                extra:
                    '${r.pedidos} ${r.pedidos == 1 ? 'pedido' : 'pedidos'} · ticket médio $ticket',
                variacao: comparacao.vendas),
            _numero(context, 'Saídas', fmtCentavos(r.saidasCentavos),
                variacao: comparacao.saidas),
            _numero(context, 'Resultado do mês',
                fmtCentavos(r.resultadoCentavos),
                cor: r.resultadoCentavos < 0
                    ? Theme.of(context).colorScheme.error
                    : null,
                extra: 'margem ${margem == null ? '—' : '$margem%'}',
                variacao: comparacao.resultado),
          ], l),
          sep,
          MdCard(
            key: const ValueKey('curva-resultado'),
            child: CurvaResultado(serie: serie),
          ),
          sep,
          const MdSectionHeader(titulo: 'Destaques do mês'),
          _grade([
            _destaque(
                context,
                'Produto campeão',
                produto?.rotulo,
                produto == null
                    ? null
                    : '${produto.quantidade} un · ${pctTxt(produto.centavos, r.vendasCentavos, 'das vendas')}'),
            _destaque(
                context,
                'Vendedor do mês',
                vendedor?.rotulo,
                vendedor == null
                    ? null
                    : pctTxt(vendedor.centavos, r.vendasCentavos, 'das vendas')),
            _destaque(
                context,
                'Maior gasto',
                gasto?.rotulo,
                gasto == null
                    ? null
                    : pctTxt(gasto.centavos, r.saidasCentavos, 'das saídas')),
          ], l),
          if (mesAtual) ...[
            sep,
            const MdSectionHeader(titulo: 'A receber'),
            MdCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.aReceberPedidos} ${r.aReceberPedidos == 1 ? 'pedido pronto' : 'pedidos prontos'}, ainda não entregues',
                      style: tt.bodyLarge,
                    ),
                  ),
                  Text(fmtCentavos(r.aReceberCentavos), style: tt.titleMedium),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}
