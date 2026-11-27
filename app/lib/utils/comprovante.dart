// lib/utils/comprovante.dart
//
// Comprovante do pedido: o PDF do pedido, pronto para compartilhar (WhatsApp
// etc.). Uma só função para Meus pedidos e para a tela de entrega.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'convert.dart' show signatureToImageBytes;
import 'pdf_utils.dart';

/// Texto que acompanha o comprovante. Número vazio ou nulo vira "s/n".
String textoComprovante(Object? numero) {
  final n = (numero ?? '').toString().trim();
  return 'Comprovante do pedido nº ${n.isEmpty ? 's/n' : n} – MilkDim. '
      'Obrigado pela preferência!';
}

/// Converte a assinatura da entrega em bytes de IMAGEM (PNG/JPEG) para o PDF.
/// 1) Tenta o arquivo local (`assinatura_path`)
/// 2) Fallback para formatos antigos (base64/hex/data URI/Uint8List) nas chaves conhecidas
Uint8List? assinaturaAsBytes(Map<String, dynamic> pedido) {
  // 1) Caminho local (preferível)
  final dynamic pth = pedido['assinatura_path'];
  if (pth is String && pth.isNotEmpty) {
    try {
      // normaliza "file://...": evita falha ao abrir
      final path = pth.startsWith('file://') ? Uri.parse(pth).toFilePath() : pth;
      final f = File(path);
      if (f.existsSync()) {
        final bytes = f.readAsBytesSync();
        final img = signatureToImageBytes(bytes);
        if (img != null && img.isNotEmpty) return img;
      }
    } catch (_) {
      // ignora e tenta os formatos antigos
    }
  }

  // 2) Formatos antigos (bytes/base64/hex/data-uri)
  final dynamic any = pedido['assinatura'] ??
      pedido['assinatura_base64'] ??
      pedido['assinaturaBytes'] ??
      pedido['signature'] ??
      pedido['signature_base64'];

  final img = signatureToImageBytes(any);
  return (img != null && img.isNotEmpty) ? img : null;
}

/// Assinatura do pedido para o PDF: o arquivo do aparelho, senão os bytes
/// (a sincronização limpa o caminho e traz os bytes do servidor).
Uint8List? assinaturaPedidoAsBytes(Map<String, dynamic> pedido) => imagemDaAssinatura(pedido,
    chaveBytes: 'assinatura_pedido', chaveCaminho: 'assinatura_pedido_path');

/// PDF do pedido com as duas assinaturas (a do pedido pode faltar nos antigos).
Future<Uint8List> pdfDoComprovante(Map<String, dynamic> pedido) => gerarPdfPedido(
      pedido: pedido,
      assinaturaBytes: assinaturaAsBytes(pedido),
      assinaturaPedidoBytes: assinaturaPedidoAsBytes(pedido),
    );

/// Grava o PDF num arquivo temporário e abre o compartilhar. [texto] troca o
/// texto padrão ([textoComprovante]); [compartilhar] existe para testes.
/// Erros sobem para quem chamou.
Future<void> compartilharComprovante(
  Map<String, dynamic> pedido, {
  String? texto,
  Future<void> Function(List<XFile> arquivos, String texto)? compartilhar,
}) async {
  final dir = await getTemporaryDirectory();
  final numero = (pedido['numero'] ?? 's_n').toString();
  final id = (pedido['id'] ?? '0').toString();
  final pdfBytes = await pdfDoComprovante(pedido);
  final pdfFile = File('${dir.path}/pedido_${numero}_$id.pdf');
  await pdfFile.writeAsBytes(pdfBytes, flush: true);
  final msg = texto ?? textoComprovante(pedido['numero']);
  if (compartilhar != null) {
    await compartilhar([XFile(pdfFile.path)], msg);
  } else {
    await Share.shareXFiles([XFile(pdfFile.path)], text: msg, subject: msg);
  }
}
