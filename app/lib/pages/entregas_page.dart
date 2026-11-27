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
String subtituloEntregas(int? n) =>
    n == null ? 'Pedidos prontos para entregar' : '$n prontos para entregar';

Future<void> _baixarDoSupabase(String vendedorCodigo) =>
    sincronizarPedidos(vendedorCodigo: vendedorCodigo);

class EntregasPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Para teste: baixar do servidor, ler o aparelho, abrir links e a tela
  /// de registrar entrega.
  final Future<void> Function(String vendedorCodigo)? baixarPedidos;
  final Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)? carregarPedidos;
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

  Future<void> _carregar() async {
    try {
      final pedidos =
          await (widget.carregarPedidos ?? listarPedidosLocaisPorVendedor)(_codigo);
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _carregando = false;
        _erro = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar entregas: $e');
      if (mounted) {
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.paginaEntrega != null
            ? widget.paginaEntrega!(pedido)
            : PedidoPageEdit(pedido: pedido),
      ),
    );
    // Quem foi entregue sai da lista (recarrega sem trocar pelo spinner).
    if (mounted) await _carregar();
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
            : _erro
                ? const MdEmptyState(
                    icone: Icons.error_outline,
                    titulo: 'Não foi possível carregar as entregas.',
                  )
                : grupos.isEmpty
                    ? const MdEmptyState(
                        icone: Icons.check_circle_outline,
                        titulo: 'Nenhum pedido pronto para entregar.',
                      )
                    : ListView(
                        padding: const EdgeInsets.all(MdSpace.lg),
                        children: [
                          MdContentWidth(
                            maxWidth: 640,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
    );
  }

  /// "Pronto desde dd/MM HH:mm" em hora local; null se não der para ler.
  String? _prontoDesde(Object? prontoEm) {
    final dt = DateTime.tryParse('${prontoEm ?? ''}'.trim());
    if (dt == null) return null;
    return 'Pronto desde ${DateFormat('dd/MM HH:mm').format(dt.toLocal())}';
  }

  Widget _cartao(Map<String, dynamic> p) {
    final tt = Theme.of(context).textTheme;
    final muted = tt.bodyMedium!.copyWith(color: MdColors.textMuted);
    final numero = '${p['numero'] ?? ''}'.trim();
    final mapa = linkMapa(p);
    final whats = linkWhatsApp(clienteDoPedido(p), mensagemPronto(_nome, numero));
    final desde = _prontoDesde(p['pronto_em']);
    final total = p['total'] is num ? p['total'] as num : num.tryParse('${p['total']}');
    return MdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nomeExibicao(clienteDoPedido(p)), style: tt.titleMedium),
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
                    : () => _abrirLink(whats, 'Não foi possível abrir o WhatsApp.'),
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
