// test/entrega_qr_test.dart
//
// Fase B no app: `codigo_qr` no SQLite (v19), a decisão depois de ler a
// etiqueta e as chamadas das RPCs de entrega por QR.
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/entrega_qr.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

const _qrA = '0b7e3c1a-5d2f-4c8e-9a41-6f3b2d7e8c90';
const _qrB = '11111111-2222-4333-8444-555555555555';

Future<String> _caminhoDb() async =>
    join(await databaseFactory.getDatabasesPath(), 'milkdim.db');

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory.deleteDatabase(await _caminhoDb());
}

Future<Map<String, dynamic>> _linha(int id) async {
  final db = await getDb();
  return Map<String, dynamic>.from(
      (await db.query('pedidos', where: 'id = ?', whereArgs: [id])).single);
}

Map<String, dynamic> _remoto({int id = 42, String numero = '70', String? codigoQr = _qrA}) => {
      'id': id,
      'numero': numero,
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor',
      'datahora': '2026-11-24T09:00:00+00:00',
      'total': 10.0,
      'cliente_id': 7,
      'cliente_nome': 'Padaria Teste',
      'produtos': [
        {'nome': 'Pudim', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
      ],
      'id_aparelho': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'enviado_em': '2026-11-24T09:00:01+00:00',
      'finalizado_manual': false,
      if (codigoQr != null) 'codigo_qr': codigoQr,
    };

/// Esquema v18 escrito à mão, para o upgrade real rodar.
Future<void> _criarSchemaV18(Database db, int _) async {
  await db.execute(
      'CREATE TABLE vendedores (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT UNIQUE, nome TEXT, ativo INTEGER);');
  await db.execute('''
    CREATE TABLE clientes (
      id INTEGER PRIMARY KEY, nome TEXT, nome_fantasia TEXT, cpf_cnpj TEXT,
      telefone TEXT, whatsapp TEXT, email TEXT, endereco TEXT, cidade TEXT,
      anotacao TEXT, ativo INTEGER, datahora TEXT, insc_estadual TEXT, cep TEXT
    );
  ''');
  await db.execute(
      'CREATE TABLE produtos (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, nome TEXT, unidade TEXT, preco REAL, ativo INTEGER);');
  await db.execute('''
    CREATE TABLE pedidos (
      id INTEGER PRIMARY KEY AUTOINCREMENT, numero TEXT, produtos TEXT,
      total REAL, status TEXT, datahora TEXT, vendedor_codigo TEXT,
      vendedor_nome TEXT, cliente_id INTEGER, cliente_nome TEXT,
      assinatura TEXT, assinatura_path TEXT, cliente_telefone TEXT,
      cliente_endereco TEXT, cliente_cidade TEXT, cliente_cpf_cnpj TEXT,
      cliente_insc_estadual TEXT, cliente_cep TEXT, cliente_anotacao TEXT,
      cliente_nome_fantasia TEXT, cliente_whatsapp TEXT, cliente_email TEXT,
      pendente_envio INTEGER NOT NULL DEFAULT 0,
      id_aparelho TEXT,
      so_local INTEGER NOT NULL DEFAULT 0,
      erro_envio TEXT,
      enviado_em TEXT, alterado_em TEXT, finalizado_em TEXT, finalizado_por TEXT,
      finalizado_manual TEXT, cancelado_em TEXT, cancelado_por TEXT,
      assinatura_pedido TEXT, assinatura_pedido_path TEXT,
      pronto_em TEXT, pronto_por TEXT
    );
  ''');
  await db.execute('''
    CREATE TABLE pedidos_descartados (
      id INTEGER PRIMARY KEY AUTOINCREMENT, descartado_em TEXT, motivo TEXT,
      pedido_json TEXT
    );
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await _limpar();
  });

  tearDownAll(_limpar);

  test('banco v18 sobe para v19 com codigo_qr e sem perder pedidos', () async {
    final v18 = await databaseFactory.openDatabase(await _caminhoDb(),
        options: OpenDatabaseOptions(version: 18, onCreate: _criarSchemaV18));
    await v18.insert('pedidos', {
      'id': 42,
      'numero': '70',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'pendente_envio': 1,
      'enviado_em': '2026-11-24T09:00:01+00:00',
    });
    await v18.insert('pedidos', {
      'id': kLocalIdBase + 1,
      'numero': '71',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'so_local': 1,
    });
    await v18.close();

    final db = await getDb();
    expect(await db.getVersion(), 19);
    final cols = (await db.rawQuery('PRAGMA table_info(pedidos)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(cols, contains('codigo_qr'));
    final idx = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_pedidos_codigo_qr'");
    expect(idx, hasLength(1));
    expect((await db.query('pedidos')).length, 2);
    expect((await _linha(42))['pendente_envio'], 1);
    expect((await _linha(kLocalIdBase + 1))['so_local'], 1);
    expect((await _linha(42))['codigo_qr'], isNull);
  });

  test('sincronização grava codigo_qr do servidor', () async {
    await aplicarPedidosRemotos([_remoto()]);
    expect((await _linha(42))['codigo_qr'], _qrA);
  });

  test('eco do envio grava codigo_qr', () async {
    final enviado = {
      'id': kLocalIdBase + 5,
      'numero': '70',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-24T09:00:00+00:00',
      'total': 10.0,
      'cliente_nome': 'Padaria Teste',
      'produtos': _remoto()['produtos'],
    };
    await salvarPedidoLocal(enviado);
    final r = await aplicarEcoDoServidor(enviado: enviado, remoto: _remoto());
    expect(r, ResultadoEco.aplicado);
    expect((await _linha(42))['codigo_qr'], _qrA);
  });

  test('montarPayloadPedido nunca leva codigo_qr', () {
    final payload = montarPayloadPedido({..._remoto(), 'codigo_qr': _qrA});
    expect(payload.containsKey('codigo_qr'), isFalse);
  });

  group('decidirDestinoDaLeitura', () {
    test('QR inválido dá QrInvalido', () async {
      var consultou = false;
      final d = await decidirDestinoDaLeitura('http://exemplo.com',
          vendedorCodigo: '0003', internet: () async {
        consultou = true;
        return true;
      });
      expect(d, isA<QrInvalido>());
      expect(consultou, isFalse);
    });

    test('código de pedido local abre o pedido local, mesmo com pendente_envio = 1',
        () async {
      await aplicarPedidosRemotos([_remoto()]);
      final db = await getDb();
      await db.update('pedidos', {'pendente_envio': 1}, where: 'id = 42');
      final d = await decidirDestinoDaLeitura('MILKDIM:E:${_qrA.toUpperCase()}',
          vendedorCodigo: '0003', internet: () async => false);
      expect(d, isA<AbrirPedidoLocal>());
      expect((d as AbrirPedidoLocal).pedido['id'], 42);
      expect(d.pedido['numero'], '70');
    });

    test('código desconhecido com internet vai ao servidor; sem internet dá SemInternet',
        () async {
      await aplicarPedidosRemotos([_remoto()]);
      final com = await decidirDestinoDaLeitura('MILKDIM:E:$_qrB',
          vendedorCodigo: '0003', internet: () async => true);
      expect(com, isA<AbrirEntregaServidor>());
      expect((com as AbrirEntregaServidor).codigoQr, _qrB);
      final sem = await decidirDestinoDaLeitura('MILKDIM:E:$_qrB',
          vendedorCodigo: '0003', internet: () async => false);
      expect(sem, isA<SemInternet>());
    });

    test('pedido no celular de outro vendedor vai ao servidor; sem internet dá SemInternet',
        () async {
      // O pedido 42 é do vendedor 0003; quem lê é o 0004 no mesmo celular.
      await aplicarPedidosRemotos([_remoto()]);
      final com = await decidirDestinoDaLeitura('MILKDIM:E:$_qrA',
          vendedorCodigo: '0004', internet: () async => true);
      expect(com, isA<AbrirEntregaServidor>());
      expect((com as AbrirEntregaServidor).codigoQr, _qrA);
      final sem = await decidirDestinoDaLeitura('MILKDIM:E:$_qrA',
          vendedorCodigo: '0004', internet: () async => false);
      expect(sem, isA<SemInternet>());
      // O dono continua abrindo o pedido local.
      final dono = await decidirDestinoDaLeitura('MILKDIM:E:$_qrA',
          vendedorCodigo: '0003', internet: () async => true);
      expect(dono, isA<AbrirPedidoLocal>());
      expect((dono as AbrirPedidoLocal).pedido['id'], 42);
    });

    test('sem vendedor logado nada abre como local', () async {
      await aplicarPedidosRemotos([_remoto()]);
      expect(await buscarPedidoLocalPorCodigoQr(_qrA, ''), isNull);
      final d = await decidirDestinoDaLeitura('MILKDIM:E:$_qrA',
          vendedorCodigo: '', internet: () async => true);
      expect(d, isA<AbrirEntregaServidor>());
    });
  });

  test('mensagemErroEntregaQr mapeia P0002, MD002, MD003, MD004 e o resto', () {
    expect(mensagemErroEntregaQr('P0002'), 'Pedido não encontrado.');
    expect(mensagemErroEntregaQr('MD002'), 'Este pedido já foi entregue.');
    expect(mensagemErroEntregaQr('MD003'), 'Este pedido ainda não está pronto para entrega.');
    expect(mensagemErroEntregaQr('MD004'), 'Este pedido foi cancelado.');
    const geral = 'Não deu para confirmar a entrega. Leia a etiqueta de novo.';
    expect(mensagemErroEntregaQr(null), geral);
    expect(mensagemErroEntregaQr('55000'), geral);
    expect(mensagemErroEntregaQr('42501'), geral);
  });

  test('PedidoQr.motivoSemEntrega', () {
    PedidoQr p(String status, bool proprio) => PedidoQr.fromJson({
          'id': 1,
          'numero': '70',
          'status': status,
          'vendedor_codigo': '0003',
          'vendedor_nome': 'Vendedor',
          'cliente_nome': 'Padaria Teste',
          'cliente_nome_fantasia': null,
          'cliente_cidade': 'Cidade',
          'itens': [
            {'nome': 'Pudim', 'quantidade': 2},
          ],
          'do_proprio_vendedor': proprio,
        });
    expect(p('pronto', false).motivoSemEntrega, isNull);
    expect(p('salvo', false).motivoSemEntrega,
        'Este pedido ainda não está pronto para entrega.');
    expect(p('salvo', true).motivoSemEntrega, isNull);
    expect(p('finalizado', true).motivoSemEntrega, 'Este pedido já foi entregue.');
    expect(p('cancelado', false).motivoSemEntrega, 'Este pedido foi cancelado.');
  });

  test('PedidoQr.fromJson: título do cliente e forma reduzida', () {
    final a = PedidoQr.fromJson({
      'id': 1,
      'numero': '70',
      'status': 'pronto',
      'cliente_nome': 'Cliente Teste',
      'cliente_nome_fantasia': 'Padaria Teste',
      'itens': [
        {'nome': 'Pudim', 'quantidade': 2},
      ],
    });
    expect(a.clienteTitulo, 'Padaria Teste');
    expect(a.itens.single.nome, 'Pudim');
    expect(a.itens.single.quantidade, 2);
    final b = PedidoQr.fromJson({
      'id': 1,
      'numero': '70',
      'status': 'pronto',
      'cliente_nome': 'Cliente Teste',
      'cliente_nome_fantasia': ''
    });
    expect(b.clienteTitulo, 'Cliente Teste');
    final c = PedidoQr.fromJson({'numero': '71', 'status': 'finalizado'});
    expect(c.numero, '71');
    expect(c.itens, isEmpty);
    expect(c.doProprioVendedor, isFalse);
    expect(c.motivoSemEntrega, 'Este pedido já foi entregue.');
  });

  group('RPCs', () {
    final entregarOriginal = rpcEntregarPorQr;
    final buscaOriginal = rpcPedidoPorQr;
    tearDown(() {
      rpcEntregarPorQr = entregarOriginal;
      rpcPedidoPorQr = buscaOriginal;
    });

    test('entregarPorQr envia a assinatura como \\x + hex', () async {
      String? codigo;
      String? assinatura;
      rpcEntregarPorQr = (c, a) async {
        codigo = c;
        assinatura = a;
        return {'id': 42, 'numero': '70', 'finalizado_em': '2026-11-24T10:00:00+00:00'};
      };
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x01, 0xab]);
      await entregarPorQr(_qrA, png);
      expect(codigo, _qrA);
      expect(assinatura, '\\x${cvt.hex.encode(png)}');
      expect(assinatura, startsWith(r'\x'));
    });

    test('entregarPorQr traduz erro do servidor em FalhaEntregaQr', () async {
      rpcEntregarPorQr =
          (c, a) async => throw const PostgrestException(message: 'x', code: 'MD002');
      await expectLater(
          entregarPorQr(_qrA, Uint8List.fromList([1])),
          throwsA(isA<FalhaEntregaQr>()
              .having((e) => e.mensagem, 'mensagem', 'Este pedido já foi entregue.')));
      rpcEntregarPorQr = (c, a) async => throw Exception('rede');
      await expectLater(
          entregarPorQr(_qrA, Uint8List.fromList([1])),
          throwsA(isA<FalhaEntregaQr>().having((e) => e.mensagem, 'mensagem',
              'Não deu para confirmar a entrega. Leia a etiqueta de novo.')));
    });

    test('buscarPedidoPorQr devolve o PedidoQr e traduz P0002', () async {
      rpcPedidoPorQr = (c) async => {'numero': '70', 'status': 'finalizado'};
      final p = await buscarPedidoPorQr(_qrA);
      expect(p.numero, '70');
      rpcPedidoPorQr =
          (c) async => throw const PostgrestException(message: 'x', code: 'P0002');
      await expectLater(
          buscarPedidoPorQr(_qrA),
          throwsA(isA<FalhaEntregaQr>()
              .having((e) => e.mensagem, 'mensagem', 'Pedido não encontrado.')));
    });
  });
}
