// test/assinatura_envio_test.dart
//
// A assinatura colhida na tela chega ao servidor como bytea ('\x' + hex), nos
// envios e nos reenvios, e o que o servidor devolve ('\x...') é lido de volta.
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/convert.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

/// PNG mínimo (assinatura do arquivo + alguns bytes).
final Uint8List _png = Uint8List.fromList(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0xab, 0xcd, 0xef]);
final String _hex = cvt.hex.encode(_png); // minúsculo
final String _bytea = '\\x$_hex'; // como vai no JSON e como o PostgREST devolve

const _cliente = {
  'cliente_nome': 'Padaria Central',
  'cliente_nome_fantasia': '',
  'cliente_telefone': '',
  'cliente_whatsapp': '',
  'cliente_email': '',
  'cliente_endereco': '',
  'cliente_cidade': '',
  'cliente_cpf_cnpj': '',
  'cliente_insc_estadual': '',
  'cliente_cep': '',
  'cliente_anotacao': '',
};

const _itens = [
  {'nome': 'Pudim', 'preco': 10.0, 'quantidade': 2, 'subtotal': 20.0},
];

/// Pedido novo exatamente como a tela de pedido monta (finalizar com assinatura).
Map<String, dynamic> _pedidoNovoDaTela({
  required String numero,
  required String status,
  Uint8List? assinatura,
  String? caminho = '/sig/sig_1.png',
}) =>
    pedidoDaTela(
      base: {'vendedor_codigo': '0003', 'vendedor_nome': 'Vendedor'},
      numero: numero,
      produtos: [for (final i in _itens) Map<String, dynamic>.from(i)],
      total: 20.0,
      status: status,
      datahora: '2026-11-23T10:00:00.000Z',
      clienteId: null,
      cliente: _cliente,
      assinatura: assinatura,
      assinaturaPath: caminho,
    );

void main() {
  final buscaOriginal = buscarRemotoPorNumero;
  final gravarOriginal = gravarPedidoNoServidor;
  late List<Map<String, dynamic>> payloads;
  late List<int?> idsServidor;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('assinatura_envio_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await _limpar();
    payloads = [];
    idsServidor = [];
    buscarRemotoPorNumero = (n, v) async => null;
    // Servidor falso: devolve a linha como o PostgREST (bytea em '\x...').
    gravarPedidoNoServidor = (payload, {int? idServidor}) async {
      payloads.add(Map<String, dynamic>.from(payload));
      idsServidor.add(idServidor);
      return {
        ...payload,
        'id': idServidor ?? 100,
        'enviado_em': '2026-11-23T10:00:01+00:00',
        'finalizado_manual': false,
      };
    };
  });

  tearDown(() {
    buscarRemotoPorNumero = buscaOriginal;
    gravarPedidoNoServidor = gravarOriginal;
  });
  tearDownAll(_limpar);

  test('finalizar com assinatura na tela: payload leva bytea \\x + hex', () async {
    final pedido = _pedidoNovoDaTela(numero: '50', status: 'finalizado', assinatura: _png);

    final r = await gravarPedidoEEnviar(pedido, novo: true);

    expect(r, ResultadoGravacao.enviado);
    final p = payloads.single;
    expect(p['assinatura'], _bytea);
    expect((p['assinatura'] as String).startsWith(r'\x'), isTrue);
    expect(p.containsKey('assinatura_path'), isFalse, reason: 'caminho é só do aparelho');

    // O eco ('\x...') volta ao SQLite como os mesmos bytes.
    final db = await getDb();
    final l = (await db.query('pedidos', where: 'numero = ?', whereArgs: ['50'])).single;
    expect(l['id'], 100);
    expect(l['assinatura'], '0x$_hex');
    expect(assinaturaToBytes(l['assinatura']), _png);
    expect(l['assinatura_path'], '/sig/sig_1.png');
  });

  test('envio falhou: o reenvio leva a assinatura guardada no SQLite', () async {
    final ok = gravarPedidoNoServidor;
    gravarPedidoNoServidor = (payload, {int? idServidor}) async =>
        throw const SocketException('sem rede');
    final r = await gravarPedidoEEnviar(
        _pedidoNovoDaTela(numero: '51', status: 'finalizado', assinatura: _png),
        novo: true);
    expect(r, ResultadoGravacao.pendente);

    final db = await getDb();
    final l = (await db.query('pedidos', where: 'numero = ?', whereArgs: ['51'])).single;
    expect(l['assinatura'], '0x$_hex', reason: 'os bytes ficam no aparelho para o reenvio');

    gravarPedidoNoServidor = ok;
    final s = await subirPedidosPendentes(vendedorCodigo: '0003');
    expect(s.enviados, 1);
    expect(payloads.single['assinatura'], _bytea);
  });

  test('entrega na edicao de pedido aberto do servidor leva a assinatura', () async {
    // Pedido em aberto que veio do servidor (sem assinatura).
    await aplicarPedidosRemotos([
      {
        'id': 42,
        'numero': '52',
        'status': 'salvo',
        'vendedor_codigo': '0003',
        'datahora': '2026-11-23T09:00:00+00:00',
        'total': 20.0,
        'cliente_nome': 'Padaria Central',
        'produtos': _itens,
        'id_aparelho': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'enviado_em': '2026-11-23T09:00:01+00:00',
      },
    ]);
    final db = await getDb();
    final linha = Map<String, dynamic>.from(
        (await db.query('pedidos', where: 'id = ?', whereArgs: [42])).single);

    // Como a tela de edição monta ao finalizar com a assinatura colhida.
    final pedido = pedidoDaTela(
      base: linha,
      numero: '52',
      produtos: [for (final i in _itens) Map<String, dynamic>.from(i)],
      total: 20.0,
      status: 'finalizado',
      datahora: '2026-11-23T11:00:00.000Z',
      clienteId: null,
      cliente: _cliente,
      assinatura: _png,
      assinaturaPath: '/sig/sig_52.png',
    );
    final r = await gravarPedidoEEnviar(pedido, novo: false);

    expect(r, ResultadoGravacao.enviado);
    expect(idsServidor.single, 42, reason: 'UPDATE pelo id do servidor');
    expect(payloads.single['status'], 'finalizado');
    expect(payloads.single['assinatura'], _bytea);
  });

  test('pedido salvo so com o caminho da assinatura: o envio le o arquivo', () async {
    final dir = await Directory.systemTemp.createTemp('assinatura_arquivo');
    final arq = File(join(dir.path, 'sig_53.png'));
    await arq.writeAsBytes(_png);

    // Linha como as versões anteriores gravavam: só assinatura_path.
    final db = await getDb();
    await db.insert('pedidos', {
      'id': kLocalIdBase + 9,
      'numero': '53',
      'vendedor_codigo': '0003',
      'status': 'finalizado',
      'total': 20.0,
      'produtos': '[]',
      'datahora': '2026-11-20T10:00:00Z',
      'assinatura_path': arq.path,
      'pendente_envio': 1,
      'id_aparelho': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    });

    final s = await subirPedidosPendentes(vendedorCodigo: '0003');

    expect(s.enviados, 1);
    expect(payloads.single['assinatura'], _bytea);
    await dir.delete(recursive: true);
  });

  test('sem assinatura nem arquivo: payload sem a chave assinatura', () async {
    await gravarPedidoEEnviar(
        _pedidoNovoDaTela(numero: '54', status: 'salvo', caminho: null), novo: true);
    expect(payloads.single.containsKey('assinatura'), isFalse);
  });

  group('decodificacao do bytea', () {
    test('assinaturaToBytes le \\x + hex (formato do PostgREST)', () {
      expect(assinaturaToBytes(_bytea), _png);
      expect(signatureToImageBytes(_bytea), _png);
      expect(assinaturaParaBytea(_png), _bytea);
      expect(assinaturaParaBytea('0x$_hex'), _bytea);
      expect(assinaturaParaBytea(null), isNull);
    });

    test('bytea antigo gravado a partir de texto base64 ainda vira a imagem', () {
      // O servidor guardou os caracteres do base64; o PostgREST devolve o hex deles.
      const b64 = 'iVBORw0KGgo=';
      final hexDoTexto = cvt.hex.encode(b64.codeUnits);
      expect(signatureToImageBytes('\\x$hexDoTexto'),
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
    });

    test('sync grava no SQLite o bytea vindo do servidor', () async {
      await aplicarPedidosRemotos([
        {
          'id': 60,
          'numero': '60',
          'status': 'finalizado',
          'vendedor_codigo': '0003',
          'datahora': '2026-11-23T09:00:00+00:00',
          'total': 20.0,
          'produtos': _itens,
          'assinatura': _bytea,
          'enviado_em': '2026-11-23T09:00:01+00:00',
        },
      ]);
      final db = await getDb();
      final l = (await db.query('pedidos', where: 'id = ?', whereArgs: [60])).single;
      expect(l['assinatura'], '0x$_hex');
      expect(signatureToImageBytes(l['assinatura']), _png);
    });
  });
}
