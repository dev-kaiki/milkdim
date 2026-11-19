// lib/utils/pdf_utils.dart
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

import 'convert.dart'; // signatureToImageBytes, imageTypeFromBytes

/// Ative/desative logs desta unidade aqui:
const bool _kPdfDebug = true;

/// Gera o PDF do pedido em um Isolate.
/// - fontes Unicode via assets (NotoSans Regular/Bold/Itálico)
/// - assinatura como PNG/JPEG nos bytes (quando houver)
///
/// Uso:
/// final bytes = await gerarPdfPedido(
///   pedido: pedidoMap,
///   assinaturaBytes: assinaturaOpcional, // pode ser bytes, base64, hex, path, data-uri...
/// );
Future<Uint8List> gerarPdfPedido({
  required Map<String, dynamic> pedido,
  dynamic assinaturaBytes,
}) async {
  if (_kPdfDebug) {
    print('[PDF] gerarPdfPedido() - inicio | num=${pedido['numero']} id=${pedido['id']}');
  }

  // Carrega as fontes NO MAIN ISOLATE (rootBundle não funciona dentro do isolate).
  final fontBaseBytes =
  (await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')).buffer.asUint8List();
  final fontBoldBytes =
  (await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')).buffer.asUint8List();
  final fontItalicBytes =
  (await rootBundle.load('assets/fonts/NotoSans-Italic.ttf')).buffer.asUint8List();

  if (_kPdfDebug) {
    print('[PDF] fontes carregadas: '
        'base=${fontBaseBytes.length} bytes, '
        'bold=${fontBoldBytes.length} bytes, '
        'italic=${fontItalicBytes.length} bytes');
  }

  // Logo (opcional)
  Uint8List? logoBytes;
  try {
    logoBytes = (await rootBundle.load('assets/logo_circular.png')).buffer.asUint8List();
    if (_kPdfDebug) print('[PDF] logo carregado (${logoBytes.length} bytes)');
  } catch (e) {
    if (_kPdfDebug) print('[PDF] logo não encontrado: $e');
    logoBytes = null;
  }

  // Normaliza a assinatura AQUI (fora do isolate).
  final rawSig = assinaturaBytes ??
      pedido['assinatura_path'] ??
      pedido['assinatura'] ??
      pedido['assinatura_base64'] ??
      pedido['assinaturaBytes'] ??
      pedido['signature'] ??
      pedido['signature_base64'];

  final Uint8List? assinaturaPngBytes = signatureToImageBytes(rawSig);
  if (_kPdfDebug) {
    if (assinaturaPngBytes == null) {
      print('[PDF] assinatura: null/indisponível (raw=${rawSig?.runtimeType})');
    } else {
      print('[PDF] assinatura OK: ${assinaturaPngBytes.length} bytes '
          '(tipo=${imageTypeFromBytes(assinaturaPngBytes)})');
    }
  }

  final payload = <String, dynamic>{
    'pedido': Map<String, dynamic>.from(pedido),
    'fontBase': fontBaseBytes,
    'fontBold': fontBoldBytes,
    'fontItalic': fontItalicBytes,
    'logo': logoBytes,
    'assinatura': assinaturaPngBytes,
    '_debug': _kPdfDebug,
  };

  final bytes = await Isolate.run(() => _buildPdfBytes(payload));
  if (_kPdfDebug) print('[PDF] gerarPdfPedido() - fim | size=${bytes.length} bytes');
  return bytes;
}

// >>> async porque pdf.save() retorna Future<Uint8List>
Future<Uint8List> _buildPdfBytes(Map<String, dynamic> data) async {
  final pedido = Map<String, dynamic>.from(data['pedido'] as Map);

  final base = pw.Font.ttf((data['fontBase'] as Uint8List).buffer.asByteData());
  final bold = pw.Font.ttf((data['fontBold'] as Uint8List).buffer.asByteData());
  final italic = pw.Font.ttf((data['fontItalic'] as Uint8List).buffer.asByteData());

  final Uint8List? logoBytes = data['logo'] as Uint8List?;
  final Uint8List? assinaturaBytes = data['assinatura'] as Uint8List?;
  final bool dbg = (data['_debug'] as bool?) ?? false;

  if (dbg) {
    print('[PDF][isolate] construindo PDF | num=${pedido['numero']} id=${pedido['id']} '
        '| assinatura=${assinaturaBytes == null ? 'null' : '${assinaturaBytes.length} bytes'}');
  }

  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: italic, // 👈 garante itálico real (evita Helvetica-Oblique)
    ),
  );

  final pw.MemoryImage? logoImage =
  (logoBytes != null && logoBytes.isNotEmpty) ? pw.MemoryImage(logoBytes) : null;

  const milkdimInfo = <String>[
    'MilkDim Alimentos',
    'Cremoso Pudim',
    'CNPJ: 59.719.874/0001-46  I.E: 461.159.670.112',
    'Rua Dona Francisca, 485 - Jardim Tangará',
    'Monte Alto - SP CEP: 15910-000',
    'Tel: (16) 99706-6448',
    'contato@milkdim.com.br',
  ];

  final produtos = _safeListOfMaps(pedido['produtos']);
  final total = _asNum(pedido['total']).toDouble();
  final dataHora = pedido['datahora'] != null
      ? (DateTime.tryParse(pedido['datahora'].toString()) ?? DateTime.now())
      : DateTime.now();

  final clienteNome = _t(pedido['cliente_nome'] ?? '-');
  final clienteId = _t(pedido['cliente_id'] ?? '-');
  final clienteNomeFantasia = _t(pedido['cliente_nome_fantasia'] ?? '-');
  final clienteCpfCnpj = _t(pedido['cliente_cpf_cnpj'] ?? pedido['cpf_cnpj'] ?? '-');
  final clienteTelefone = _t(pedido['cliente_telefone'] ?? pedido['telefone'] ?? '-');
  final clienteWhatsapp = _t(pedido['cliente_whatsapp'] ?? pedido['whatsapp'] ?? '-');
  final clienteEmail = _t(pedido['cliente_email'] ?? pedido['email'] ?? '-');
  final clienteEndereco = _t(pedido['cliente_endereco'] ?? pedido['endereco'] ?? '-');
  final clienteCidade = _t(pedido['cliente_cidade'] ?? pedido['cidade'] ?? '-');
  final clienteInscEstadual =
  _t(pedido['cliente_insc_estadual'] ?? pedido['insc_estadual'] ?? '-');
  final clienteCep = _t(pedido['cliente_cep'] ?? pedido['cep'] ?? '-');
  final clienteAnotacao = _t(pedido['cliente_anotacao'] ?? pedido['anotacao'] ?? '-');

  final numeroPedido = _t(pedido['numero'] ?? '-');
  final vendedorNome = _t(pedido['vendedor_nome'] ?? '-');
  final vendedorCodigo = _t(pedido['vendedor_codigo'] ?? '-');

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Cabeçalho
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 70,
                  height: 70,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.orange400, width: 2.2),
                  ),
                  child: logoImage != null
                      ? pw.ClipOval(child: pw.Image(logoImage, fit: pw.BoxFit.cover))
                      : _logoFallback(),
                ),
                pw.SizedBox(width: 18),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      milkdimInfo[0],
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 19,
                        color: PdfColors.orange800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    pw.Text(
                      milkdimInfo[1],
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        color: PdfColors.orange600,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    ...milkdimInfo.sublist(2).map(
                          (e) => pw.Text(
                        e,
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfColors.orange700, thickness: 1.2),

            // Título/numero/data
            pw.Center(
              child: pw.Text(
                'PEDIDO DE VENDA',
                style: pw.TextStyle(
                  fontSize: 21,
                  color: PdfColors.orange900,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Nº Pedido: $numeroPedido',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13.8,
                  color: PdfColors.orange800,
                  letterSpacing: 1.3,
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Data/Hora: ${DateFormat('dd/MM/yyyy HH:mm').format(dataHora)}',
                style: const pw.TextStyle(fontSize: 12.5, color: PdfColors.orange700),
              ),
            ),
            pw.SizedBox(height: 12),

            // Blocos Cliente/Vendedor
            pw.Container(
              padding: const pw.EdgeInsets.all(13),
              decoration: pw.BoxDecoration(
                color: PdfColors.orange50,
                borderRadius: pw.BorderRadius.circular(14),
                border: pw.Border.all(color: PdfColors.orange100, width: 1.0),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 9,
                    child: pw.Wrap(
                      spacing: 18,
                      runSpacing: 1,
                      children: [
                        _small('Cliente: $clienteNome'),
                        _small('Fantasia: $clienteNomeFantasia'),
                        _small('Telefone: $clienteTelefone'),
                        _smallColor('WhatsApp: $clienteWhatsapp', PdfColors.green800),
                        _smallColor('Email: $clienteEmail', PdfColors.blue800),
                        _small('Endereço: $clienteEndereco'),
                        _small('Cidade: $clienteCidade'),
                        _small('CEP: $clienteCep'),
                        _small('CPF/CNPJ: $clienteCpfCnpj'),
                        _small('Insc. Estadual: $clienteInscEstadual'),
                        _small('Código/ID: $clienteId'),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 22),
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _small('Vendedor: $vendedorNome'),
                        _small('Código: $vendedorCodigo'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (clienteAnotacao.trim().isNotEmpty && clienteAnotacao.trim() != '-')
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange50,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.orange100, width: 1),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'OBSERVAÇÕES:',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Text(
                          clienteAnotacao,
                          style: const pw.TextStyle(fontSize: 11, color: PdfColors.orange800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            pw.SizedBox(height: 10),

            // Tabela Produtos
            pw.Text(
              'Produtos',
              style: pw.TextStyle(
                color: PdfColors.orange900,
                fontSize: 14.5,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.orange100, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(3),
                3: pw.FlexColumnWidth(3),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.orange50),
                  children: [
                    _th('Produto'),
                    _th('Qtd'),
                    _th('Valor Un.'),
                    _th('Subtotal'),
                  ],
                ),
                ...produtos.asMap().entries.map((entry) {
                  final i = entry.key;
                  final prod = entry.value;
                  final isEven = i % 2 == 0;
                  final nome = _t(prod['nome'] ?? '-');
                  final qtd = _t(prod['quantidade'] ?? '');
                  final preco = _asNum(prod['preco']).toStringAsFixed(2);
                  final subtotal = _asNum(prod['subtotal']).toStringAsFixed(2);
                  return pw.TableRow(
                    decoration:
                    pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.orange50),
                    children: [
                      _td(nome),
                      _tc(qtd),
                      _tc('R\$ $preco'),
                      _tc('R\$ $subtotal'),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange100,
                    borderRadius: pw.BorderRadius.circular(9),
                  ),
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 22),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'TOTAL: ',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 15,
                          color: PdfColors.orange900,
                        ),
                      ),
                      pw.Text(
                        'R\$ ${total.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16.5,
                          color: PdfColors.orange700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),
            pw.Divider(color: PdfColors.orange100, thickness: 0.8),

            // Assinatura
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Assinatura do Cliente:',
                      style: const pw.TextStyle(color: PdfColors.orange800, fontSize: 12),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      width: 220,
                      height: 84,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.orange300),
                        borderRadius: pw.BorderRadius.circular(6),
                        color: PdfColors.white,
                      ),
                      child: (assinaturaBytes != null && assinaturaBytes.isNotEmpty)
                          ? pw.Center(
                        child: pw.Image(
                          pw.MemoryImage(assinaturaBytes),
                          width: 210,
                          height: 74,
                          fit: pw.BoxFit.contain,
                        ),
                      )
                          : pw.Center(
                        child: pw.Text(
                          'Não assinada',
                          style: pw.TextStyle(
                            color: PdfColors.orange300,
                            fontStyle: pw.FontStyle.italic, // usa NotoSans-Italico.ttf
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Obrigado pela preferência!',
                  style: pw.TextStyle(
                    color: PdfColors.orange700,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 18),
            pw.Center(
              child: pw.Text(
                'MilkDim Alimentos • www.milkdim.com.br',
                style: pw.TextStyle(
                  fontSize: 10.8,
                  color: PdfColors.orange400,
                  fontStyle: pw.FontStyle.italic, // usa NotoSans-Italico.ttf
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  final out = await pdf.save();
  if (dbg) print('[PDF][isolate] pdf.save() -> ${out.length} bytes');
  return out;
}

// ----------------- Helpers -----------------

String _t(dynamic v) => (v ?? '').toString();

num _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.replaceAll(',', '.')) ?? 0;
  return 0;
}

List<Map<String, dynamic>> _safeListOfMaps(dynamic raw) {
  dynamic list = raw;
  if (raw is String) {
    try {
      list = jsonDecode(raw);
    } catch (_) {
      list = const [];
    }
  }
  if (list is! List) return <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in list) {
    if (item is Map) out.add(Map<String, dynamic>.from(item));
  }
  return out;
}

pw.Widget _th(String t) => pw.Padding(
  padding: const pw.EdgeInsets.all(6),
  child: pw.Center(
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.orange800,
        fontSize: 11.5,
      ),
    ),
  ),
);

pw.Widget _td(String t) =>
    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 11)));

pw.Widget _tc(String t) => pw.Center(child: pw.Text(t, style: const pw.TextStyle(fontSize: 10.5)));

pw.Widget _small(String t) => pw.Text(t, style: const pw.TextStyle(fontSize: 10.5));

pw.Widget _smallColor(String t, PdfColor color) =>
    pw.Text(t, style: pw.TextStyle(fontSize: 10.5, color: color));

pw.Widget _logoFallback() => pw.Container(
  decoration: const pw.BoxDecoration(color: PdfColors.orange100, shape: pw.BoxShape.circle),
  child: pw.Center(
    child: pw.Text(
      'MD',
      style: pw.TextStyle(
        color: PdfColors.orange800,
        fontWeight: pw.FontWeight.bold,
        fontSize: 22,
      ),
    ),
  ),
);
