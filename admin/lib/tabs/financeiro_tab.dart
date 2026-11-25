// lib/tabs/financeiro_tab.dart
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../financeiro/dialogo_categorias.dart';
import '../financeiro/dialogo_saida.dart';
import '../financeiro/modelos_financeiro.dart';
import '../financeiro/resumo_financeiro.dart';
import '../models/pedido.dart';
import '../services/financeiro_service.dart';
import '../services/supabase_service.dart';

const List<String> _meses = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// Até novembro de 2026 (inclusive) a venda conta pela data do pedido.
const int _anoHistorico = 2026;
const int _mesHistorico = 11;
const String _avisoHistorico = 'Até 23/11/2026, a data é a do pedido.';

String _dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Financeiro: resumo do mês (vendas, saídas, resultado), quadros por
/// vendedor/produto/categoria, "A receber" (só no mês atual) e as saídas.
class FinanceiroTab extends StatefulWidget {
  /// Nulo usa o [FinanceiroService].
  final FonteFinanceiro? fonte;

  /// Relógio; nulo usa [DateTime.now].
  final DateTime Function()? agora;

  const FinanceiroTab({super.key, this.fonte, this.agora});

  @override
  State<FinanceiroTab> createState() => _FinanceiroTabState();
}

class _FinanceiroTabState extends State<FinanceiroTab> {
  late final FonteFinanceiro _fonte = widget.fonte ?? FinanceiroService();
  late int _ano;
  late int _mes;

  bool _carregando = true;
  String? _erro;
  ResumoMes? _resumo;
  List<Saida> _saidas = [];
  Map<int, String> _nomes = {};
  int _geracao = 0;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final n = _agora();
    _ano = n.year;
    _mes = n.month;
    _carregar();
  }

  bool get _mesAtual {
    final n = _agora();
    return n.year == _ano && n.month == _mes;
  }

  bool get _mostraAviso =>
      _ano < _anoHistorico || (_ano == _anoHistorico && _mes <= _mesHistorico);

  Future<void> _carregar() async {
    final minha = ++_geracao;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final iv = intervaloDoMes(_ano, _mes);
      final atual = _mesAtual;
      final entregues = await _fonte.pedidosEntregues(iv.inicio, iv.fim);
      final prontos = atual ? await _fonte.pedidosProntos() : <Pedido>[];
      final saidas = await _fonte.saidasEntre(iv.inicio, iv.fim);
      final cats = await _fonte.categorias();
      if (!mounted || minha != _geracao) return;
      // Todas as categorias (ativas e inativas): saída antiga mantém o nome.
      final nomes = {for (final c in cats) c.id: c.nome};
      setState(() {
        _nomes = nomes;
        _saidas = saidas;
        _resumo = resumirMes(
          entregues: entregues,
          prontos: prontos,
          saidas: saidas,
          nomesCategorias: nomes,
        );
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || minha != _geracao) return;
      setState(() {
        _erro =
            e is RepoFailure ? e.message : 'Erro ao carregar o financeiro: $e';
        _carregando = false;
      });
    }
  }

  void _mudarMes(int delta) {
    final d = DateTime(_ano, _mes + delta, 1);
    _ano = d.year;
    _mes = d.month;
    _carregar();
  }

  void _aviso(Object e) {
    if (!mounted) return;
    final msg = e is RepoFailure ? e.message : 'Erro: $e';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _lancarSaida() => _abrirDialogoSaida(null);

  Future<void> _abrirDialogoSaida(Saida? editar) async {
    final List<CategoriaSaida> cats;
    try {
      cats = await _fonte.categorias();
    } catch (e) {
      _aviso(e);
      return;
    }
    if (!mounted) return;
    final n = _agora();
    final s = await mostrarDialogoSaida(
      context,
      categorias: cats,
      editar: editar,
      hoje: DateTime(n.year, n.month, n.day),
    );
    if (s == null) return;
    try {
      if (editar == null) {
        await _fonte.inserirSaida(s);
      } else {
        await _fonte.alterarSaida(s);
      }
    } catch (e) {
      _aviso(e);
      return;
    }
    if (mounted) await _carregar();
  }

  Future<void> _apagarSaida(Saida s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar esta saída?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true || s.id == null) return;
    try {
      await _fonte.apagarSaida(s.id!);
    } catch (e) {
      _aviso(e);
      return;
    }
    if (mounted) await _carregar();
  }

  Future<void> _gerenciarCategorias() async {
    await mostrarDialogoCategorias(context, _fonte);
    if (mounted) await _carregar();
  }

  // -------------------- UI --------------------

  Widget _cabecalho() {
    final tt = Theme.of(context).textTheme;
    // Wrap: em tela estreita as ações descem para a linha de baixo.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: MdSpace.xs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => _mudarMes(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${_meses[_mes - 1]} $_ano', style: tt.titleLarge),
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: () => _mudarMes(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MdSpace.xs,
          children: [
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Categorias',
              onPressed: _gerenciarCategorias,
              icon: const Icon(Icons.category_outlined),
            ),
            FilledButton.icon(
              onPressed: _lancarSaida,
              icon: const Icon(Icons.add),
              label: const Text('Lançar saída'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numero(String rotulo, String valor, {Color? cor, String? extra}) {
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
        ],
      ),
    );
  }

  Widget _resumoTopo(ResumoMes r) {
    final negativo = r.resultadoCentavos < 0;
    final cards = [
      _numero('Vendas', fmtCentavos(r.vendasCentavos),
          extra: '(${r.pedidos} ${r.pedidos == 1 ? 'pedido' : 'pedidos'})'),
      _numero('Saídas', fmtCentavos(r.saidasCentavos)),
      _numero('Resultado do mês', fmtCentavos(r.resultadoCentavos),
          cor: negativo ? Theme.of(context).colorScheme.error : null),
    ];
    // Estreito (celular): um cartão embaixo do outro.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 560) {
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
    });
  }

  Widget _quadro(String titulo, List<LinhaValor> linhas,
      {bool comUnidades = false}) {
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
          MdCard(
            padding: const EdgeInsets.symmetric(
                horizontal: MdSpace.lg, vertical: MdSpace.sm),
            child: Column(
              children: [
                for (var i = 0; i < linhas.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: MdSpace.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              linhas[i].rotulo.isEmpty ? '—' : linhas[i].rotulo,
                              style: tt.bodyLarge),
                        ),
                        if (comUnidades) ...[
                          Text('${linhas[i].quantidade} un',
                              style: tt.bodyMedium!
                                  .copyWith(color: MdColors.textMuted)),
                          const SizedBox(width: MdSpace.md),
                        ],
                        Text(fmtCentavos(linhas[i].centavos),
                            style: tt.bodyLarge),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _aReceber(ResumoMes r) {
    final tt = Theme.of(context).textTheme;
    final n = r.aReceberPedidos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MdSectionHeader(titulo: 'A receber'),
        MdCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$n ${n == 1 ? 'pedido pronto' : 'pedidos prontos'}, ainda não entregues',
                  style: tt.bodyLarge,
                ),
              ),
              Text(fmtCentavos(r.aReceberCentavos), style: tt.titleMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _listaSaidas() {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MdSectionHeader(titulo: 'Saídas do mês'),
        if (_saidas.isEmpty)
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
                for (var i = 0; i < _saidas.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => _abrirDialogoSaida(_saidas[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: MdSpace.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _nomes[_saidas[i].categoriaId] ??
                                        'Sem categoria',
                                    style: tt.bodyLarge),
                                Text(_dataBr(_saidas[i].data),
                                    style: tt.bodySmall!
                                        .copyWith(color: MdColors.textMuted)),
                                if (_saidas[i].descricao.trim().isNotEmpty)
                                  Text(_saidas[i].descricao.trim(),
                                      style: tt.bodyMedium!
                                          .copyWith(color: MdColors.textMuted)),
                              ],
                            ),
                          ),
                          Text(fmtCentavos(_saidas[i].valorCentavos),
                              style: tt.bodyLarge),
                          IconButton(
                            tooltip: 'Apagar saída',
                            onPressed: () => _apagarSaida(_saidas[i]),
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

  Widget _corpo() {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MdSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erro != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MdBanner(tipo: MdTipo.erro, texto: _erro!),
          const SizedBox(height: MdSpace.md),
          OutlinedButton.icon(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ],
      );
    }
    final r = _resumo!;
    const sep = SizedBox(height: MdSpace.lg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _resumoTopo(r),
        sep,
        _quadro('Vendas por vendedor', r.porVendedor),
        sep,
        _quadro('Vendas por produto', r.porProduto, comUnidades: true),
        sep,
        _quadro('Saídas por categoria', r.porCategoria),
        if (_mesAtual) ...[sep, _aReceber(r)],
        sep,
        _listaSaidas(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          MdSpace.lg, MdSpace.sm, MdSpace.lg, MdSpace.lg),
      children: [
        _cabecalho(),
        if (_mostraAviso)
          Padding(
            padding: const EdgeInsets.only(top: MdSpace.xs),
            child: Text(_avisoHistorico,
                style: tt.bodySmall!.copyWith(color: MdColors.textMuted)),
          ),
        const SizedBox(height: MdSpace.md),
        _corpo(),
      ],
    );
  }
}
