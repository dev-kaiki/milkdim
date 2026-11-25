// test/eco_cancelado_test.dart
//
// Pedido cancelado no Controle não é anunciado como "finalizado no Controle".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

Map<String, dynamic> _pedido({
  required int id,
  String status = 'salvo',
  String datahora = '2026-11-23T10:00:00Z',
  double total = 10.0,
}) =>
    {
      'id': id,
      'numero': '8',
      'status': status,
      'vendedor_codigo': '0003',
      'datahora': datahora,
      'total': total,
      'cliente_nome': 'Cliente',
      'produtos': [
        {'nome': 'Pudim', 'preco': total, 'quantidade': 1, 'subtotal': total},
      ],
      'id_aparelho': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    };

void main() {
  final buscaOriginal = buscarRemotoPorNumero;
  final gravarOriginal = gravarPedidoNoServidor;
  late Map<String, dynamic> noServidor;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('eco_cancelado_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await _limpar();
    buscarRemotoPorNumero = (n, v) async => null;
    // Gatilho: pedido fechado volta como estava.
    gravarPedidoNoServidor = (payload, {int? idServidor}) async =>
        Map<String, dynamic>.from(noServidor);
  });

  tearDown(() {
    buscarRemotoPorNumero = buscaOriginal;
    gravarPedidoNoServidor = gravarOriginal;
  });
  tearDownAll(_limpar);

  Future<void> abertoNoAparelho() async {
    await salvarPedidoLocal(_pedido(id: 42));
  }

  test('edicao de pedido cancelado no Controle: canceladoNoControle', () async {
    noServidor = {
      ..._pedido(id: 42, status: 'cancelado'),
      'cancelado_em': '2026-11-23T10:30:00+00:00',
      'cancelado_por': '0001',
    };
    await abertoNoAparelho();

    final r = await gravarPedidoEEnviar(
        _pedido(id: 42, total: 30.0, datahora: '2026-11-23T11:00:00Z'),
        novo: false);

    expect(r, ResultadoGravacao.canceladoNoControle);
    expect(mensagemGravacao(r, 'salvo'), 'Este pedido foi cancelado no Controle.');
    expect(gravacaoEhAviso(r), isTrue);
    final db = await getDb();
    final l = (await db.query('pedidos', where: 'id = ?', whereArgs: [42])).single;
    expect(l['status'], 'cancelado', reason: 'fica a versão do servidor');
    expect(
        (await db.rawQuery('SELECT COUNT(*) AS c FROM pedidos_descartados')).first['c'], 1,
        reason: 'a versão local que perdeu é guardada');
  });

  test('aplicarEcoDoServidor devolve servidorCancelou para cancelado', () async {
    final enviado = _pedido(id: 42, total: 30.0, datahora: '2026-11-23T11:00:00Z');
    await salvarPedidoLocal(enviado);
    final r = await aplicarEcoDoServidor(
        enviado: enviado, remoto: _pedido(id: 42, status: 'cancelado'));
    expect(r, ResultadoEco.servidorCancelou);
  });

  test('edicao de pedido finalizado no Controle continua fechadoNoControle', () async {
    noServidor = {..._pedido(id: 42, status: 'finalizado'), 'finalizado_manual': true};
    await abertoNoAparelho();

    final r = await gravarPedidoEEnviar(
        _pedido(id: 42, total: 30.0, datahora: '2026-11-23T11:00:00Z'),
        novo: false);

    expect(r, ResultadoGravacao.fechadoNoControle);
    expect(mensagemGravacao(r, 'salvo'), 'Este pedido já foi finalizado no Controle.');
  });

  test('cancelar no app um pedido que o Controle ja cancelou: cancelado no Controle',
      () async {
    noServidor = _pedido(id: 42, status: 'cancelado');
    await abertoNoAparelho();

    final r = await gravarPedidoEEnviar(
        {..._pedido(id: 42, status: 'cancelado', datahora: '2026-11-23T11:00:00Z')},
        novo: false);

    expect(r, ResultadoGravacao.canceladoNoControle);
    expect(mensagemGravacao(r, 'cancelado'), 'Este pedido foi cancelado no Controle.');
  });
}
