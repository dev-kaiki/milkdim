// lib/etiqueta/estado_etiqueta.dart
//
// Texto e tom da situação da etiqueta de um pedido pronto; compartilhado pelo
// cartão da aba Produção e pelo detalhe do pedido.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import '../models/pedido.dart';

final _hora = DateFormat('HH:mm');

/// "Sem etiqueta", "Etiqueta impressa às HH:mm" ou "Etiqueta desatualizada".
/// Com [quem] (o nome de quem imprimiu), a impressa acrescenta " por <quem>".
({MdTipo tipo, IconData icone, String texto}) estadoEtiqueta(Pedido p, {String? quem}) {
  if (p.etiquetaDesatualizada) {
    return (
      tipo: MdTipo.atencao,
      icone: Icons.print_disabled_outlined,
      texto: 'Etiqueta desatualizada',
    );
  }
  if (p.etiquetaImpressaEm != null) {
    final por = (quem ?? '').trim();
    return (
      tipo: MdTipo.neutro,
      icone: Icons.print_outlined,
      texto: 'Etiqueta impressa às ${_hora.format(p.etiquetaImpressaEm!.toLocal())}'
          '${por.isNotEmpty ? ' por $por' : ''}',
    );
  }
  return (tipo: MdTipo.atencao, icone: Icons.print_outlined, texto: 'Sem etiqueta');
}

Widget chipEtiqueta(Pedido p, {String? quem}) {
  final e = estadoEtiqueta(p, quem: quem);
  return MdStatusChip(tipo: e.tipo, icone: e.icone, texto: e.texto);
}
