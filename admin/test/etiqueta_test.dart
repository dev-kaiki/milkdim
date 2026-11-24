import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:milkdim_admin/etiqueta/etiqueta_pdf.dart';
import 'package:milkdim_admin/etiqueta/qr_arredondado.dart';
import 'package:milkdim_admin/etiqueta/tamanho_etiqueta.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing2/qrcode.dart';

const _uuids = [
  '3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b',
  '00000000-0000-4000-8000-000000000000',
  'ffffffff-ffff-4fff-bfff-ffffffffffff',
  '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
  'a7c3e1f2-58d4-4c9a-b6e1-0f4d2a9c7e15',
];

/// Rasteriza a geometria: 8 px por módulo, preto sobre branco, com a área do
/// logo branca e um quadrado preto menor no meio (como o logo impresso).
img.Image rasterizar(String conteudo, {int px = 8}) {
  final g = geometriaQrArredondado(conteudo);
  final total = g.modulos + 2 * margemQrModulos;
  final im = img.Image(width: total * px, height: total * px, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));

  bool dentro(
      double x, double y, double fx, double fy, double w, double h, double r) {
    if (x < fx || x > fx + w || y < fy || y > fy + h) return false;
    final cx = x < fx + r ? fx + r : (x > fx + w - r ? fx + w - r : x);
    final cy = y < fy + r ? fy + r : (y > fy + h - r ? fy + h - r : y);
    final dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  }

  for (var py = 0; py < im.height; py++) {
    for (var pxx = 0; pxx < im.width; pxx++) {
      final x = (pxx + 0.5) / px, y = (py + 0.5) / px;
      var preto = false;
      for (final f in g.formas) {
        final r = f.raio;
        var d = dentro(x, y, f.x, f.y, f.largura, f.altura, r);
        if (d && f.anel) {
          d = !dentro(x, y, f.x + 1, f.y + 1, f.largura - 2, f.altura - 2,
              r > 1 ? r - 1 : 0);
        }
        if (d) {
          preto = true;
          break;
        }
      }
      final l = g.areaLogo;
      if (x >= l.x && x <= l.x + l.lado && y >= l.y && y <= l.y + l.lado) {
        // Branco, com um quadrado preto de metade do lado no meio.
        preto = x >= l.x + l.lado * 0.25 &&
            x <= l.x + l.lado * 0.75 &&
            y >= l.y + l.lado * 0.25 &&
            y <= l.y + l.lado * 0.75;
      }
      if (preto) im.setPixelRgb(pxx, py, 0, 0, 0);
    }
  }
  return im;
}

String decodificar(img.Image im) {
  final pixels = Int32List(im.width * im.height);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      final g = p.r.toInt();
      pixels[y * im.width + x] = (0xFF << 24) | (g << 16) | (g << 8) | g;
    }
  }
  final fonte = RGBLuminanceSource(im.width, im.height, pixels);
  final bitmap = BinaryBitmap(HybridBinarizer(fonte));
  return QRCodeReader().decode(bitmap).text;
}

EtiquetaDados _dados({int itens = 3}) => EtiquetaDados(
      numero: 1234,
      clienteTitulo: 'Cliente Teste',
      cidade: 'Cidade Teste',
      vendedorCodigo: '0002',
      itens: [
        for (var i = 0; i < itens; i++)
          (nome: 'Produto de teste ${i + 1}', quantidade: 3 + i),
      ],
      prontoEm: DateTime(2026, 11, 24, 14, 5),
      codigoQr: _uuids.first,
    );

Uint8List? _logo() {
  final f = File('../packages/milkdim_ui/assets/logo.jpg');
  return f.existsSync() ? f.readAsBytesSync() : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QR arredondado', () {
    test('o QR arredondado decodifica de volta no mesmo conteúdo', () {
      for (final u in _uuids) {
        final c = conteudoQrEntrega(u);
        expect(decodificar(rasterizar(c)), c, reason: u);
      }
    });

    test('a área do logo cobre no máximo 22% da área útil', () {
      for (final u in _uuids) {
        final g = geometriaQrArredondado(conteudoQrEntrega(u));
        final lado = g.areaLogo.lado;
        expect(lado * lado / (g.modulos * g.modulos), lessThanOrEqualTo(0.22));
        // R1: o lado fica entre 20% e 25% da largura útil.
        expect(lado / g.modulos, inInclusiveRange(0.20, 0.25));
        // Alinhada a módulos inteiros e centralizada.
        expect(lado, lado.roundToDouble());
        expect(g.areaLogo.x, g.areaLogo.x.roundToDouble());
        expect(g.areaLogo.x - margemQrModulos,
            g.modulos - (g.areaLogo.x - margemQrModulos) - lado);
      }
    });

    test('margem de 4 módulos', () {
      final g = geometriaQrArredondado(conteudoQrEntrega(_uuids.first));
      final total = g.modulos + 2 * margemQrModulos;
      expect(g.formas, isNotEmpty);
      for (final f in g.formas) {
        expect(f.x, greaterThanOrEqualTo(4));
        expect(f.y, greaterThanOrEqualTo(4));
        expect(f.x + f.largura, lessThanOrEqualTo(total - 4));
        expect(f.y + f.altura, lessThanOrEqualTo(total - 4));
      }
    });

    test('nenhum módulo escuro fica dentro da área do logo', () {
      final g = geometriaQrArredondado(conteudoQrEntrega(_uuids.first));
      final l = g.areaLogo;
      for (final f in g.formas) {
        final cruza = f.x < l.x + l.lado &&
            f.x + f.largura > l.x &&
            f.y < l.y + l.lado &&
            f.y + f.altura > l.y;
        expect(cruza, isFalse);
      }
    });
  });

  group('paginação', () {
    test(
        'paginarItens: 25 itens em 60x40 dão mais de uma página e não perdem item',
        () {
      final p = paginarItens(25, TamanhoEtiqueta.m60x40);
      expect(p.length, greaterThan(1));
      expect(p.expand((e) => e).toList(), List.generate(25, (i) => i));
    });

    test('paginarItens: 3 itens em 100x100 dão uma página', () {
      final p = paginarItens(3, TamanhoEtiqueta.m100x100);
      expect(p, [
        [0, 1, 2]
      ]);
    });

    test('paginarItens: sem itens ainda dá uma página', () {
      expect(paginarItens(0, TamanhoEtiqueta.m100x100).length, 1);
    });
  });

  group('PDF', () {
    test('gerarEtiquetaPdf gera PDF não vazio para os três tamanhos', () async {
      for (final t in TamanhoEtiqueta.values) {
        final bytes = await gerarEtiquetaPdf(_dados(), t, logo: _logo());
        expect(bytes, isNotEmpty);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: t.name);
      }
    });

    test('"Pronto em" sai na hora local, não em UTC', () {
      // Como o Pedido lê o pronto_em do PostgREST.
      final utc = DateTime.parse('2026-11-24T17:05:00+00:00');
      expect(utc.isUtc, isTrue);
      final local = DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
      expect(textoProntoEm(utc), DateFormat('dd/MM HH:mm').format(local));
      if (local.timeZoneOffset != Duration.zero) {
        expect(textoProntoEm(utc), isNot('24/11 17:05'));
      }
      // Hora já local fica como está.
      expect(textoProntoEm(DateTime(2026, 11, 24, 14, 5)), '24/11 14:05');
    });

    test('gera PDF também sem logo e com muitos itens', () async {
      final bytes =
          await gerarEtiquetaPdf(_dados(itens: 25), TamanhoEtiqueta.m60x40);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('tamanho da etiqueta', () {
    test('padrão 100x100 e grava a escolha', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await lerTamanhoEtiqueta(), TamanhoEtiqueta.m100x100);
      await gravarTamanhoEtiqueta(TamanhoEtiqueta.m60x40);
      expect(await lerTamanhoEtiqueta(), TamanhoEtiqueta.m60x40);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('etiqueta_tamanho'), isNotNull);
    });

    test('medidas e rótulos', () {
      expect(TamanhoEtiqueta.m100x100.rotulo, '100 × 100 mm');
      expect(TamanhoEtiqueta.m100x150.larguraMm, 100);
      expect(TamanhoEtiqueta.m100x150.alturaMm, 150);
      expect(TamanhoEtiqueta.m60x40.rotulo, '60 × 40 mm');
    });
  });

  group('amostra', () {
    test('grava a amostra para o Kaiki', () async {
      final dir = Directory('build/amostra_etiqueta')
        ..createSync(recursive: true);
      final logo = _logo();
      File('${dir.path}/etiqueta_100x100.pdf').writeAsBytesSync(
          await gerarEtiquetaPdf(_dados(), TamanhoEtiqueta.m100x100,
              logo: logo));
      File('${dir.path}/etiqueta_60x40_muitos_itens.pdf').writeAsBytesSync(
          await gerarEtiquetaPdf(_dados(itens: 25), TamanhoEtiqueta.m60x40,
              logo: logo));
      File('${dir.path}/qr.png').writeAsBytesSync(
          img.encodePng(rasterizar(conteudoQrEntrega(_uuids.first))));
      for (final n in [
        'etiqueta_100x100.pdf',
        'etiqueta_60x40_muitos_itens.pdf',
        'qr.png'
      ]) {
        expect(File('${dir.path}/$n').existsSync(), isTrue);
      }
    }, tags: ['amostra']);
  });
}
