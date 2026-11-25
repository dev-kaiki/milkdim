// lib/pages/entrega_qr_page.dart
//
// Fase B: "Entrega de pedido" para a etiqueta lida que não está no celular.
// Consulta o servidor (`pedido_por_qr`), mostra o pedido e, quando a entrega
// é possível, pede a assinatura do cliente e registra (`pedido_entregar_por_qr`).
// Nada é gravado no banco local.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../utils/convert.dart' show signatureToImageBytes;
import '../utils/entrega_qr.dart';
import '../utils/pedido_da_tela.dart';
import 'assinatura_page.dart';

class EntregaQrPage extends StatefulWidget {
  final String codigoQr;

  /// Para teste: no lugar da tela de assinatura.
  final PedirAssinatura? pedirAssinatura;

  const EntregaQrPage({super.key, required this.codigoQr, this.pedirAssinatura});

  @override
  State<EntregaQrPage> createState() => _EntregaQrPageState();
}

class _EntregaQrPageState extends State<EntregaQrPage> {
  PedidoQr? _pedido;
  String? _erro;
  bool _carregando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final p = await buscarPedidoPorQr(widget.codigoQr);
      if (!mounted) return;
      setState(() {
        _pedido = p;
        _carregando = false;
      });
    } on FalhaEntregaQr catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    }
  }

  Future<Uint8List?> _pedirAssinatura() async {
    final injetada = widget.pedirAssinatura;
    if (injetada != null) return injetada(TipoAssinatura.entrega);
    final dynamic ret = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssinaturaPage(titulo: TipoAssinatura.entrega.titulo),
      ),
    );
    final img = signatureToImageBytes(ret);
    return (img == null || img.isEmpty) ? null : img;
  }

  Future<void> _registrar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      final bytes = await _pedirAssinatura();
      if (bytes == null || !mounted) return;
      await entregarPorQr(widget.codigoQr, bytes);
      if (!mounted) return;
      showMdSnack(context, 'Entrega registrada.', tipo: MdTipo.sucesso);
      Navigator.pop(context, true);
    } on FalhaEntregaQr catch (e) {
      if (mounted) showMdSnack(context, e.mensagem, tipo: MdTipo.erro);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrega de pedido')),
      body: SafeArea(child: _corpo(context)),
    );
  }

  Widget _corpo(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    final p = _pedido;
    if (p == null) {
      return MdEmptyState(
        icone: Icons.error_outline,
        titulo: _erro ?? 'Não deu para ler o pedido.',
        acao: OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
      );
    }
    final tt = Theme.of(context).textTheme;
    final motivo = p.motivoSemEntrega;
    final outroVendedor = !p.doProprioVendedor && (p.vendedorCodigo ?? '').isNotEmpty;
    final cliente = p.clienteTitulo;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(MdSpace.lg),
      child: MdContentWidth(
        maxWidth: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pedido ${p.numero}', style: tt.headlineSmall),
            if (outroVendedor) ...[
              const SizedBox(height: MdSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: MdStatusChip(
                  tipo: MdTipo.info,
                  texto: 'Pedido do vendedor ${(p.vendedorNome ?? '').trim().isNotEmpty ? p.vendedorNome!.trim() : p.vendedorCodigo}',
                  icone: Icons.badge_outlined,
                ),
              ),
            ],
            if (cliente.isNotEmpty) ...[
              const SizedBox(height: MdSpace.lg),
              Text(cliente, style: tt.titleMedium),
            ],
            if ((p.cidade ?? '').isNotEmpty) ...[
              const SizedBox(height: MdSpace.xs),
              Text(p.cidade!, style: tt.bodyMedium),
            ],
            if (p.itens.isNotEmpty) ...[
              const SizedBox(height: MdSpace.lg),
              for (final it in p.itens)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: MdSpace.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text('${it.quantidade}×',
                            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Expanded(child: Text(it.nome, style: tt.bodyMedium)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: MdSpace.xl),
            if (motivo != null)
              Text(motivo, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700))
            else
              FilledButton.icon(
                onPressed: _enviando ? null : _registrar,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Registrar entrega'),
              ),
          ],
        ),
      ),
    );
  }
}
