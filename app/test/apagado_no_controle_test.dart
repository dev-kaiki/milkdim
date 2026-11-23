// test/apagado_no_controle_test.dart
//
// Pedido que já chegou ao servidor e foi apagado no Controle: o UPDATE por id
// não devolve linha. O app confere se o pedido ainda existe (consulta por id,
// trocada aqui por uma função local) e, se não existe, guarda uma cópia em
// pedidos_descartados, tira o pedido da fila de envio (sem apagá-lo) e marca
// erro_envio = 'apagado'.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

Future<Map<String, Object?>?> _porId(int id) async {
  final db = await getDb();
  final r = await db.query('pedidos', where: 'id = ?', whereArgs: [id]);
  return r.isEmpty ? null : r.single;
}

Future<List<Map<String, Object?>>> _descartados() async {
  final db = await getDb();
  return db.query('pedidos_descartados');
}

Map<String, dynamic> _pedido(int id, {String numero = '492', double total = 10.0}) => {
      'id': id,
      'numero': numero,
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-23T10:00:00Z',
      'total': total,
      'cliente_nome': 'Cliente',
      'id_aparelho': 'ap-$id',
      'produtos': [
        {'nome': 'Pudim', 'preco': total, 'quantidade': 1, 'subtotal': total},
      ],
    };

/// Pedido já no servidor (id baixo), aguardando envio de uma alteração.
Future<void> _pendenteNoServidor(int id, {String numero = '492'}) async {
  await salvarPedidoLocal(_pedido(id, numero: numero));
  final db = await getDb();
  await db.update('pedidos', {'pendente_envio': 1, 'so_local': 0},
      where: 'id = ?', whereArgs: [id]);
}

void main() {
  final buscaNumeroOriginal = buscarRemotoPorNumero;
  final buscaIdOriginal = buscarRemotoPorId;
  final gravarOriginal = gravarPedidoNoServidor;

  /// ids que o servidor falso ainda tem.
  late Set<int> noServidor;
  late List<int> consultasPorId;
  late List<int?> gravacoes;
  var consultaFalha = false;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('apagado_no_controle_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await _limpar();
    noServidor = {};
    consultasPorId = [];
    gravacoes = [];
    consultaFalha = false;
    buscarRemotoPorNumero = (numero, vend) async => null;
    // UPDATE por id: sem a linha no servidor, nada volta (406 / maybeSingle null).
    gravarPedidoNoServidor = (payload, {int? idServidor}) async {
      gravacoes.add(idServidor);
      if (idServidor == null || !noServidor.contains(idServidor)) return null;
      return {...payload, 'id': idServidor};
    };
    buscarRemotoPorId = (id) async {
      consultasPorId.add(id);
      if (consultaFalha) throw const SocketException('sem rede');
      return noServidor.contains(id) ? {'id': id} : null;
    };
  });

  tearDown(() {
    buscarRemotoPorNumero = buscaNumeroOriginal;
    buscarRemotoPorId = buscaIdOriginal;
    gravarPedidoNoServidor = gravarOriginal;
  });
  tearDownAll(_limpar);

  group('gravarPedidoEEnviar', () {
    test('UPDATE sem linha e pedido nao existe: apagado no Controle', () async {
      await _pendenteNoServidor(492);

      final r = await gravarPedidoEEnviar(_pedido(492, total: 12.5), novo: false);

      expect(r, ResultadoGravacao.apagadoNoControle);
      expect(consultasPorId, [492]);
      final p = await _porId(492);
      expect(p, isNotNull, reason: 'o pedido local nunca é apagado pela sincronização');
      expect(p!['pendente_envio'], 0);
      expect(p['erro_envio'], 'apagado');
      expect(p['total'], 12.5);
      final d = await _descartados();
      expect(d, hasLength(1));
      expect(d.single['motivo'], 'apagado no Controle');
      final copia = jsonDecode(d.single['pedido_json'] as String) as Map;
      expect(copia['id'], 492);
      expect(copia['total'], 12.5);
      expect(await contarPedidosPendentesEnvio('0003'), 0);
    });

    test('UPDATE sem linha mas o pedido existe: continua pendente', () async {
      await _pendenteNoServidor(492);
      noServidor = {};
      buscarRemotoPorId = (id) async {
        consultasPorId.add(id);
        return {'id': id};
      };

      final r = await gravarPedidoEEnviar(_pedido(492), novo: false);

      expect(r, ResultadoGravacao.pendente);
      final p = await _porId(492);
      expect(p!['pendente_envio'], 1);
      expect(p['erro_envio'], isNull);
      expect(await _descartados(), isEmpty);
      expect(await contarPedidosPendentesEnvio('0003'), 1);
    });

    test('consulta falha (sem rede): continua pendente, nada descartado', () async {
      await _pendenteNoServidor(492);
      consultaFalha = true;

      final r = await gravarPedidoEEnviar(_pedido(492), novo: false);

      expect(r, ResultadoGravacao.pendente);
      final p = await _porId(492);
      expect(p!['pendente_envio'], 1);
      expect(p['erro_envio'], isNull);
      expect(await _descartados(), isEmpty);
    });

    test('pedido que existe e aceita o UPDATE: enviado normalmente', () async {
      await _pendenteNoServidor(492);
      noServidor = {492};

      final r = await gravarPedidoEEnviar(_pedido(492), novo: false);

      expect(r, ResultadoGravacao.enviado);
      expect(consultasPorId, isEmpty);
      expect((await _porId(492))!['pendente_envio'], 0);
      expect((await _porId(492))!['erro_envio'], isNull);
    });
  });

  group('subirPedidosPendentes', () {
    test('apagado conta em apagados, nao em falhas, e nao volta para a fila', () async {
      await _pendenteNoServidor(492);
      await _pendenteNoServidor(493, numero: '493');
      // 493 existe, mas o UPDATE não voltou (problema passageiro).
      buscarRemotoPorId = (id) async {
        consultasPorId.add(id);
        return id == 493 ? {'id': id} : null;
      };

      final r = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(r.enviados, 0);
      expect(r.apagados, 1);
      expect(r.falhas, 1);
      expect(r.numeroEmUso, 0);
      expect((await _porId(492))!['pendente_envio'], 0);
      expect((await _porId(492))!['erro_envio'], 'apagado');
      expect((await _porId(493))!['pendente_envio'], 1);
      expect(await contarPedidosPendentesEnvio('0003'), 1);
      expect(await _descartados(), hasLength(1));

      // Próxima vez: só o 493 é tentado.
      gravacoes.clear();
      final r2 = await subirPedidosPendentes(vendedorCodigo: '0003');
      expect(gravacoes, [493]);
      expect(r2.apagados, 0);
      expect(r2.falhas, 1);
      expect(await _descartados(), hasLength(1));
    });

    test('pendentes e trava de logout nao contam o apagado', () async {
      await _pendenteNoServidor(492);
      expect(await contarPedidosPendentesEnvio('0003'), 1);
      expect(await codigosComPendentesEnvio(), contains('0003'));

      await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(await contarPedidosPendentesEnvio('0003'), 0);
      expect(await codigosComPendentesEnvio(), isNot(contains('0003')));
    });
  });

  group('sincronizacao depois', () {
    test('baixar pedidos nao ressuscita nem reenfileira o apagado', () async {
      await _pendenteNoServidor(492);
      await subirPedidosPendentes(vendedorCodigo: '0003');

      // O servidor não tem mais o 492; tem outro pedido do vendedor.
      await aplicarPedidosRemotos([
        {..._pedido(500, numero: '500'), 'pendente_envio': 0},
      ]);
      await aplicarPedidosRemotos(const []);

      final p = await _porId(492);
      expect(p, isNotNull);
      expect(p!['pendente_envio'], 0);
      expect(p['erro_envio'], 'apagado');
      expect(await _porId(500), isNotNull);
      expect(await contarPedidosPendentesEnvio('0003'), 0);

      gravacoes.clear();
      final r = await subirPedidosPendentes(vendedorCodigo: '0003');
      expect(gravacoes, isEmpty);
      expect(r.apagados + r.falhas + r.enviados, 0);
    });
  });

  group('Meus pedidos', () {
    testWidgets('apagado no Controle: selo e so Apagar do aparelho', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildMilkdimTheme(),
        home: PedidosPage(vendedorCodigo: '0003', pedidosParaCaptura: [
          {
            ..._pedido(492),
            'produtos': '[]',
            'so_local': 0,
            'pendente_envio': 0,
            'erro_envio': 'apagado',
            'cliente_nome': 'Padaria Central',
          },
          {
            ..._pedido(493, numero: '493'),
            'produtos': '[]',
            'status': 'finalizado',
            'so_local': 0,
            'pendente_envio': 0,
            'erro_envio': 'apagado',
            'cliente_nome': 'Mercearia Boa Vista',
          },
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Apagado no Controle'), findsOneWidget);
      expect(find.text('Apagar do aparelho'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Cancelar pedido'), findsNothing);
      expect(find.text('Trocar número'), findsNothing);
      expect(find.text('Aguardando envio'), findsNothing);

      await tester.tap(find.text('Apagar do aparelho'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'pede confirmação');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entregues (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Apagado no Controle'), findsOneWidget);
      expect(find.text('Apagar do aparelho'), findsOneWidget);
      expect(find.text('Entregue'), findsNothing);
      expect(find.text('Registrar entrega'), findsNothing);
    });
  });
}
