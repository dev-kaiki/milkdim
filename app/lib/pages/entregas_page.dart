// lib/pages/entregas_page.dart
//
// Entregas do dia: pedidos prontos do vendedor, agrupados por cidade, com
// atalhos para o mapa, o aviso por WhatsApp e o "Registrar entrega". Esta
// tela não grava nada: a entrega é registrada na tela de edição do pedido.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/clientes_sumidos.dart';
import '../utils/db.dart';
import '../utils/entregas.dart';
import '../utils/moeda.dart';
import '../utils/repetir_pedido.dart';
import '../utils/supabase_helper.dart';
import 'pedido_edit_page.dart';

/// Subtítulo do item da tela inicial.
String subtituloEntregas(int? n) => n == null
    ? 'Pedidos prontos para entregar'
    : n == 1
        ? '1 pronto para entregar'
        : '$n prontos para entregar';

Future<void> _baixarDoSupabase(String vendedorCodigo) =>
    sincronizarPedidos(vendedorCodigo: vendedorCodigo);

class EntregasPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Para teste: baixar do servidor, ler o aparelho, abrir links e a tela
  /// de registrar entrega.
  final Future<void> Function(String vendedorCodigo)? baixarPedidos;
  final Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)?
      carregarPedidos;
  final Future<bool> Function(Uri)? abrirLink;
  final Widget Function(Map<String, dynamic> pedido)? paginaEntrega;

  const EntregasPage({
    super.key,
    required this.vendedor,
    this.baixarPedidos,
    this.carregarPedidos,
    this.abrirLink,
    this.paginaEntrega,
  });

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  bool _erro = false;
  bool _abrindo = false;

  String get _codigo => widget.vendedor['codigo']?.toString() ?? '';
  String get _nome => widget.vendedor['nome']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  /// Mostra logo o que está no aparelho e depois baixa do servidor. Sem
  /// conexão, a lista fica como está e nenhum erro aparece.
  Future<void> _abrir() async {
    await _carregar();
    if (!mounted || _erro || _codigo.isEmpty) return;
    try {
      await (widget.baixarPedidos ?? _baixarDoSupabase)(_codigo);
    } catch (e) {
      debugPrint('Entregas: não deu para baixar do servidor: $e');
      return;
    }
    if (mounted) await _carregar();
  }

  /// Puxar para atualizar: baixa do servidor e relê o aparelho. Sem conexão,
  /// só relê.
  Future<void> _atualizar() async {
    if (_codigo.isNotEmpty) {
      try {
        await (widget.baixarPedidos ?? _baixarDoSupabase)(_codigo);
      } catch (e) {
        debugPrint('Entregas: não deu para baixar do servidor: $e');
      }
    }
    if (mounted) await _carregar();
  }

  Future<void> _carregar() async {
    try {
      final pedidos =
          await (widget.carregarPedidos ?? listarPedidosProntos)(_codigo);
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _carregando = false;
        _erro = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar entregas: $e');
      // Erro numa releitura não apaga a lista que já está na tela.
      if (mounted && _carregando) {
        setState(() {
          _carregando = false;
          _erro = true;
        });
      }
    }
  }

  Future<void> _abrirLink(Uri uri, String falha) async {
    var ok = false;
    try {
      ok = await (widget.abrirLink ?? _abrirExterno)(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) showMdSnack(context, falha, tipo: MdTipo.erro);
  }

  static Future<bool> _abrirExterno(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _registrarEntrega(Map<String, dynamic> pedido) async {
    if (_abrindo) return;
    _abrindo = true;
    try {
      // A lista traz só algumas colunas; o editor precisa da linha completa.
      var completo = pedido;
      if (widget.paginaEntrega == null) {
        final id = int.tryParse('${pedido['id'] ?? ''}');
        final linha = id == null ? null : await buscarPedidoLocalPorId(id);
        if (linha == null) {
          if (mounted) await _carregar();
          return;
        }
        completo = linha;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => widget.paginaEntrega != null
              ? widget.paginaEntrega!(completo)
              : PedidoPageEdit(pedido: completo),
        ),
      );
      // Quem foi entregue sai da lista (recarrega sem trocar pelo spinner).
      if (mounted) await _carregar();
    } finally {
      _abrindo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _carregando || _erro
        ? const <GrupoEntrega>[]
        : entregasProntas(_pedidos, vendedorCodigo: _codigo);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Entregas do dia')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _atualizar,
                child: _erro
                    ? _rolavel(const MdEmptyState(
                        icone: Icons.error_outline,
                        titulo: 'Não foi possível carregar as entregas.',
                      ))
                    : grupos.isEmpty
                        ? _rolavel(const MdEmptyState(
                            icone: Icons.check_circle_outline,
                            titulo: 'Nenhum pedido pronto para entregar.',
                          ))
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(MdSpace.lg),
                            children: [
                              MdContentWidth(
                                maxWidth: 640,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final g in grupos) ...[
                                      Text(g.cidade, style: tt.titleLarge),
                                      const SizedBox(height: MdSpace.sm),
                                      for (final p in g.pedidos) ...[
                                        _cartao(p),
                                        const SizedBox(height: MdSpace.md),
                                      ],
                                      const SizedBox(height: MdSpace.md),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
      ),
    );
  }

  /// Estado vazio/erro rolável, para o puxar-para-atualizar funcionar nele.
  Widget _rolavel(Widget filho) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: filho),
        ),
      );

  /// "Pronto desde dd/MM HH:mm" em hora local; null se não der para ler.
  String? _prontoDesde(Object? prontoEm) {
    final dt = DateTime.tryParse('${prontoEm ?? ''}'.trim());
    if (dt == null) return null;
    return 'Pronto desde ${DateFormat('dd/MM HH:mm').format(dt.toLocal())}';
  }

  /// "Rua X, 123 · CEP 14400-000"; null sem endereço e sem CEP.
  String? _endereco(Map<String, dynamic> p) {
    final partes = [
      '${p['cliente_endereco'] ?? ''}'.trim(),
      if ('${p['cliente_cep'] ?? ''}'.trim().isNotEmpty)
        'CEP ${'${p['cliente_cep']}'.trim()}',
    ].where((s) => s.isNotEmpty);
    return partes.isEmpty ? null : partes.join(' · ');
  }

  Widget _cartao(Map<String, dynamic> p) {
    final tt = Theme.of(context).textTheme;
    final muted = tt.bodyMedium!.copyWith(color: MdColors.textMuted);
    final numero = '${p['numero'] ?? ''}'.trim();
    final mapa = linkMapa(p);
    final whats =
        linkWhatsApp(clienteDoPedido(p), mensagemPronto(_nome, numero));
    final desde = _prontoDesde(p['pronto_em']);
    final endereco = _endereco(p);
    final total =
        p['total'] is num ? p['total'] as num : num.tryParse('${p['total']}');
    return MdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nomeExibicao(clienteDoPedido(p)), style: tt.titleMedium),
          if (endereco != null) Text(endereco, style: muted),
          Text('Pedido nº $numero', style: muted),
          if (desde != null) Text(desde, style: muted),
          const SizedBox(height: MdSpace.xs),
          Text(resumoItens(p['produtos']), style: muted),
          if (total != null) Text(formatarReais(total), style: muted),
          const SizedBox(height: MdSpace.md),
          Wrap(
            spacing: MdSpace.sm,
            runSpacing: MdSpace.sm,
            children: [
              OutlinedButton.icon(
                onPressed: mapa == null
                    ? null
                    : () => _abrirLink(mapa, 'Não foi possível abrir o mapa.'),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Mapa'),
              ),
              OutlinedButton.icon(
                onPressed: whats == null
                    ? null
                    : () =>
                        _abrirLink(whats, 'Não foi possível abrir o WhatsApp.'),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Avisar'),
              ),
              FilledButton.icon(
                onPressed: () => _registrarEntrega(p),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Registrar entrega'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
