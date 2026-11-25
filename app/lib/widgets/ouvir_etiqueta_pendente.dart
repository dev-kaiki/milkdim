// lib/widgets/ouvir_etiqueta_pendente.dart
//
// Na tela inicial do vendedor logado: quando chega um link de etiqueta (a
// câmera do celular leu o QR fora do app), abre o pedido pelo mesmo caminho
// do botão "Ler etiqueta".
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../pages/ler_etiqueta_page.dart';
import '../utils/link_etiqueta.dart';

class OuvirEtiquetaPendente extends StatefulWidget {
  final String vendedorCodigo;
  final Widget child;

  /// Para teste: no lugar de [abrirPelaEtiqueta]. Devolve a mensagem de erro.
  final Future<String?> Function(BuildContext context, String lido)? abrir;

  const OuvirEtiquetaPendente({
    super.key,
    required this.vendedorCodigo,
    required this.child,
    this.abrir,
  });

  @override
  State<OuvirEtiquetaPendente> createState() => _OuvirEtiquetaPendenteState();
}

class _OuvirEtiquetaPendenteState extends State<OuvirEtiquetaPendente> {
  bool _abrindo = false;

  @override
  void initState() {
    super.initState();
    etiquetaPendente.addListener(_verificar);
    // O link pode ter chegado antes do login ou da tela abrir.
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar());
  }

  @override
  void dispose() {
    etiquetaPendente.removeListener(_verificar);
    super.dispose();
  }

  Future<void> _verificar() async {
    final link = etiquetaPendente.value;
    if (link == null || _abrindo || !mounted || widget.vendedorCodigo.isEmpty) return;
    etiquetaPendente.value = null;
    _abrindo = true;
    try {
      final msg = await (widget.abrir ??
          (ctx, lido) => abrirPelaEtiqueta(ctx, lido, vendedorCodigo: widget.vendedorCodigo))(
        context,
        link,
      );
      if (msg != null && mounted) showMdSnack(context, msg, tipo: MdTipo.erro);
    } catch (e) {
      debugPrint('Link da etiqueta: erro: $e');
      if (mounted) {
        showMdSnack(context, 'Não deu para abrir a etiqueta. Tente de novo.',
            tipo: MdTipo.erro);
      }
    } finally {
      _abrindo = false;
    }
    // Chegou outro link enquanto o pedido estava aberto.
    if (mounted && etiquetaPendente.value != null) _verificar();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
