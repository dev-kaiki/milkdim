// lib/utils/link_etiqueta.dart
//
// Link da etiqueta aberto pela câmera do celular (fora do app). O QR é um
// link https (ver `conteudoQrEntrega` no milkdim_ui); com o App Link
// verificado, o Android abre o app com ele. O link fica aqui até a tela
// inicial do vendedor logado abrir o pedido (ver OuvirEtiquetaPendente); sem
// login, espera o login.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:milkdim_ui/milkdim_ui.dart' show codigoDoQrEntrega;

/// Link de etiqueta que o Android entregou e ainda não foi aberto.
final ValueNotifier<String?> etiquetaPendente = ValueNotifier<String?>(null);

/// Guarda [link] para abrir, se for de uma etiqueta da MilkDim. Outros links
/// (o retorno de login do Supabase, por exemplo) são ignorados.
void receberLinkDeEtiqueta(String link) {
  if (codigoDoQrEntrega(link) != null) etiquetaPendente.value = link;
}

StreamSubscription<Uri>? _links;

/// Começa a ouvir os links (o que abriu o app e os que chegam com ele
/// aberto). Só no Android, o único com o App Link configurado.
void ouvirLinksDeEtiqueta() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _links != null) return;
  _links = AppLinks().allUriLinkStream.listen(
        (uri) => receberLinkDeEtiqueta(uri.toString()),
        onError: (Object e) => debugPrint('Link da etiqueta: $e'),
      );
}
