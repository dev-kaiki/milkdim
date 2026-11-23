// test/fluxo_pedido_local_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/id_aparelho.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

Future<Map<String, Object?>> _linha(String numero) async {
  final db = await getDb();
  final r = await db.query('pedidos', where: 'numero = ?', whereArgs: [numero]);
  return r.single;
}

/// Esquema v16 escrito à mão (copiado do onCreate da v16), para o upgrade real rodar.
Future<void> _criarSchemaV16(Database db, int _) async {
  await db.execute('''
    CREATE TABLE vendedores (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigo TEXT UNIQUE,
      nome TEXT,
      ativo INTEGER
    );
  ''');
  await db.execute('''
    CREATE TABLE clientes (
      id INTEGER PRIMARY KEY, nome TEXT, nome_fantasia TEXT, cpf_cnpj TEXT,
      telefone TEXT, whatsapp TEXT, email TEXT, endereco TEXT, cidade TEXT,
      anotacao TEXT, ativo INTEGER, datahora TEXT, insc_estadual TEXT, cep TEXT
    );
  ''');
  await db.execute('''
    CREATE TABLE produtos (
      id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, nome TEXT,
      unidade TEXT, preco REAL, ativo INTEGER
    );
  ''');
  await db.execute('''
    CREATE TABLE pedidos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      numero TEXT,
      produtos TEXT,
      total REAL,
      status TEXT,
      datahora TEXT,
      vendedor_codigo TEXT,
      vendedor_nome TEXT,
      cliente_id INTEGER,
      cliente_nome TEXT,
      assinatura TEXT,
      assinatura_path TEXT,
      cliente_telefone TEXT,
      cliente_endereco TEXT,
      cliente_cidade TEXT,
      cliente_cpf_cnpj TEXT,
      cliente_insc_estadual TEXT,
      cliente_cep TEXT,
      cliente_anotacao TEXT,
      cliente_nome_fantasia TEXT,
      cliente_whatsapp TEXT,
      cliente_email TEXT,
      pendente_envio INTEGER NOT NULL DEFAULT 0
    );
  ''');
  await db.execute(
      'CREATE UNIQUE INDEX ux_pedidos_num_vend ON pedidos(numero, vendedor_codigo);');
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('fluxo_pedido_local_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDownAll(_limpar);

  test('novoIdAparelho gera uuid v4', () {
    final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final ids = {for (var i = 0; i < 50; i++) novoIdAparelho()};
    expect(ids.length, 50);
    expect(ids.every(re.hasMatch), isTrue);
  });

  test('salvo novo vira pendente e ganha id_aparelho', () async {
    await salvarPedidoLocal(
        {'status': 'salvo', 'numero': '7', 'vendedor_codigo': '0003'});
    final r = await _linha('7');
    expect(r['pendente_envio'], 1);
    expect((r['id_aparelho'] as String).length, 36);
    expect(r['so_local'], 0);
  });

  test('id_aparelho nao muda ao regravar', () async {
    await salvarPedidoLocal(
        {'status': 'salvo', 'numero': '7', 'vendedor_codigo': '0003'});
    final antes = await _linha('7');
    await atualizarPedidoLocal({
      'id': antes['id'],
      'status': 'salvo',
      'numero': '7',
      'vendedor_codigo': '0003',
      'id_aparelho': 'outro-valor',
    });
    expect((await _linha('7'))['id_aparelho'], antes['id_aparelho']);
    // regravar via salvarPedidoLocal (INSERT OR REPLACE) tambem preserva
    await salvarPedidoLocal({
      'id': antes['id'],
      'status': 'finalizado',
      'numero': '7',
      'vendedor_codigo': '0003',
    });
    expect((await _linha('7'))['id_aparelho'], antes['id_aparelho']);
  });

  test('linha do servidor mantem o id_aparelho que veio', () async {
    await salvarPedidoLocal({
      'id': 42,
      'status': 'finalizado',
      'numero': '9',
      'vendedor_codigo': '0003',
      'id_aparelho': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    });
    expect((await _linha('9'))['id_aparelho'],
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  });

  test('cancelado tambem fica pendente', () async {
    await salvarPedidoLocal(
        {'status': 'salvo', 'numero': '7', 'vendedor_codigo': '0003'});
    final antes = await _linha('7');
    await atualizarPedidoLocal({
      'id': antes['id'],
      'status': 'cancelado',
      'numero': '7',
      'vendedor_codigo': '0003',
    });
    expect((await _linha('7'))['pendente_envio'], 1);
  });

  test('v16 para v17 marca rascunhos antigos como so_local', () async {
    final path = join(await databaseFactory.getDatabasesPath(), 'milkdim.db');
    final v16 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(version: 16, onCreate: _criarSchemaV16));
    await v16.insert('pedidos', {
      'id': kLocalIdBase + 1,
      'numero': '1',
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'pendente_envio': 0,
    });
    await v16.insert('pedidos', {
      'id': kLocalIdBase + 2,
      'numero': '2',
      'status': 'finalizado',
      'vendedor_codigo': '0003',
      'pendente_envio': 1,
    });
    await v16.close();

    final rasc = await _linha('1');
    expect(rasc['so_local'], 1);
    expect(rasc['pendente_envio'], 0);
    final fin = await _linha('2');
    expect(fin['so_local'], 0);
    expect(fin['pendente_envio'], 1);

    final db = await getDb();
    final t = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'pedidos_descartados'");
    expect(t, isNotEmpty);
  });

  test('salvar um so_local tira a marca e envia', () async {
    await salvarPedidoLocal({
      'status': 'salvo',
      'numero': '5',
      'vendedor_codigo': '0003',
      'so_local': 1,
    });
    final r = await _linha('5');
    expect(r['so_local'], 1);
    expect(r['pendente_envio'], 0);

    // sem a chave so_local, o valor guardado e mantido
    await atualizarPedidoLocal({
      'id': r['id'],
      'status': 'salvo',
      'numero': '5',
      'vendedor_codigo': '0003',
    });
    final mant = await _linha('5');
    expect(mant['so_local'], 1);
    expect(mant['pendente_envio'], 0);

    await atualizarPedidoLocal({
      'id': r['id'],
      'status': 'salvo',
      'numero': '5',
      'vendedor_codigo': '0003',
      'so_local': 0,
    });
    final env = await _linha('5');
    expect(env['so_local'], 0);
    expect(env['pendente_envio'], 1);
  });

  test('listarPedidosLocaisPorStatus filtra vendedor e status', () async {
    await salvarPedidoLocal(
        {'status': 'salvo', 'numero': '1', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal(
        {'status': 'cancelado', 'numero': '2', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal(
        {'status': 'salvo', 'numero': '3', 'vendedor_codigo': '0004'});
    final r = await listarPedidosLocaisPorStatus('0003', 'salvo');
    expect(r.map((e) => e['numero']), ['1']);
  });

  test('guardarVersaoDescartada grava json', () async {
    await guardarVersaoDescartada(
        {'numero': '88', 'status': 'salvo', 'total': 3.5}, 'servidor_mais_novo');
    final db = await getDb();
    final r = await db.query('pedidos_descartados');
    expect(r.length, 1);
    expect(jsonDecode(r.single['pedido_json'] as String)['numero'], '88');
    expect(r.single['motivo'], 'servidor_mais_novo');
    expect(r.single['descartado_em'], isNotNull);
  });

  test('jaChegouAoServidor', () {
    expect(jaChegouAoServidor({'id': 42}), isTrue);
    expect(jaChegouAoServidor({'id': kLocalIdBase + 1}), isFalse);
    expect(jaChegouAoServidor({}), isFalse);
  });
}
