import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:milkdim_admin/etiqueta/etiqueta_pdf.dart';
import 'package:milkdim_admin/etiqueta/imprimir_etiqueta.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/etiqueta/qr_arredondado.dart';
import 'package:milkdim_admin/etiqueta/tamanho_etiqueta.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
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
      vendedor: 'Vendedor Teste',
      itens: [
        for (var i = 0; i < itens; i++)
          (nome: 'Produto de teste ${i + 1}', quantidade: 3 + i),
      ],
      prontoEm: DateTime(2026, 11, 24, 14, 5),
      codigoQr: _uuids.first,
      endereco: 'Rua de Teste, 123 - Centro',
      cep: '15990000',
      telefone: '(16) 99999-0000',
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
      final local =
          DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
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

  group('dados da etiqueta', () {
    Pedido pedido({String? nome, String? codigo = '0002'}) => Pedido(
          id: 9,
          numero: '77',
          total: 0,
          status: 'pronto',
          vendedorCodigo: codigo,
          vendedorNome: nome,
          clienteNome: 'Cliente Teste',
          itens: const [],
        );

    test('a etiqueta leva o nome do vendedor, não o código', () {
      expect(etiquetaDoPedido(pedido(nome: ' Vendedor Teste ')).vendedor,
          'Vendedor Teste');
    });

    test('sem nome no pedido, leva o código', () {
      expect(etiquetaDoPedido(pedido(nome: '  ')).vendedor, '0002');
      expect(etiquetaDoPedido(pedido(nome: null, codigo: null)).vendedor, '');
    });

    Pedido comContato({
      String? endereco,
      String? cep,
      String? telefone,
      String? whatsapp,
    }) =>
        Pedido(
          id: 9,
          numero: '77',
          total: 0,
          status: 'pronto',
          clienteNome: 'Cliente Teste',
          clienteEndereco: endereco,
          clienteCep: cep,
          clienteTelefone: telefone,
          clienteWhatsapp: whatsapp,
          itens: const [],
        );

    test('a etiqueta leva endereço, CEP e telefone do pedido', () {
      final d = etiquetaDoPedido(comContato(
        endereco: ' Rua Teste, 10 ',
        cep: ' 15990000 ',
        telefone: ' (16) 3333-0000 ',
        whatsapp: '(16) 99999-0000',
      ));
      expect(d.endereco, 'Rua Teste, 10');
      expect(d.cep, '15990000');
      expect(d.telefone, '(16) 3333-0000');
    });

    test('sem telefone, usa o WhatsApp', () {
      expect(
          etiquetaDoPedido(
                  comContato(telefone: ' ', whatsapp: '(16) 99999-0000'))
              .telefone,
          '(16) 99999-0000');
      expect(etiquetaDoPedido(comContato()).telefone, '');
    });
  });

  group('bloco "Entregar em"', () {
    EtiquetaDados com(
            {String endereco = '', String cep = '', String telefone = ''}) =>
        EtiquetaDados(
          numero: 1,
          clienteTitulo: 'Cliente Teste',
          cidade: 'Cidade Teste',
          vendedor: '',
          itens: const [],
          prontoEm: null,
          codigoQr: _uuids.first,
          endereco: endereco,
          cep: cep,
          telefone: telefone,
        );

    test('com tudo preenchido', () {
      expect(
        linhasEntrega(com(
            endereco: 'Rua Teste, 10',
            cep: '15990000',
            telefone: '(16) 3333-0000')),
        [
          'Entregar em',
          'Rua Teste, 10',
          'CEP 15990-000',
          'Tel. (16) 3333-0000'
        ],
      );
    });

    test('linha vazia não aparece', () {
      expect(linhasEntrega(com(endereco: 'Rua Teste, 10')),
          ['Entregar em', 'Rua Teste, 10']);
      expect(linhasEntrega(com(telefone: '(16) 3333-0000')),
          ['Entregar em', 'Tel. (16) 3333-0000']);
    });

    test('sem endereço, CEP nem telefone, o bloco some', () {
      expect(linhasEntrega(com()), isEmpty);
    });

    test('CEP: formata 8 dígitos e não repete o "CEP"', () {
      expect(linhasEntrega(com(cep: '15.990-000')).last, 'CEP 15990-000');
      expect(linhasEntrega(com(cep: 'CEP: 15990-000')).last, 'CEP 15990-000');
      expect(linhasEntrega(com(cep: '1599')).last, 'CEP 1599');
    });

    test('gera o PDF com o bloco nos três tamanhos, mesmo com endereço longo',
        () async {
      final d = com(
        endereco:
            'Avenida de Teste com um Nome Bem Comprido, 12345 - Bairro Distante',
        cep: '15990000',
        telefone: '(16) 99999-0000',
      );
      for (final t in TamanhoEtiqueta.values) {
        final bytes = await gerarEtiquetaPdf(d, t, logo: _logo());
        expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: t.name);
      }
    });
  });

  group('volumes', () {
    const v3 = VolumesPedido(solto: false, volumes: [
      Volume(caixa: true, tipoNome: 'Copo', itens: [
        ItemVolume(nome: 'Produto A', quantidade: 20),
      ]),
      Volume(caixa: true, tipoNome: 'Copo', itens: [
        ItemVolume(nome: 'Produto A', quantidade: 5),
        ItemVolume(nome: 'Produto B', quantidade: 15),
      ]),
      Volume(caixa: false, tipoNome: null, itens: [
        ItemVolume(nome: 'Produto C', quantidade: 2),
      ]),
    ]);

    int paginas(Uint8List b) => RegExp(r'/Type\s*/Page(?![a-z])')
        .allMatches(String.fromCharCodes(b))
        .length;

    test('etiquetasDosVolumes copia cliente e QR, troca itens e rotula', () {
      final base = _dados();
      final l = etiquetasDosVolumes(base, v3);
      expect(l.length, 3);
      expect(l.map((e) => e.volume),
          ['Caixa 1/3 · Copo', 'Caixa 2/3 · Copo', 'Avulsos 3/3']);
      for (final e in l) {
        expect(e.numero, base.numero);
        expect(e.clienteTitulo, base.clienteTitulo);
        expect(e.codigoQr, base.codigoQr);
        expect(e.endereco, base.endereco);
        expect(e.vendedor, base.vendedor);
      }
      expect(l[1].itens, [
        (nome: 'Produto A', quantidade: 5),
        (nome: 'Produto B', quantidade: 15),
      ]);
    });

    test('3 volumes geram um PDF com uma página por volume', () async {
      final l = etiquetasDosVolumes(_dados(), v3);
      for (final t in TamanhoEtiqueta.values) {
        final b = await gerarEtiquetasPdf(l, t, logo: _logo());
        expect(String.fromCharCodes(b.take(4)), '%PDF', reason: t.name);
        expect(paginas(b), 3, reason: t.name);
      }
    });

    test('volume com 25 itens em 60x40 continua paginando', () async {
      final d = EtiquetaDados(
        numero: 1,
        clienteTitulo: 'Cliente Teste',
        cidade: 'Cidade Teste',
        vendedor: '',
        itens: [
          for (var i = 0; i < 25; i++) (nome: 'Produto $i', quantidade: 1)
        ],
        prontoEm: null,
        codigoQr: _uuids.first,
        volume: 'Caixa 1/1 · Copo',
      );
      final b = await gerarEtiquetasPdf([d], TamanhoEtiqueta.m60x40);
      expect(paginas(b), greaterThan(1));
      expect(paginas(b),
          paginarItens(25, TamanhoEtiqueta.m60x40, comVolume: true).length);
    });

    test('lista de etiquetas vazia é erro', () {
      expect(() => gerarEtiquetasPdf([], TamanhoEtiqueta.m100x100),
          throwsArgumentError);
    });

    test('com rótulo cabem menos itens por página, nunca mais', () {
      for (final t in TamanhoEtiqueta.values) {
        final sem = paginarItens(60, t);
        final com = paginarItens(60, t, comVolume: true);
        expect(com.first.length, lessThanOrEqualTo(sem.first.length),
            reason: t.name);
        expect(com.length, greaterThanOrEqualTo(sem.length), reason: t.name);
        expect(com.expand((e) => e).length, 60, reason: t.name);
      }
    });

    test('sem rótulo, o PDF tem as páginas de antes', () async {
      for (final t in TamanhoEtiqueta.values) {
        final d = _dados(itens: 25);
        final a = await gerarEtiquetaPdf(d, t);
        final b = await gerarEtiquetasPdf([d], t);
        expect(paginas(a), paginarItens(25, t).length, reason: t.name);
        expect(paginas(b), paginas(a), reason: t.name);
      }
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
      File('${dir.path}/etiqueta_100x150.pdf').writeAsBytesSync(
          await gerarEtiquetaPdf(_dados(), TamanhoEtiqueta.m100x150,
              logo: logo));
      File('${dir.path}/etiqueta_60x40_muitos_itens.pdf').writeAsBytesSync(
          await gerarEtiquetaPdf(_dados(itens: 25), TamanhoEtiqueta.m60x40,
              logo: logo));
      File('${dir.path}/etiqueta_volumes_100x100.pdf')
          .writeAsBytesSync(await gerarEtiquetasPdf(
              etiquetasDosVolumes(
                  _dados(),
                  const VolumesPedido(solto: false, volumes: [
                    Volume(caixa: true, tipoNome: 'Copo', itens: [
                      ItemVolume(nome: 'Produto de teste 1', quantidade: 20),
                    ]),
                    Volume(caixa: true, tipoNome: 'Copo', itens: [
                      ItemVolume(nome: 'Produto de teste 1', quantidade: 5),
                      ItemVolume(nome: 'Produto de teste 2', quantidade: 15),
                    ]),
                    Volume(caixa: false, tipoNome: null, itens: [
                      ItemVolume(nome: 'Produto de teste 3', quantidade: 2),
                    ]),
                  ])),
              TamanhoEtiqueta.m100x100,
              logo: logo));
      File('${dir.path}/qr.png').writeAsBytesSync(
          img.encodePng(rasterizar(conteudoQrEntrega(_uuids.first))));
      for (final n in [
        'etiqueta_100x100.pdf',
        'etiqueta_100x150.pdf',
        'etiqueta_60x40_muitos_itens.pdf',
        'etiqueta_volumes_100x100.pdf',
        'qr.png'
      ]) {
        expect(File('${dir.path}/$n').existsSync(), isTrue);
      }
    }, tags: ['amostra']);
  });
}
