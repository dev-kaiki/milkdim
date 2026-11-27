// lib/pages/minhas_vendas_page.dart
//
// "Minhas vendas": quanto o vendedor vendeu no mês (pedidos entregues), com
// comparação com o mês anterior, o que falta entregar, vendas por produto e os
// melhores clientes. Só leitura, com os pedidos que já estão no aparelho.
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/db.dart';
import '../utils/minhas_vendas.dart';
import '../utils/moeda.dart';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// Nome do mês em minúsculas (1 a 12), sem depender de locale.
String nomeDoMes(int mes) => _meses[mes - 1];

/// Subtítulo do item da tela inicial.
String subtituloVendas(double? vendido, int mes) => vendido == null
    ? 'Quanto você vendeu no mês'
    : '${formatarReais(vendido)} em ${nomeDoMes(mes)}';

class MinhasVendasPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Para teste: relógio e fonte dos pedidos.
  final DateTime Function()? relogio;
  final Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)? carregarPedidos;

  const MinhasVendasPage({
    super.key,
    required this.vendedor,
    this.relogio,
    this.carregarPedidos,
  });

  @override
  State<MinhasVendasPage> createState() => _MinhasVendasPageState();
}

class _MinhasVendasPageState extends State<MinhasVendasPage> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  bool _erro = false;
  late int _ano;
  late int _mes;

  String get _codigo => widget.vendedor['codigo']?.toString() ?? '';
  DateTime get _agora => (widget.relogio ?? DateTime.now)();
  bool get _mesAtual => _ano == _agora.year && _mes == _agora.month;

  @override
  void initState() {
    super.initState();
    _ano = _agora.year;
    _mes = _agora.month;
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final pedidos = await (widget.carregarPedidos ?? listarPedidosParaVendas)(_codigo);
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _carregando = false;
        _erro = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar vendas: $e');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = true;
        });
      }
    }
  }

  void _mover(int delta) {
    var m = _mes + delta;
    var a = _ano;
    if (m < 1) {
      m = 12;
      a--;
    } else if (m > 12) {
      m = 1;
      a++;
    }
    // Não avança além do mês atual.
    if (a > _agora.year || (a == _agora.year && m > _agora.month)) return;
    setState(() {
      _ano = a;
      _mes = m;
    });
  }

  ResumoVendas _resumo(int ano, int mes, {DateTime? ate}) =>
      resumoDoMes(_pedidos, vendedorCodigo: _codigo, ano: ano, mes: mes, ate: ate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas vendas')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro
                ? const MdEmptyState(
                    icone: Icons.error_outline,
                    titulo: 'Não foi possível carregar as vendas.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(MdSpace.lg),
                    children: [MdContentWidth(maxWidth: 640, child: _conteudo())],
                  ),
      ),
    );
  }

  Widget _conteudo() {
    final r = _resumo(_ano, _mes);
    // Mês atual: compara com o mesmo trecho do mês anterior (até o mesmo dia e
    // hora); mês encerrado: mês inteiro contra mês inteiro.
    final anterior = _resumo(
      _mes == 1 ? _ano - 1 : _ano,
      _mes == 1 ? 12 : _mes - 1,
      ate: _mesAtual ? limiteMesAnterior(_agora) : null,
    );
    final tt = Theme.of(context).textTheme;
    final semVenda = r.pedidos == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navegacaoMes(tt),
        const SizedBox(height: MdSpace.md),
        _numero(
          'Vendido',
          formatarReais(r.vendido),
          textoVariacao(r.vendido, anterior.vendido),
        ),
        const SizedBox(height: MdSpace.md),
        _numero(
          'Pedidos entregues',
          '${r.pedidos}',
          textoVariacao(r.pedidos.toDouble(), anterior.pedidos.toDouble()),
        ),
        const SizedBox(height: MdSpace.md),
        _numero(
          'Ticket médio',
          r.ticketMedio == null ? '—' : formatarReais(r.ticketMedio!),
          r.ticketMedio == null || anterior.ticketMedio == null
              ? null
              : textoVariacao(r.ticketMedio!, anterior.ticketMedio!),
        ),
        if (_mesAtual) ...[
          const SizedBox(height: MdSpace.lg),
          const MdSectionHeader(titulo: 'A entregar'),
          MdCard(
            child: Text(
              '${formatarReais(r.aEntregarValor)} · '
              '${r.aEntregarPedidos == 1 ? '1 pedido' : '${r.aEntregarPedidos} pedidos'}',
              style: tt.bodyLarge,
            ),
          ),
        ],
        if (_mesAtual && r.aguardandoEnvioPedidos > 0) ...[
          const SizedBox(height: MdSpace.md),
          MdBanner(
            tipo: MdTipo.info,
            icone: Icons.cloud_upload_outlined,
            texto: 'Entregues sem internet: '
                '${r.aguardandoEnvioPedidos == 1 ? '1 pedido' : '${r.aguardandoEnvioPedidos} pedidos'}'
                ' · ${formatarReais(r.aguardandoEnvioValor)}'
                ' — entram nas vendas quando forem enviados',
          ),
        ],
        if (semVenda) ...[
          const SizedBox(height: MdSpace.lg),
          MdEmptyState(
            icone: Icons.insights_outlined,
            titulo: 'Nenhuma venda entregue em ${nomeDoMes(_mes)}.',
          ),
        ] else ...[
          const SizedBox(height: MdSpace.lg),
          const MdSectionHeader(titulo: 'Por produto'),
          MdCard(
            child: Column(
              children: [
                for (final p in r.porProduto)
                  _linha(tt, p.nome, '${p.unidades} un', formatarReais(p.valor)),
              ],
            ),
          ),
          const SizedBox(height: MdSpace.lg),
          const MdSectionHeader(titulo: 'Melhores clientes'),
          MdCard(
            child: Column(
              children: [
                for (final c in r.melhoresClientes)
                  _linha(tt, c.nome, c.pedidos == 1 ? '1 pedido' : '${c.pedidos} pedidos',
                      formatarReais(c.valor)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _navegacaoMes(TextTheme tt) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mês anterior',
          onPressed: () => _mover(-1),
        ),
        Expanded(
          child: Text(
            '${nomeDoMes(_mes)} de $_ano',
            style: tt.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Próximo mês',
          onPressed: _mesAtual ? null : () => _mover(1),
        ),
      ],
    );
  }

  Widget _numero(String rotulo, String valor, String? variacao) {
    final tt = Theme.of(context).textTheme;
    final cor = variacao == null
        ? MdColors.textMuted
        : variacao.startsWith('▲')
            ? MdColors.success
            : variacao.startsWith('▼')
                ? MdColors.danger
                : MdColors.textMuted;
    return MdCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
                Text(valor, style: tt.headlineSmall),
              ],
            ),
          ),
          if (variacao != null)
            Text(variacao, style: tt.titleMedium!.copyWith(color: cor)),
        ],
      ),
    );
  }

  Widget _linha(TextTheme tt, String nome, String detalhe, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MdSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome, style: tt.bodyLarge),
                Text(detalhe, style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
              ],
            ),
          ),
          Text(valor, style: tt.titleMedium),
        ],
      ),
    );
  }
}
