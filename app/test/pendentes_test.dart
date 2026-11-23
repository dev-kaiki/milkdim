// test/pendentes_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';

Future<String> _dbPath() async =>
    join(await databaseFactory.getDatabasesPath(), 'milkdim.db');

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory.deleteDatabase(await _dbPath());
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Pasta própria: os arquivos de teste rodam em paralelo e não podem
    // compartilhar o milkdim.db.
    final dir = await Directory.systemTemp.createTemp('pendentes_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDownAll(_limpar);

  test('v16 marca finalizados locais como pendentes e remove senha', () async {
    final path = await _dbPath();
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE vendedores (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT UNIQUE, nome TEXT, senha TEXT, ativo INTEGER)');
          await db.execute('CREATE TABLE pedidos (id INTEGER PRIMARY KEY AUTOINCREMENT, numero TEXT, produtos TEXT, total REAL, status TEXT, datahora TEXT, vendedor_codigo TEXT, vendedor_nome TEXT, cliente_id INTEGER, cliente_nome TEXT, assinatura TEXT, assinatura_path TEXT)');
          await db.insert('vendedores', {'codigo': '0003', 'nome': 'Fulano', 'senha': '1234', 'ativo': 1});
          for (final p in [
            [kLocalIdBase + 1, '1', 'finalizado'],
            [5, '2', 'finalizado'],
            [kLocalIdBase + 2, '3', 'salvo'],
          ]) {
            await db.insert('pedidos', {
              'id': p[0], 'numero': p[1], 'status': p[2],
              'vendedor_codigo': '0003', 'datahora': '2026-01-01T10:00:00Z',
            });
          }
        },
      ),
    );
    await old.close();

    final db = await getDb();
    final cols = (await db.rawQuery('PRAGMA table_info(vendedores)')).map((r) => r['name']).toList();
    expect(cols, isNot(contains('senha')));
    expect((await db.query('vendedores')).single['codigo'], '0003');

    final pend = await listarPedidosPendentesEnvio('0003');
    expect(pend.map((r) => r['id']).toList(), [kLocalIdBase + 1]);
  });

  test('salvar finalizado marca pendente; salvo nao', () async {
    await salvarPedidoLocal({'numero': '10', 'status': 'finalizado', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal({'numero': '11', 'status': 'salvo', 'vendedor_codigo': '0003', 'so_local': 1});
    final pend = await listarPedidosPendentesEnvio('0003');
    expect(pend.length, 1);
    expect(pend.single['numero'], '10');

    final db = await getDb();
    final id11 = (await db.query('pedidos', where: "numero='11'")).single['id'];
    await atualizarPedidoLocal({'id': id11, 'numero': '11', 'status': 'finalizado', 'vendedor_codigo': '0003', 'so_local': 0});
    expect(await contarPedidosPendentesEnvio('0003'), 2);
    await atualizarPedidoLocal({'id': id11, 'numero': '11', 'status': 'salvo', 'vendedor_codigo': '0003', 'so_local': 1});
    expect(await contarPedidosPendentesEnvio('0003'), 1);
  });

  test('contarPedidosPendentesEnvio filtra pelo vendedor', () async {
    await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal({'numero': '2', 'status': 'finalizado', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0004'});
    expect(await contarPedidosPendentesEnvio('0003'), 2);
    expect(await contarPedidosPendentesEnvio('0004'), 1);
    expect(await contarPedidosPendentesEnvio('0009'), 0);
  });

  test('codigosComPendentesEnvio devolve {0003} quando so 0003 tem pendente', () async {
    await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0003'});
    await salvarPedidoLocal({'numero': '2', 'status': 'salvo', 'vendedor_codigo': '0004', 'so_local': 1});
    expect(await codigosComPendentesEnvio(), {'0003'});
  });

  test('salvarVendedorLocal deixa so o vendedor logado', () async {
    await salvarVendedorLocal({'codigo': '0003', 'nome': 'A', 'ativo': true, 'senha': 'x'});
    await salvarVendedorLocal({'codigo': '0004', 'nome': 'B', 'ativo': 1});
    final db = await getDb();
    final rows = await db.query('vendedores');
    expect(rows.length, 1);
    expect(rows.single['codigo'], '0004');
    expect(rows.single.containsKey('senha'), isFalse);
  });
}
