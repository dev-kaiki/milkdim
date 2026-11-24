import 'package:qr/qr.dart';

/// Margem branca do QR, em módulos.
const margemQrModulos = 4;

/// Retângulo arredondado preto, em unidades de módulo, com a margem já somada.
///
/// Se [anel] for verdadeiro, só se pinta uma faixa de 1 módulo por dentro do
/// retângulo (o anel externo dos quadrados de canto).
class FormaQr {
  const FormaQr({
    required this.x,
    required this.y,
    required this.largura,
    required this.altura,
    required this.raio,
    this.anel = false,
  });

  final double x, y, largura, altura, raio;
  final bool anel;
}

typedef GeometriaQr = ({
  int modulos,
  List<FormaQr> formas,
  ({double x, double y, double lado}) areaLogo,
});

/// Geometria do QR com módulos arredondados e espaço central para o logo.
///
/// Correção de erro H e margem de [margemQrModulos] módulos. O lado da área do
/// logo fica em torno de 20% da largura útil, em módulos inteiros e
/// centralizado; os módulos dentro dela são omitidos.
GeometriaQr geometriaQrArredondado(String conteudo) {
  final code = QrCode.fromData(
    data: conteudo,
    errorCorrectLevel: QrErrorCorrectLevel.H,
  );
  final qr = QrImage(code);
  final n = code.moduleCount;
  const m = margemQrModulos;

  // Menor lado >= 20% da largura útil com a mesma paridade de n (centraliza).
  var lado = (n * 0.2).ceil();
  if ((n - lado).isOdd) lado++;
  final ini = (n - lado) ~/ 2; // em módulos, sem margem

  bool emFinder(int r, int c) =>
      (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
  bool emLogo(int r, int c) =>
      r >= ini && r < ini + lado && c >= ini && c < ini + lado;

  final formas = <FormaQr>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (emFinder(r, c) || emLogo(r, c) || !qr.isDark(r, c)) continue;
      formas.add(FormaQr(
        x: (c + m).toDouble(),
        y: (r + m).toDouble(),
        largura: 1,
        altura: 1,
        raio: 0.5,
      ));
    }
  }

  for (final (r, c) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
    final x = (c + m).toDouble(), y = (r + m).toDouble();
    formas.add(FormaQr(x: x, y: y, largura: 7, altura: 7, raio: 2, anel: true));
    formas.add(FormaQr(x: x + 2, y: y + 2, largura: 3, altura: 3, raio: 1));
  }

  return (
    modulos: n,
    formas: formas,
    areaLogo: (
      x: (ini + m).toDouble(),
      y: (ini + m).toDouble(),
      lado: lado.toDouble(),
    ),
  );
}
