// lib/pages/ler_etiqueta_page.dart
//
// Fase B: lê o QR da etiqueta do pedido e abre a tela certa.
//  - pedido que está no celular: a edição do pedido (mesma chamada de
//    "Registrar entrega" em Meus pedidos);
//  - pedido que não está: "Entrega de pedido", consultando o servidor.
//
// A leitura trava na primeira leitura (a câmera repete o mesmo QR várias
// vezes por segundo) e só volta quando a tela de destino fecha ou, nas
// mensagens de erro, depois de um intervalo curto.
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/entrega_qr.dart';
import '../utils/regras_pedido.dart';
import 'entrega_qr_page.dart';
import 'pedido_edit_page.dart';

const String _msgQrInvalido = 'Esta etiqueta não é de um pedido da MilkDim.';
const String _msgSemInternet =
    'Sem internet. Para entregar pedido de outro vendedor, conecte e leia de novo.';
const String _msgCameraNegada =
    'Libere a câmera nas configurações do Android para ler etiquetas.';

/// A câmera só está configurada no Android (iOS/macOS não têm a chave de
/// permissão de câmera); nos outros sistemas o botão não aparece.
bool get leituraDeEtiquetaDisponivel => defaultTargetPlatform == TargetPlatform.android;

class LerEtiquetaPage extends StatefulWidget {
  /// Código do vendedor logado: só pedido dele abre como pedido local.
  final String vendedorCodigo;

  /// Para teste: no lugar da câmera.
  final Stream<String>? leituras;

  /// Para teste: no lugar de `decidirDestinoDaLeitura`.
  final Future<DestinoLeitura> Function(String lido)? decidir;

  /// Para teste: no lugar da tela de edição do pedido local.
  final Widget Function(Map<String, dynamic> pedido)? editor;

  const LerEtiquetaPage({
    super.key,
    required this.vendedorCodigo,
    this.leituras,
    this.decidir,
    this.editor,
  });

  @override
  State<LerEtiquetaPage> createState() => _LerEtiquetaPageState();
}

class _LerEtiquetaPageState extends State<LerEtiquetaPage> with WidgetsBindingObserver {
  MobileScannerController? _camera;
  StreamSubscription<String>? _sub;
  Timer? _intervalo;
  bool _travada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final leituras = widget.leituras;
    if (leituras != null) {
      _sub = leituras.listen(_aoLer);
    } else {
      _camera = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _intervalo?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  /// Parar e religar a câmera zera a "última leitura" do mobile_scanner (com
  /// `noDuplicates` ele nunca repetiria a mesma etiqueta) e libera a câmera
  /// enquanto outra tela está aberta.
  Future<void> _pararCamera() async {
    try {
      await _camera?.stop();
    } catch (e) {
      debugPrint('Câmera: erro ao parar: $e');
    }
  }

  Future<void> _ligarCamera() async {
    try {
      await _camera?.start();
    } catch (e) {
      debugPrint('Câmera: erro ao iniciar: $e');
    }
  }

  void _liberar() {
    _travada = false;
    if (mounted) _ligarCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_camera == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _pararCamera();
    } else if (state == AppLifecycleState.resumed && !_travada) {
      _ligarCamera();
    }
  }

  void _aoDetectar(BarcodeCapture captura) {
    for (final b in captura.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _aoLer(v);
        return;
      }
    }
  }

  Future<void> _aoLer(String lido) async {
    if (_travada) return;
    _travada = true;
    try {
      final decidir = widget.decidir ??
          (String l) => decidirDestinoDaLeitura(l, vendedorCodigo: widget.vendedorCodigo);
      final destino = await decidir(lido);
      if (!mounted) return;
      await _pararCamera();
      if (!mounted) return;
      switch (destino) {
        case AbrirPedidoLocal(:final pedido):
          if (!podeAbrirPelaEtiqueta(pedido)) {
            _avisarELiberar(motivoNaoAbrirPelaEtiqueta(pedido));
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) =>
                (widget.editor ?? (p) => PedidoPageEdit(pedido: p))(pedido)),
          );
        case AbrirEntregaServidor(:final codigoQr):
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EntregaQrPage(codigoQr: codigoQr)),
          );
        case QrInvalido():
          _avisarELiberar(_msgQrInvalido);
          return;
        case SemInternet():
          _avisarELiberar(_msgSemInternet);
          return;
      }
    } catch (e) {
      debugPrint('Ler etiqueta: erro: $e');
      if (mounted) {
        _avisarELiberar('Não deu para ler a etiqueta. Tente de novo.');
        return;
      }
    }
    _liberar();
  }

  /// Mostra a mensagem e só aceita nova leitura depois de um intervalo, para
  /// a câmera parada na mesma etiqueta não repetir o aviso sem parar.
  void _avisarELiberar(String msg) {
    showMdSnack(context, msg, tipo: MdTipo.erro);
    _intervalo?.cancel();
    _intervalo = Timer(const Duration(seconds: 2), _liberar);
  }

  Widget _semCamera(BuildContext context, MobileScannerException erro) {
    final negada = erro.errorCode == MobileScannerErrorCode.permissionDenied;
    return MdEmptyState(
      icone: Icons.no_photography_outlined,
      titulo: negada ? _msgCameraNegada : 'Não deu para abrir a câmera.',
      acao: FilledButton(
        onPressed: () => _camera?.start(),
        child: const Text('Tentar de novo'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ler etiqueta')),
      body: Column(
        children: [
          Expanded(
            child: _camera == null
                ? const ColoredBox(color: Colors.black)
                : MobileScanner(
                    controller: _camera,
                    onDetect: _aoDetectar,
                    errorBuilder: (ctx, erro) => _semCamera(ctx, erro),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(MdSpace.lg),
              child: Text(
                'Aponte a câmera para o QR da etiqueta do pedido.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
