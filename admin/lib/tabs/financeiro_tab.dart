// lib/tabs/financeiro_tab.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../financeiro/abas/aba_ano.dart';
import '../financeiro/abas/aba_resumo.dart';
import '../financeiro/abas/aba_saidas.dart';
import '../financeiro/abas/aba_vendas.dart';
import '../financeiro/dialogo_categorias.dart';
import '../financeiro/dialogo_saida.dart';
import '../financeiro/modelos_financeiro.dart';
import '../financeiro/painel_financeiro.dart';
import '../financeiro/relatorio_mes.dart';
import '../financeiro/resumo_financeiro.dart';
import '../models/pedido.dart';
import '../services/financeiro_service.dart';
import '../services/supabase_service.dart';

String _dataBr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Financeiro: resumo do mês (vendas, saídas, resultado), quadros por
/// vendedor/produto/categoria, "A receber" (só no mês atual) e as saídas.
class FinanceiroTab extends StatefulWidget {
  /// Nulo usa o [FinanceiroService].
  final FonteFinanceiro? fonte;

  /// Relógio; nulo usa [DateTime.now].
  final DateTime Function()? agora;

  /// Fica verdadeiro quando a aba passa a ser a selecionada; a cada abertura
  /// o mês é recarregado. Nulo: só carrega ao montar.
  final ValueListenable<bool>? aberta;

  /// Entrega o PDF do relatório (bytes e nome do arquivo). Nulo abre o
  /// diálogo de impressão do sistema.
  final Future<void> Function(Uint8List pdf, String nome)? imprimirRelatorio;

  const FinanceiroTab({
    super.key,
    this.fonte,
    this.agora,
    this.aberta,
    this.imprimirRelatorio,
  });

  @override
  State<FinanceiroTab> createState() => _FinanceiroTabState();
}

class _FinanceiroTabState extends State<FinanceiroTab>
    with SingleTickerProviderStateMixin {
  late final TabController _abas = TabController(length: 4, vsync: this);
  late final FonteFinanceiro _fonte = widget.fonte ?? FinanceiroService();
  late int _ano;
  late int _mes;

  bool _carregando = true;
  String? _erro;
  ResumoMes? _resumo;
  ComparacaoMes _comparacao = const ComparacaoMes();
  List<MesSerie> _serie = [];
  List<LinhaValor> _clientes = [];
  List<Saida> _saidas = [];
  List<Pedido> _entregues = [];
  bool _gerandoRelatorio = false;
  Map<int, String> _nomes = {};
  int _geracao = 0;

  /// Calculado uma vez por carga: o mês na tela era o mês real?
  bool _mesAtual = false;

  /// Mês real (ano, mês) no momento da última carga iniciada.
  late int _anoReal;
  late int _mesReal;

  DateTime _agora() => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final n = _agora();
    _ano = n.year;
    _mes = n.month;
    _anoReal = n.year;
    _mesReal = n.month;
    _ultimaAberta = widget.aberta?.value ?? true;
    widget.aberta?.addListener(_aoMudarAberta);
    _carregar();
  }

  late bool _ultimaAberta;

  @override
  void didUpdateWidget(FinanceiroTab old) {
    super.didUpdateWidget(old);
    if (old.aberta != widget.aberta) {
      old.aberta?.removeListener(_aoMudarAberta);
      widget.aberta?.addListener(_aoMudarAberta);
      _ultimaAberta = widget.aberta?.value ?? true;
    }
  }

  @override
  void dispose() {
    widget.aberta?.removeListener(_aoMudarAberta);
    _abas.dispose();
    super.dispose();
  }

  void _aoMudarAberta() {
    final v = widget.aberta!.value;
    final abriu = v && !_ultimaAberta;
    _ultimaAberta = v;
    if (abriu) _atualizarAoAbrir();
  }

  /// Ao abrir a aba: se virou o mês e a pessoa olhava o "mês atual" de antes,
  /// vai para o novo mês atual; depois recarrega.
  void _atualizarAoAbrir() {
    if (!mounted) return;
    final n = _agora();
    if ((n.year != _anoReal || n.month != _mesReal) &&
        _ano == _anoReal &&
        _mes == _mesReal) {
      _ano = n.year;
      _mes = n.month;
    }
    _carregar();
  }

  bool get _mostraAviso => avisoHistoricoAte(_ano, _mes);

  Future<void> _carregar() async {
    final minha = ++_geracao;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final iv = intervaloDoMes(_ano, _mes);
      final n = _agora();
      _anoReal = n.year;
      _mesReal = n.month;
      final atual = n.year == _ano && n.month == _mes;
      // 12 meses terminando no mês escolhido; o mês é filtrado em memória.
      final ini12 = DateTime(_ano, _mes - 11, 1);
      final entregues12 = await _fonte.pedidosEntregues(ini12, iv.fim);
      final prontos = atual ? await _fonte.pedidosProntos() : <Pedido>[];
      final saidas12 = await _fonte.saidasEntre(ini12, iv.fim);
      final cats = await _fonte.categorias();
      if (!mounted || minha != _geracao) return;
      // Todas as categorias (ativas e inativas): saída antiga mantém o nome.
      final nomes = {for (final c in cats) c.id: c.nome};
      final entregues = [
        for (final p in entregues12)
          if (p.finalizadoEm != null &&
              !p.finalizadoEm!.toLocal().isBefore(iv.inicio) &&
              p.finalizadoEm!.toLocal().isBefore(iv.fim))
            p,
      ];
      final saidas = [
        for (final s in saidas12)
          if (!s.data.isBefore(iv.inicio) && s.data.isBefore(iv.fim)) s,
      ];
      setState(() {
        _mesAtual = atual;
        _nomes = nomes;
        _saidas = saidas;
        _entregues = entregues;
        _resumo = resumirMes(
          entregues: entregues,
          prontos: prontos,
          saidas: saidas,
          nomesCategorias: nomes,
        );
        _comparacao = compararMes(
          ano: _ano,
          mes: _mes,
          agora: n,
          entregues: entregues12,
          saidas: saidas12,
        );
        _serie = serieDozeMeses(
          ano: _ano,
          mes: _mes,
          entregues: entregues12,
          saidas: saidas12,
        );
        _clientes = melhoresClientes(entregues);
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

  Future<void> _imprimirPadrao(Uint8List pdf, String nome) =>
      Printing.layoutPdf(
        name: nome,
        format: PdfPageFormat.a4,
        onLayout: (_) async => pdf,
      );

  /// Monta o PDF do mês na tela e o entrega à impressão. A trava impede dois
  /// cliques seguidos.
  Future<void> _gerarRelatorio() async {
    final resumo = _resumo;
    if (_gerandoRelatorio || _carregando || _erro != null || resumo == null) {
      return;
    }
    // O mês pode mudar enquanto o PDF é gerado: tudo vem do que estava na tela.
    final ano = _ano, mes = _mes;
    setState(() => _gerandoRelatorio = true);
    try {
      final r = montarRelatorio(
        ano: ano,
        mes: mes,
        geradoEm: _agora(),
        mesAtual: _mesAtual,
        resumo: resumo,
        comparacao: _comparacao,
        saidas: _saidas,
        nomesCategorias: _nomes,
        entregues: _entregues,
      );
      final pdf = await pdfDoRelatorio(r);
      await (widget.imprimirRelatorio ?? _imprimirPadrao)(
          pdf, nomeArquivoRelatorio(ano, mes));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível gerar o relatório.')));
      }
    } finally {
      if (mounted) setState(() => _gerandoRelatorio = false);
    }
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
    if (!mounted) return;
    var msg = editar == null
        ? 'Saída lançada em ${_dataBr(s.data)}.'
        : 'Saída alterada.';
    if (s.data.year != _ano || s.data.month != _mes) {
      msg += ' Ela aparece em ${nomesMeses[s.data.month - 1]} ${s.data.year}.';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _carregar();
  }

  Future<void> _apagarSaida(Saida s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar esta saída?'),
        content: Text(
            '${_nomes[s.categoriaId] ?? 'Sem categoria'} · ${_dataBr(s.data)} · ${fmtCentavos(s.valorCentavos)}'),
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
                child: Text('${nomesMeses[_mes - 1]} $_ano',
                    style: tt.titleLarge),
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
            OutlinedButton.icon(
              onPressed: (_carregando || _erro != null || _gerandoRelatorio)
                  ? null
                  : _gerarRelatorio,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Relatório (PDF)'),
            ),
            IconButton(
              tooltip: 'Atualizar',
              onPressed: _carregando ? null : _carregar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }

  /// Conteúdo de uma aba: carregando, erro (igual em todas) ou o [conteudo].
  Widget _aba(Widget Function(ResumoMes r) conteudo) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MdSpace.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erro != null) {
      return ListView(
        padding: const EdgeInsets.only(top: MdSpace.md),
        children: [
          MdBanner(tipo: MdTipo.erro, texto: _erro!),
          const SizedBox(height: MdSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ),
        ],
      );
    }
    return conteudo(_resumo!);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MdSpace.lg, MdSpace.sm, MdSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecalho(),
          if (_mostraAviso)
            Padding(
              padding: const EdgeInsets.only(top: MdSpace.xs),
              child: Text(textoAvisoHistorico,
                  style: tt.bodySmall!.copyWith(color: MdColors.textMuted)),
            ),
          const SizedBox(height: MdSpace.xs),
          TabBar(
            controller: _abas,
            tabs: const [
              Tab(text: 'Resumo'),
              Tab(text: 'Vendas'),
              Tab(text: 'Saídas'),
              Tab(text: 'Ano'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _abas,
              children: [
                _aba((r) => AbaResumo(
                      resumo: r,
                      comparacao: _comparacao,
                      serie: _serie,
                      mesAtual: _mesAtual,
                    )),
                _aba((r) => AbaVendas(resumo: r, clientes: _clientes)),
                _aba((r) => AbaSaidas(
                      resumo: r,
                      saidasDoMes: _saidas,
                      nomesCategorias: _nomes,
                      onLancar: _lancarSaida,
                      onCategorias: _gerenciarCategorias,
                      onEditar: _abrirDialogoSaida,
                      onApagar: _apagarSaida,
                    )),
                _aba((r) => AbaAno(serie: _serie)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
