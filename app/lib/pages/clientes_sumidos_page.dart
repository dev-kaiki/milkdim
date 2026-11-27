// lib/pages/clientes_sumidos_page.dart
//
// Clientes que pararam de comprar: última compra, dias, quantidade de pedidos,
// e atalhos para WhatsApp, ligação e novo pedido. Só leitura: nenhum pedido
// é alterado aqui.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/clientes_sumidos.dart';
import '../utils/db.dart';
import 'pedido_page.dart';

/// Subtítulo do item da tela inicial.
String subtituloSumidos(int n) =>
    '$n sem comprar há ${kPrazosSumido.first} dias ou mais';

class ClientesSumidosPage extends StatefulWidget {
  final Map<String, dynamic> vendedor;

  /// Para teste: relógio, fontes de dados, abertura de links e a tela de pedido.
  final DateTime Function()? relogio;
  final Future<List<Map<String, dynamic>>> Function()? carregarClientes;
  final Future<List<Map<String, dynamic>>> Function(String vendedorCodigo)? carregarPedidos;
  final Future<bool> Function(Uri)? abrirLink;
  final Widget Function(Map<String, dynamic> vendedor, int clienteId)? paginaPedido;

  const ClientesSumidosPage({
    super.key,
    required this.vendedor,
    this.relogio,
    this.carregarClientes,
    this.carregarPedidos,
    this.abrirLink,
    this.paginaPedido,
  });

  @override
  State<ClientesSumidosPage> createState() => _ClientesSumidosPageState();
}

class _ClientesSumidosPageState extends State<ClientesSumidosPage> {
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _pedidos = [];
  bool _carregando = true;
  bool _erro = false;
  int _prazo = kPrazosSumido.first;

  String get _codigo => widget.vendedor['codigo']?.toString() ?? '';
  String get _nome => widget.vendedor['nome']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final clientes = await (widget.carregarClientes ?? listarClientes)();
      final pedidos = await (widget.carregarPedidos ?? listarPedidosParaSumidos)(_codigo);
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _pedidos = pedidos;
        _carregando = false;
        _erro = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar clientes sumidos: $e');
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

  Future<void> _novoPedido(int clienteId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.paginaPedido != null
            ? widget.paginaPedido!(widget.vendedor, clienteId)
            : PedidoPage(vendedor: widget.vendedor, clienteInicialId: clienteId),
      ),
    );
    // Quem acabou de comprar sai da lista (recarrega sem trocar pelo spinner).
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _carregando || _erro
        ? const <ClienteSumido>[]
        : clientesSumidos(
            clientes: _clientes,
            pedidos: _pedidos,
            vendedorCodigo: _codigo,
            agora: (widget.relogio ?? DateTime.now)(),
            prazoDias: _prazo,
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes sumidos')),
      body: SafeArea(
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro
                ? const MdEmptyState(
                    icone: Icons.error_outline,
                    titulo: 'Não foi possível carregar os clientes.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(MdSpace.lg),
                    children: [
                      MdContentWidth(
                        maxWidth: 640,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: MdSpace.sm,
                              children: [
                                for (final p in kPrazosSumido)
                                  ChoiceChip(
                                    label: Text('$p dias'),
                                    selected: _prazo == p,
                                    onSelected: (_) => setState(() => _prazo = p),
                                  ),
                              ],
                            ),
                            const SizedBox(height: MdSpace.lg),
                            if (lista.isEmpty)
                              MdEmptyState(
                                icone: Icons.check_circle_outline,
                                titulo: 'Nenhum cliente sumido há $_prazo dias ou mais.',
                              )
                            else
                              for (final s in lista) ...[
                                _linha(s),
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

  Widget _linha(ClienteSumido s) {
    final tt = Theme.of(context).textTheme;
    final whats = linkWhatsApp(s.cliente, mensagemSumido(_nome));
    final ligar = linkLigar(s.cliente);
    final id = (s.cliente['id'] as num?)?.toInt();
    final data = DateFormat('dd/MM').format(s.ultimaCompra);
    return MdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.cliente['nome'] ?? ''}', style: tt.titleMedium),
          const SizedBox(height: MdSpace.xs),
          Text('Última compra $data · há ${s.dias} dias',
              style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          Text(s.pedidos == 1 ? '1 pedido' : '${s.pedidos} pedidos',
              style: tt.bodyMedium!.copyWith(color: MdColors.textMuted)),
          const SizedBox(height: MdSpace.md),
          Wrap(
            spacing: MdSpace.sm,
            runSpacing: MdSpace.sm,
            children: [
              OutlinedButton.icon(
                onPressed: whats == null
                    ? null
                    : () => _abrirLink(whats, 'Não foi possível abrir o WhatsApp.'),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp'),
              ),
              OutlinedButton.icon(
                onPressed: ligar == null
                    ? null
                    : () => _abrirLink(ligar, 'Não foi possível abrir o discador.'),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Ligar'),
              ),
              FilledButton.icon(
                onPressed: id == null ? null : () => _novoPedido(id),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Novo pedido'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
