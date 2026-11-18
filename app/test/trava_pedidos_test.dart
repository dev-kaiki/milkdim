// test/trava_pedidos_test.dart
//
// Envio de pendentes e gravação/envio de pedido não podem rodar ao mesmo
// tempo: o eco antigo do servidor sobrescreveria uma edição mais nova.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('trava_pedidos_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDownAll(_limpar);

  test('duas chamadas concorrentes rodam uma depois da outra', () async {
    final log = <String>[];
    final liberaA = Completer<void>();

    final a = comTravaDePedidos(() async {
      log.add('a:inicio');
      await liberaA.future;
      log.add('a:fim');
    });
    final b = comTravaDePedidos(() async {
      log.add('b:inicio');
      log.add('b:fim');
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(log, ['a:inicio'], reason: 'b não pode começar com a em andamento');

    liberaA.complete();
    await Future.wait([a, b]);
    expect(log, ['a:inicio', 'a:fim', 'b:inicio', 'b:fim']);
  });

  test('erro numa chamada não trava a fila', () async {
    await expectLater(
        comTravaDePedidos<void>(() async => throw StateError('x')), throwsStateError);
    expect(await comTravaDePedidos(() async => 7), 7);
  });

  test('chamada aninhada (subir -> salvar) não trava', () async {
    final r = await comTravaDePedidos(() => comTravaDePedidos(() async => 'ok'))
        .timeout(const Duration(seconds: 2));
    expect(r, 'ok');
  });

  test('subirPedidosPendentes concorrentes não enviam o mesmo pedido duas vezes', () async {
    await salvarPedidoLocal({
      'id': kLocalIdBase + 1,
      'numero': '1',
      'status': 'finalizado',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-01T10:00:00Z',
    });

    var envios = 0;
    Future<void> enviar(Map<String, dynamic> p) async {
      envios++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final db = await getDb();
      await db.update('pedidos', {'pendente_envio': 0},
          where: 'id = ?', whereArgs: [p['id']]);
    }

    final r = await Future.wait([
      subirPedidosPendentes(vendedorCodigo: '0003', enviar: enviar),
      subirPedidosPendentes(vendedorCodigo: '0003', enviar: enviar),
    ]);
    expect(envios, 1);
    expect(r.map((e) => e.enviados).toList()..sort(), [0, 1]);
  });

  test('gravação local sob a trava espera o envio em andamento', () async {
    await salvarPedidoLocal({
      'id': kLocalIdBase + 1,
      'numero': '1',
      'status': 'finalizado',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-01T10:00:00Z',
      'total': 10.0,
    });

    final enviando = Completer<void>();
    final liberaEnvio = Completer<void>();
    // Eco do servidor: versão antiga, já enviada.
    Future<void> enviar(Map<String, dynamic> p) async {
      enviando.complete();
      await liberaEnvio.future;
      final db = await getDb();
      await db.update('pedidos', {'total': 10.0, 'pendente_envio': 0},
          where: 'id = ?', whereArgs: [p['id']]);
    }

    final subida = subirPedidosPendentes(vendedorCodigo: '0003', enviar: enviar);
    await enviando.future;

    // Edição offline do mesmo pedido enquanto o envio está no ar.
    final edicao = comTravaDePedidos(() => atualizarPedidoLocal({
          'id': kLocalIdBase + 1,
          'numero': '1',
          'status': 'finalizado',
          'vendedor_codigo': '0003',
          'datahora': '2026-11-01T11:00:00Z',
          'total': 25.0,
        }));
    // Sem a trava a edição já teria terminado aqui, antes do eco.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    liberaEnvio.complete();
    await Future.wait([subida, edicao]);

    final db = await getDb();
    final p = (await db.query('pedidos', where: 'id = ?', whereArgs: [kLocalIdBase + 1])).single;
    expect(p['total'], 25.0, reason: 'a edição mais nova vence o eco antigo');
    expect(p['pendente_envio'], 1, reason: 'a edição continua aguardando envio');
  });
}
