import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'qr_arredondado.dart';
import 'tamanho_etiqueta.dart';
import 'volumes.dart';

const _logoAsset = 'packages/milkdim_ui/assets/logo.jpg';

/// Dados impressos na etiqueta de um pedido pronto.
class EtiquetaDados {
  const EtiquetaDados({
    required this.numero,
    required this.clienteTitulo,
    required this.cidade,
    required this.vendedor,
    required this.itens,
    required this.prontoEm,
    required this.codigoQr,
    this.endereco = '',
    this.cep = '',
    this.telefone = '',
    this.volume = '',
  });

  final int numero;

  /// Nome fantasia ou, na falta, o nome do cliente.
  final String clienteTitulo;
  final String cidade;

  /// Nome do vendedor do pedido (o código, se o pedido não tem o nome).
  final String vendedor;
  final List<({String nome, int quantidade})> itens;
  final DateTime? prontoEm;
  final String codigoQr;

  /// Contato para a entrega; vazio quando o cliente não tem.
  final String endereco, cep, telefone;

  /// Rótulo do volume ("Caixa 1/3 · Copo"); vazio quando a etiqueta é única.
  /// Sai em destaque logo abaixo de "Pedido N", em todas as páginas.
  final String volume;
}

/// Uma etiqueta por volume: copia [base] (cliente, endereço, vendedor, QR),
/// troca os itens pelos do volume e preenche o rótulo.
List<EtiquetaDados> etiquetasDosVolumes(EtiquetaDados base, VolumesPedido v) =>
    [
      for (var i = 0; i < v.volumes.length; i++)
        EtiquetaDados(
          numero: base.numero,
          clienteTitulo: base.clienteTitulo,
          cidade: base.cidade,
          vendedor: base.vendedor,
          itens: [
            for (final it in v.volumes[i].itens)
              (nome: it.nome, quantidade: it.quantidade)
          ],
          prontoEm: base.prontoEm,
          codigoQr: base.codigoQr,
          endereco: base.endereco,
          cep: base.cep,
          telefone: base.telefone,
          volume: rotuloVolume(v, i),
        ),
    ];

/// Linhas do bloco "Entregar em", ao lado do QR (só nas etiquetas de 100 mm).
/// Linha sem dado não aparece; sem endereço, CEP nem telefone, o bloco some.
/// CPF/CNPJ, e-mail e anotação ficam de fora: a etiqueta fica à vista no
/// pacote.
List<String> linhasEntrega(EtiquetaDados d) {
  final endereco = d.endereco.trim();
  final cep = _textoCep(d.cep);
  final telefone = d.telefone.trim();
  if (endereco.isEmpty && cep.isEmpty && telefone.isEmpty) return const [];
  return [
    'Entregar em',
    if (endereco.isNotEmpty) endereco,
    if (cep.isNotEmpty) 'CEP $cep',
    if (telefone.isNotEmpty) 'Tel. $telefone',
  ];
}

/// CEP sem o prefixo "CEP" que às vezes vem digitado; 8 dígitos saem como
/// 00000-000, o resto como foi cadastrado.
String _textoCep(String bruto) {
  final s = bruto
      .trim()
      .replaceFirst(RegExp(r'^cep\s*:?\s*', caseSensitive: false), '');
  final digitos = s.replaceAll(RegExp(r'\D'), '');
  if (digitos.length == 8) {
    return '${digitos.substring(0, 5)}-${digitos.substring(5)}';
  }
  return s;
}

/// Texto de "Pronto em" na hora local. O `pronto_em` vem do PostgREST com
/// `+00:00` e o `Pedido` o lê em UTC: sem `toLocal()` a etiqueta sairia com a
/// hora de Greenwich.
String textoProntoEm(DateTime prontoEm) =>
    DateFormat('dd/MM HH:mm').format(prontoEm.toLocal());

/// Medidas de cada tamanho. Tudo em pontos (1 mm = 72/25,4 pt).
class _Medidas {
  const _Medidas({
    required this.margemMm,
    required this.qrMm,
    required this.fonteCabecalho,
    required this.fonteCliente,
    required this.fontePequena,
    required this.fonteItemMax,
    required this.qrLateral,
  });

  final double margemMm;

  /// Lado do QR com a margem branca.
  final double qrMm;
  final double fonteCabecalho, fonteCliente, fontePequena, fonteItemMax;

  /// QR ao lado da lista (etiqueta pequena) em vez de embaixo.
  final bool qrLateral;
}

const _fonteItemMin = 7.0;
const _alturaLinha = 1.25; // altura da linha de item, em múltiplos da fonte
const _alturaTexto = 1.3;
const _gapMm = 1.5;

const _medidas = {
  TamanhoEtiqueta.m100x100: _Medidas(
    margemMm: 4,
    qrMm: 38,
    fonteCabecalho: 14,
    fonteCliente: 12,
    fontePequena: 9,
    fonteItemMax: 11,
    qrLateral: false,
  ),
  TamanhoEtiqueta.m100x150: _Medidas(
    margemMm: 5,
    qrMm: 44,
    fonteCabecalho: 16,
    fonteCliente: 13,
    fontePequena: 10,
    fonteItemMax: 12,
    qrLateral: false,
  ),
  TamanhoEtiqueta.m60x40: _Medidas(
    margemMm: 2,
    qrMm: 22,
    fonteCabecalho: 8,
    fonteCliente: 7.5,
    fontePequena: 6.5,
    fonteItemMax: 7,
    qrLateral: true,
  ),
};

double _pt(double mm) => mm * PdfPageFormat.mm;

/// Altura disponível para a lista de itens em cada página.
///
/// [comVolume]: o rótulo do volume ocupa uma linha a mais no cabeçalho.
double _alturaItens(TamanhoEtiqueta t, {bool comVolume = false}) {
  final m = _medidas[t]!;
  final util = _pt(t.alturaMm) - 2 * _pt(m.margemMm);
  final topo = m.fonteCabecalho * _alturaTexto +
      m.fonteCliente * _alturaTexto +
      m.fontePequena * _alturaTexto +
      (comVolume ? _alturaVolume(m) : 0) +
      2 * _pt(_gapMm);
  final total = m.fontePequena * 1.4;
  final base = m.qrLateral ? 0.0 : _pt(m.qrMm) + _pt(_gapMm);
  return util - topo - total - base;
}

/// Rodapé das etiquetas que passam de uma página: "Folha 1/2" quando é um
/// volume (para não confundir com a contagem de caixas, "Caixa 1/3"), "1/2"
/// na etiqueta única. Null quando cabe numa página só.
String? rodapeDaPagina(
    {required bool comVolume, required int pagina, required int total}) {
  if (total <= 1) return null;
  return comVolume ? 'Folha $pagina/$total' : '$pagina/$total';
}

/// Altura da linha do rótulo do volume (mesma fonte do nome do cliente).
double _alturaVolume(_Medidas m) => m.fonteCliente * _alturaTexto;

/// Quantos itens cabem numa página na fonte mínima.
int _capacidade(TamanhoEtiqueta t, {bool comVolume = false}) => math.max(
    1,
    (_alturaItens(t, comVolume: comVolume) / (_fonteItemMin * _alturaLinha))
        .floor());

/// Índices dos itens de cada página da etiqueta. Sempre há ao menos uma
/// página, mesmo sem itens.
List<List<int>> paginarItens(int totalItens, TamanhoEtiqueta t,
    {bool comVolume = false}) {
  final cap = _capacidade(t, comVolume: comVolume);
  if (totalItens <= 0) return [<int>[]];
  return [
    for (var i = 0; i < totalItens; i += cap)
      [for (var j = i; j < math.min(i + cap, totalItens); j++) j],
  ];
}

/// Limiar de Otsu sobre o histograma de luminância (0-255).
int _limiarOtsu(List<int> hist, int total) {
  var somaTotal = 0.0;
  for (var i = 0; i < 256; i++) {
    somaTotal += i * hist[i];
  }
  var somaFundo = 0.0, pesoFundo = 0;
  var melhor = 128;
  var maiorVar = -1.0;
  for (var i = 0; i < 256; i++) {
    pesoFundo += hist[i];
    if (pesoFundo == 0) continue;
    final pesoFrente = total - pesoFundo;
    if (pesoFrente == 0) break;
    somaFundo += i * hist[i];
    final mF = somaFundo / pesoFundo;
    final mT = (somaTotal - somaFundo) / pesoFrente;
    final v = pesoFundo * pesoFrente * (mF - mT) * (mF - mT);
    if (v > maiorVar) {
      maiorVar = v;
      melhor = i;
    }
  }
  return melhor;
}

/// Logo em preto e branco puro: limiar de Otsu (separa o traço do fundo
/// colorido), recorte no traço e quadrado branco em volta.
Uint8List? _logoPretoEBranco(Uint8List bytes) {
  final origem = img.decodeImage(bytes);
  if (origem == null) return null;
  final w0 = origem.width, h0 = origem.height;
  final lum = List<int>.filled(w0 * h0, 255);
  final hist = List<int>.filled(256, 0);
  for (var y = 0; y < h0; y++) {
    for (var x = 0; x < w0; x++) {
      final p = origem.getPixel(x, y);
      final a = p.a / p.maxChannelValue;
      final l = ((0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * a + 255 * (1 - a))
          .round()
          .clamp(0, 255);
      lum[y * w0 + x] = l;
      hist[l]++;
    }
  }
  final limiar = _limiarOtsu(hist, w0 * h0);
  // Traço = lado escuro do limiar.
  var x0 = w0, y0 = h0, x1 = -1, y1 = -1;
  for (var y = 0; y < h0; y++) {
    for (var x = 0; x < w0; x++) {
      if (lum[y * w0 + x] <= limiar) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  const lado = 256;
  const miolo = 236; // folga branca de 10 px em volta
  final escala = miolo / math.max(cw, ch);
  final w = math.max(1, (cw * escala).round());
  final h = math.max(1, (ch * escala).round());
  final saida = img.Image(width: lado, height: lado, numChannels: 3);
  img.fill(saida, color: img.ColorRgb8(255, 255, 255));
  final dx = (lado - w) ~/ 2, dy = (lado - h) ~/ 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final int sx = x0 + math.min(cw - 1, (x / escala).floor());
      final int sy = y0 + math.min(ch - 1, (y / escala).floor());
      final v = lum[sy * w0 + sx] <= limiar ? 0 : 255;
      saida.setPixelRgb(dx + x, dy + y, v, v, v);
    }
  }
  return img.encodePng(saida);
}

Future<Uint8List?> _carregarLogo() async {
  try {
    return (await rootBundle.load(_logoAsset)).buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// NotoSans do pacote de UI, compartilhada com o relatório (acentos e "×"
/// corretos no PDF). Sem o asset, cai na Helvetica embutida do PDF.
Future<pw.Font> carregarFonte(String arquivo, pw.Font reserva) async {
  try {
    final dados = await rootBundle.load('packages/milkdim_ui/fonts/$arquivo');
    return pw.Font.ttf(dados);
  } catch (_) {
    return reserva;
  }
}

/// Gera a etiqueta em PDF no tamanho do rolo.
///
/// [logo] são os bytes da imagem do logo; sem ele, o logo de
/// `packages/milkdim_ui/assets/logo.jpg` é lido do bundle de assets. Se não
/// houver logo, o QR sai com o centro em branco.
Future<Uint8List> gerarEtiquetaPdf(
  EtiquetaDados d,
  TamanhoEtiqueta t, {
  Uint8List? logo,
}) =>
    gerarEtiquetasPdf([d], t, logo: logo);

/// Um PDF com as páginas de cada etiqueta de [volumes], em ordem. Logo e
/// fontes são carregados uma vez só.
Future<Uint8List> gerarEtiquetasPdf(
  List<EtiquetaDados> volumes,
  TamanhoEtiqueta t, {
  Uint8List? logo,
}) async {
  if (volumes.isEmpty) throw ArgumentError('volumes vazio');
  final m = _medidas[t]!;
  final logoBytes = logo ?? await _carregarLogo();
  final logoPb = logoBytes == null ? null : _logoPretoEBranco(logoBytes);

  final negrito =
      await carregarFonte('NotoSans-Bold.ttf', pw.Font.helveticaBold());
  final normal =
      await carregarFonte('NotoSans-Regular.ttf', pw.Font.helvetica());
  final formato = PdfPageFormat(_pt(t.larguraMm), _pt(t.alturaMm));
  final doc = pw.Document(title: 'Etiqueta do pedido ${volumes.first.numero}');

  pw.Widget linha(double fonte, String texto,
      {bool bold = false, double? altura}) {
    return pw.SizedBox(
      height: altura ?? fonte * _alturaTexto,
      // Texto vazio tem largura 0 e o FittedBox recusa (assert do pdf).
      child: texto.isEmpty
          ? null
          : pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                texto,
                style: pw.TextStyle(
                    font: bold ? negrito : normal, fontSize: fonte),
              ),
            ),
    );
  }

  // Dois textos nas pontas da linha; cada um encolhe se não couber.
  pw.Widget duasPontas(double fonte, String esq, String dir,
      {bool bold = false}) {
    pw.Widget texto(String t, pw.Alignment al) => pw.Flexible(
          child: t.isEmpty
              ? pw.SizedBox()
              : pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: al,
                  child: pw.Text(t,
                      style: pw.TextStyle(
                          font: bold ? negrito : normal, fontSize: fonte)),
                ),
        );
    return pw.SizedBox(
      height: fonte * _alturaTexto,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          texto(esq, pw.Alignment.centerLeft),
          pw.SizedBox(width: 4),
          texto(dir, pw.Alignment.centerRight),
        ],
      ),
    );
  }

  pw.Widget separador() => pw.Container(
        height: _pt(_gapMm),
        alignment: pw.Alignment.center,
        child: pw.Container(height: 0.6, color: PdfColors.black),
      );

  pw.Widget qr(double ladoPt, GeometriaQr geom) {
    final escala = ladoPt / (geom.modulos + 2 * margemQrModulos);
    final logoLado = geom.areaLogo.lado * escala;
    final pad = 0.5 * escala;
    return pw.SizedBox(
      width: ladoPt,
      height: ladoPt,
      child: pw.Stack(children: [
        pw.Positioned.fill(
          child: pw.CustomPaint(
            size: PdfPoint(ladoPt, ladoPt),
            painter: (canvas, size) {
              canvas.setFillColor(PdfColors.black);
              // No PDF o eixo y cresce para cima.
              double y(double v, double h) => size.y - (v + h) * escala;
              for (final f in geom.formas) {
                final r = f.raio * escala;
                canvas.drawRRect(f.x * escala, y(f.y, f.altura),
                    f.largura * escala, f.altura * escala, r, r);
                if (f.anel) {
                  final ri = math.max(f.raio - 1, 0) * escala;
                  canvas.drawRRect(
                      (f.x + 1) * escala,
                      y(f.y + 1, f.altura - 2),
                      (f.largura - 2) * escala,
                      (f.altura - 2) * escala,
                      ri,
                      ri);
                  canvas.fillPath(evenOdd: true);
                } else {
                  canvas.fillPath();
                }
              }
              // Área do logo em branco puro.
              canvas.setFillColor(PdfColors.white);
              canvas.drawRect(geom.areaLogo.x * escala,
                  y(geom.areaLogo.y, geom.areaLogo.lado), logoLado, logoLado);
              canvas.fillPath();
            },
          ),
        ),
        if (logoPb != null)
          pw.Positioned(
            left: geom.areaLogo.x * escala + pad,
            top: geom.areaLogo.y * escala + pad,
            child: pw.Image(
              pw.MemoryImage(logoPb),
              width: logoLado - 2 * pad,
              height: logoLado - 2 * pad,
            ),
          ),
      ]),
    );
  }

  for (final d in volumes) {
    final geom = geometriaQrArredondado(conteudoQrEntrega(d.codigoQr));
    final comVolume = d.volume.trim().isNotEmpty;
    final alturaItens = _alturaItens(t, comVolume: comVolume);
    final paginas = paginarItens(d.itens.length, t, comVolume: comVolume);
    final total = d.itens.fold<int>(0, (s, i) => s + i.quantidade);
    final prontoEm = d.prontoEm == null ? null : textoProntoEm(d.prontoEm!);
    final entrega = linhasEntrega(d);

    for (var p = 0; p < paginas.length; p++) {
      final idx = paginas[p];
      final fonteItem = idx.isEmpty
          ? m.fonteItemMax
          : math.max(
              _fonteItemMin,
              math.min(
                  m.fonteItemMax, alturaItens / (idx.length * _alturaLinha)));
      final rodapePagina = rodapeDaPagina(
          comVolume: comVolume, pagina: p + 1, total: paginas.length);

      final lista = pw.SizedBox(
        height: alturaItens,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final i in idx)
              linha(fonteItem, '${d.itens[i].quantidade}×  ${d.itens[i].nome}',
                  altura: fonteItem * _alturaLinha),
          ],
        ),
      );

      final infoQr = pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Na 60x40 a coluna é só a largura do QR: o endereço não cabe.
          if (!m.qrLateral && entrega.isNotEmpty) ...[
            linha(m.fontePequena, entrega.first),
            for (final l in entrega.skip(1))
              linha(m.fontePequena, l, bold: true),
            pw.SizedBox(height: _pt(1)),
          ],
          if (prontoEm != null) ...[
            pw.Text('Pronto em',
                style: pw.TextStyle(font: normal, fontSize: m.fontePequena)),
            pw.Text(prontoEm,
                style: pw.TextStyle(font: negrito, fontSize: m.fontePequena)),
          ],
          if (rodapePagina != null)
            pw.Text(rodapePagina,
                style: pw.TextStyle(font: normal, fontSize: m.fontePequena)),
        ],
      );

      final cabecalho = <pw.Widget>[
        duasPontas(m.fonteCabecalho, 'MILKDIM', 'Pedido ${d.numero}',
            bold: true),
        if (comVolume) linha(m.fonteCliente, d.volume.trim(), bold: true),
        linha(m.fonteCliente, d.clienteTitulo, bold: true),
        duasPontas(m.fontePequena, d.cidade,
            d.vendedor.isEmpty ? '' : 'Vendedor ${d.vendedor}'),
        separador(),
      ];

      final totalLinha = linha(m.fontePequena, 'Total: $total unidades',
          bold: true, altura: m.fontePequena * 1.4);

      final qrPt = _pt(m.qrMm);
      final pw.Widget conteudo;
      if (m.qrLateral) {
        // Etiqueta pequena: texto à esquerda, QR e "Pronto em" à direita.
        conteudo = pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [...cabecalho, lista, totalLinha],
              ),
            ),
            pw.SizedBox(width: _pt(_gapMm)),
            pw.SizedBox(
              width: qrPt,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [qr(qrPt, geom), infoQr],
              ),
            ),
          ],
        );
      } else {
        conteudo = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ...cabecalho,
            lista,
            totalLinha,
            separador(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                qr(qrPt, geom),
                pw.SizedBox(width: _pt(2)),
                pw.Expanded(child: infoQr),
              ],
            ),
          ],
        );
      }

      doc.addPage(pw.Page(
        pageFormat: formato,
        margin: pw.EdgeInsets.all(_pt(m.margemMm)),
        build: (_) => conteudo,
      ));
    }
  }

  return doc.save();
}
