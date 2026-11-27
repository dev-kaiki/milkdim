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

/// Espera [condicao] ficar verdadeira, sem prazo fixo curto: com a suíte
/// inteira (ou outro processo) ocupando a CPU, abrir o banco e gravar no
/// SQLite (ffi) passa fácil de 100 ms. Quem chama segura a trava o tempo todo,
/// então uma gravação que esperasse a trava nunca apareceria e o teste
/// falharia no [limite].
Future<void> _esperarAte(
  Future<bool> Function() condicao, {
  required String motivo,
  Duration limite = const Duration(seconds: 20),
}) async {
  final relogio = Stopwatch()..start();
  while (!await condicao()) {
    if (relogio.elapsed > limite) fail('$motivo (esperou ${relogio.elapsed})');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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

  // ---- Gravação local nunca espera a rede; eco antigo não apaga edição ----

  Future<Map<String, Object?>?> porId(int id) async {
    final db = await getDb();
    final r = await db.query('pedidos', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.single;
  }

  Map<String, dynamic> pedido({
    int? id,
    String status = 'finalizado',
    String datahora = '2026-11-01T10:00:00Z',
    double total = 10.0,
  }) =>
      {
        if (id != null) 'id': id,
        'numero': '1',
        'status': status,
        'vendedor_codigo': '0003',
        'datahora': datahora,
        'total': total,
        'produtos': [
          {'nome': 'Queijo', 'preco': total, 'quantidade': 1, 'subtotal': total},
        ],
        'assinatura_path': '/local/ass_1.png',
      };

  test('gravarPedidoEEnviar grava no aparelho na hora, com a trava ocupada', () async {
    final liberaTrava = Completer<void>();
    final ocupada = comTravaDePedidos(() => liberaTrava.future);

    final gravacao = gravarPedidoEEnviar(
      pedido(),
      novo: true,
      enviar: (p) => comTravaDePedidos(() async {}),
      // A espera abaixo pode passar do prazo da tela numa máquina carregada;
      // aqui o envio deve terminar como enviado, não virar pendente por prazo.
      prazoEnvio: const Duration(minutes: 2),
    );

    final db = await getDb();
    Future<List<Map<String, Object?>>> linhas() =>
        db.query('pedidos', where: "numero = '1'");
    await _esperarAte(() async => (await linhas()).isNotEmpty,
        motivo: 'a gravação local não pode esperar a trava');
    final rows = await linhas();
    expect(rows, hasLength(1));
    expect(rows.single['pendente_envio'], 1);

    liberaTrava.complete();
    await ocupada;
    expect(await gravacao, ResultadoGravacao.enviado);
  });

  test('envio que falha não é erro: pedido fica salvo e pendente', () async {
    final r = await gravarPedidoEEnviar(
      pedido(),
      novo: true,
      enviar: (p) async => throw Exception('sem internet'),
    );
    expect(r, ResultadoGravacao.pendente);
    final db = await getDb();
    final rows = await db.query('pedidos', where: "numero = '1'");
    expect(rows.single['pendente_envio'], 1);
  });

  test('rascunho antigo (so_local) não é enviado', () async {
    var enviou = false;
    final r = await gravarPedidoEEnviar({...pedido(status: 'salvo'), 'so_local': 1},
        novo: true, enviar: (p) async => enviou = true);
    expect(r, ResultadoGravacao.rascunho);
    expect(enviou, isFalse);
  });

  test('finalizar de novo o mesmo numero+vendedor atualiza a linha pendente', () async {
    await salvarPedidoLocal(pedido(total: 10.0));
    final db = await getDb();
    final id1 = (await db.query('pedidos')).single['id'];

    await salvarPedidoLocal(pedido(total: 30.0, datahora: '2026-11-01T10:05:00Z'));
    final rows = await db.query('pedidos', where: "numero = '1' AND vendedor_codigo = '0003'");
    expect(rows, hasLength(1));
    expect(rows.single['id'], id1, reason: 'mesma linha, mesmo id');
    expect(rows.single['total'], 30.0);
    expect(rows.single['pendente_envio'], 1);
  });

  test('eco antigo do servidor não sobrescreve edição local mais nova', () async {
    const idLocal = kLocalIdBase + 1;
    final enviado = pedido(id: idLocal); // versão que foi para o servidor
    // Edição feita com o envio no ar.
    await salvarPedidoLocal(pedido(id: idLocal, total: 25.0, datahora: '2026-11-01T11:00:00Z'));

    final aplicou = await aplicarEcoDoServidor(
      enviado: enviado,
      remoto: {...pedido(), 'id': 55},
    );

    expect(aplicou, ResultadoEco.edicaoLocalMaisNova);
    final p = await porId(idLocal);
    expect(p, isNotNull, reason: 'a edição local continua lá');
    expect(p!['total'], 25.0);
    expect(p['pendente_envio'], 1);
    expect(await porId(55), isNull);
  });

  test('eco do servidor aplica quando a cópia local não mudou', () async {
    const idLocal = kLocalIdBase + 1;
    final enviado = pedido(id: idLocal);
    await salvarPedidoLocal(enviado);

    final aplicou = await aplicarEcoDoServidor(
      enviado: enviado,
      remoto: {...pedido(), 'id': 55, 'assinatura_path': null},
    );

    expect(aplicou, ResultadoEco.aplicado);
    expect(await porId(idLocal), isNull, reason: 'id local antigo sai');
    final p = await porId(55);
    expect(p!['pendente_envio'], 0);
    expect(p['assinatura_path'], '/local/ass_1.png');
  });

  test('edição durante subirPedidosPendentes: grava na hora e sobrevive ao eco', () async {
    const idLocal = kLocalIdBase + 1;
    await salvarPedidoLocal(pedido(id: idLocal));

    final enviando = Completer<void>();
    final liberaEnvio = Completer<void>();
    Future<void> enviarComEco(Map<String, dynamic> p) async {
      enviando.complete();
      await liberaEnvio.future;
      await aplicarEcoDoServidor(enviado: p, remoto: {...pedido(), 'id': 55});
    }

    final subida = subirPedidosPendentes(vendedorCodigo: '0003', enviar: enviarComEco);
    await enviando.future;

    // A edição (offline: o envio dela falha) grava sem esperar a subida.
    final edicao = gravarPedidoEEnviar(
      pedido(id: idLocal, total: 25.0, datahora: '2026-11-01T11:00:00Z'),
      novo: false,
      enviar: (p) => comTravaDePedidos(() async => throw Exception('sem internet')),
    );
    await _esperarAte(() async => (await porId(idLocal))?['total'] == 25.0,
        motivo: 'a edição grava com a subida no ar (que segura a trava)');

    liberaEnvio.complete();
    await subida;
    expect(await edicao, ResultadoGravacao.pendente);

    final p = await porId(idLocal);
    expect(p!['total'], 25.0, reason: 'a edição mais nova vence o eco antigo');
    expect(p['pendente_envio'], 1, reason: 'a edição continua aguardando envio');
    expect(await porId(55), isNull);
  });
}
