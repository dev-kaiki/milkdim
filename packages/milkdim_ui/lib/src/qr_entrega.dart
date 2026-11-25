/// Conteúdo do QR da etiqueta de entrega.
///
/// O QR é um link `https://dev-kaiki.github.io/m/#<uuid sem traços>`. Com o
/// app instalado, o Android abre o app direto pelo link (App Link verificado
/// pelo `/.well-known/assetlinks.json` do site); sem o app, abre uma página
/// que manda usar o app. O código vai depois do `#`: o navegador não manda
/// essa parte ao site. Sem traços, o QR cabe numa versão menor (módulos
/// maiores na etiqueta pequena).
///
/// As etiquetas do formato antigo (`MILKDIM:E:<uuid>`) continuam sendo lidas
/// pelo botão "Ler etiqueta".
library;

/// Endereço do link da etiqueta (sem o código).
const String linkEtiquetaBase = 'https://dev-kaiki.github.io/m/';

/// Host e caminho que o app aceita como link de etiqueta (também usados no
/// AndroidManifest).
const String linkEtiquetaHost = 'dev-kaiki.github.io';
const String linkEtiquetaCaminho = '/m/';

const _prefixoAntigo = 'MILKDIM:E:';
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _hex32 = RegExp(r'^[0-9a-fA-F]{32}$');

/// Monta o link que vai dentro do QR.
String conteudoQrEntrega(String codigoQr) =>
    '$linkEtiquetaBase#${codigoQr.replaceAll('-', '').toLowerCase()}';

/// Devolve o uuid (com traços, em minúsculas) do QR lido, ou `null` se o
/// conteúdo não for de uma etiqueta da MilkDim. Aceita o link (código com ou
/// sem traços) e o formato antigo `MILKDIM:E:<uuid>`; espaços nas pontas não
/// atrapalham.
String? codigoDoQrEntrega(String lido) {
  final s = lido.trim();
  if (s.startsWith(_prefixoAntigo)) {
    final codigo = s.substring(_prefixoAntigo.length);
    return _uuid.hasMatch(codigo) ? codigo.toLowerCase() : null;
  }
  final uri = Uri.tryParse(s);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != linkEtiquetaHost ||
      uri.hasPort ||
      uri.hasQuery ||
      (uri.path != '/m/' && uri.path != '/m') ||
      !uri.hasFragment) {
    return null;
  }
  return _normalizar(uri.fragment);
}

String? _normalizar(String codigo) {
  if (_uuid.hasMatch(codigo)) return codigo.toLowerCase();
  if (!_hex32.hasMatch(codigo)) return null;
  final c = codigo.toLowerCase();
  return '${c.substring(0, 8)}-${c.substring(8, 12)}-${c.substring(12, 16)}-'
      '${c.substring(16, 20)}-${c.substring(20)}';
}
