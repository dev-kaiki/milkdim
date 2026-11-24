/// Conteúdo do QR da etiqueta de entrega: texto puro `MILKDIM:E:<uuid>`.
library;

const _prefixo = 'MILKDIM:E:';
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Monta o texto que vai dentro do QR.
String conteudoQrEntrega(String codigoQr) => '$_prefixo$codigoQr';

/// Devolve o uuid (em minúsculas) do QR lido, ou `null` se o conteúdo não for
/// de uma etiqueta da MilkDim. Aceita espaços nas pontas; o prefixo é
/// sensível a maiúsculas.
String? codigoDoQrEntrega(String lido) {
  final s = lido.trim();
  if (!s.startsWith(_prefixo)) return null;
  final codigo = s.substring(_prefixo.length);
  if (!_uuid.hasMatch(codigo)) return null;
  return codigo.toLowerCase();
}
