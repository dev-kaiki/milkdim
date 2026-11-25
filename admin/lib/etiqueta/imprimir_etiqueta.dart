import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/pedido.dart';
import '../widgets/lista_adaptavel.dart';
import 'etiqueta_pdf.dart';
import 'tamanho_etiqueta.dart';

/// Envia o PDF para a impressora. Devolve false se o diálogo do sistema foi
/// cancelado (nada saiu).
typedef EnviarParaImpressora = Future<bool> Function(Uint8List pdf, TamanhoEtiqueta t);

Future<bool> _enviarPadrao(Uint8List pdf, TamanhoEtiqueta t) {
  final formato = PdfPageFormat(
    t.larguraMm * PdfPageFormat.mm,
    t.alturaMm * PdfPageFormat.mm,
  );
  return Printing.layoutPdf(
    name: 'Etiqueta',
    format: formato,
    usePrinterSettings: true,
    onLayout: (_) async => pdf,
  );
}

/// Dados da etiqueta a partir do pedido (nome fantasia, se houver, senão o nome).
/// O vendedor sai pelo nome; sem nome no pedido, pelo código. Sem telefone,
/// vai o WhatsApp.
EtiquetaDados etiquetaDoPedido(Pedido p) {
  final fantasia = (p.clienteNomeFantasia ?? '').trim();
  final nome = (p.clienteNome ?? '').trim();
  final nomeVendedor = (p.vendedorNome ?? '').trim();
  final telefone = (p.clienteTelefone ?? '').trim();
  return EtiquetaDados(
    numero: int.tryParse((p.numero ?? '').trim()) ?? p.id,
    clienteTitulo: fantasia.isNotEmpty ? fantasia : nome,
    cidade: (p.clienteCidade ?? '').trim(),
    vendedor: nomeVendedor.isNotEmpty ? nomeVendedor : (p.vendedorCodigo ?? '').trim(),
    itens: [for (final i in p.itens) (nome: i.nome.trim(), quantidade: i.quantidade)],
    prontoEm: p.prontoEm,
    codigoQr: p.codigoQr ?? '',
    endereco: (p.clienteEndereco ?? '').trim(),
    cep: (p.clienteCep ?? '').trim(),
    telefone: telefone.isNotEmpty ? telefone : (p.clienteWhatsapp ?? '').trim(),
  );
}

enum _Resposta { sim, denovo, cancelar }

/// Gera a etiqueta, envia para a impressora e pergunta se saiu certa. Só o
/// "Sim" chama [marcar], com o `alterado_em` (texto bruto) do pedido de onde
/// a etiqueta saiu: o servidor recusa se o pedido mudou depois. Devolve true
/// se marcou.
Future<bool> imprimirEtiquetaComConfirmacao(
  BuildContext context,
  Pedido p, {
  required Future<void> Function(int id, String? alteradoEmBruto) marcar,
  EnviarParaImpressora? enviar,
}) async {
  TamanhoEtiqueta tamanho;
  try {
    tamanho = await lerTamanhoEtiqueta();
  } catch (_) {
    tamanho = TamanhoEtiqueta.m100x100;
  }
  final envio = enviar ?? _enviarPadrao;
  while (true) {
    final pdf = await gerarEtiquetaPdf(etiquetaDoPedido(p), tamanho);
    final saiu = await envio(pdf, tamanho);
    if (!saiu) return false;
    if (!context.mounted) return false;
    final r = await showDialog<_Resposta>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const TituloDialogo(
          icone: Icons.print_outlined,
          texto: 'A etiqueta saiu certa?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.cancelar),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.denovo),
            child: const Text('Imprimir de novo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_Resposta.sim),
            child: const Text('Sim'),
          ),
        ],
      ),
    );
    switch (r) {
      case _Resposta.sim:
        await marcar(p.id, p.alteradoEmBruto);
        return true;
      case _Resposta.denovo:
        continue;
      case _Resposta.cancelar:
      case null:
        return false;
    }
  }
}
