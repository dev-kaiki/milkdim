// test/fluxo_pedido_envio_test.dart
//
// Fase A, Task 3: envio de pedido aberto/cancelado, conflito de número por
// id_aparelho, eco de pedido fechado no Controle e sincronização sem duplicar.
// O servidor é falso: os dois pontos de rede do envio (consulta por número e
// gravação) são trocados por funções locais.
import 'dart:convert';
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

Future<Map<String, Object?>?> _porId(int id) async {
  final db = await getDb();
  final r = await db.query('pedidos', where: 'id = ?', whereArgs: [id]);
  return r.isEmpty ? null : r.single;
}

Future<List<Map<String, Object?>>> _porNumero(String numero) async {
  final db = await getDb();
  return db.query('pedidos', where: 'numero = ?', whereArgs: [numero]);
}

Future<int> _descartados() async {
  final db = await getDb();
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM pedidos_descartados');
  return r.first['c'] as int;
}

/// Servidor falso com a regra do gatilho: pedido fechado (finalizado ou
/// cancelado) devolve a linha como estava, salvo entrega assinada sobre
/// cancelado ou finalizado manual.
class _ServidorFalso {
  final linhas = <Map<String, dynamic>>[];
  final gravacoes = <Map<String, dynamic>>[];
  final consultas = <String>[];
  final inserts = <Map<String, dynamic>>[];
  var _proximoId = 100;

  Future<Map<String, dynamic>?> buscar(String numero, String vend) async {
    consultas.add('$numero/$vend');
    for (final l in linhas) {
      if (l['numero'] == numero && l['vendedor_codigo'] == vend) {
        return {
          'id': l['id'],
          'id_aparelho': l['id_aparelho'],
          'datahora': l['datahora'],
        };
      }
    }
    return null;
  }

  /// Índices únicos do servidor: id_aparelho e (numero, vendedor_codigo).
  void _unico(Map<String, dynamic> nova) {
    for (final l in linhas) {
      if (l['id'] == nova['id']) continue;
      if (nova['id_aparelho'] != null && l['id_aparelho'] == nova['id_aparelho']) {
        throw StateError('23505 id_aparelho duplicado');
      }
      if (l['numero'] == nova['numero'] &&
          l['vendedor_codigo'] == nova['vendedor_codigo']) {
        throw StateError('23505 pedidos_numero_vendedor_key');
      }
    }
  }

  Future<Map<String, dynamic>?> gravar(Map<String, dynamic> payload,
      {int? idServidor}) async {
    gravacoes.add(Map<String, dynamic>.from(payload));
    final i = idServidor != null
        ? linhas.indexWhere((l) => l['id'] == idServidor)
        : linhas.indexWhere((l) =>
            l['numero'] == payload['numero'] &&
            l['vendedor_codigo'] == payload['vendedor_codigo']);
    if (i < 0) {
      if (idServidor != null) return null; // UPDATE por id sem linha
      final nova = {
        ...payload,
        'id': _proximoId++,
        'enviado_em': '2026-11-23T12:00:00+00:00',
        'finalizado_manual': false,
      };
      _unico(nova);
      inserts.add(nova);
      linhas.add(nova);
      return Map<String, dynamic>.from(nova);
    }
    final old = linhas[i];
    final fechado = old['status'] == 'finalizado' || old['status'] == 'cancelado';
    final assinadaVence = payload['status'] == 'finalizado' &&
        payload['assinatura'] != null &&
        (old['status'] == 'cancelado' || old['finalizado_manual'] == true);
    if (fechado && !assinadaVence) return Map<String, dynamic>.from(old);
    final nova = {
      ...old,
      ...payload,
      'id': old['id'],
      'id_aparelho': old['id_aparelho'] ?? payload['id_aparelho'],
    };
    _unico(nova);
    linhas[i] = nova;
    return Map<String, dynamic>.from(nova);
  }
}

Map<String, dynamic> _pedido({
  int? id,
  String numero = '5',
  String status = 'salvo',
  String datahora = '2026-11-23T10:00:00Z',
  double total = 10.0,
  String? idAparelho,
}) =>
    {
      if (id != null) 'id': id,
      'numero': numero,
      'status': status,
      'vendedor_codigo': '0003',
      'datahora': datahora,
      'total': total,
      'cliente_nome': 'Cliente',
      'produtos': [
        {'nome': 'Pudim', 'preco': total, 'quantidade': 1, 'subtotal': total},
      ],
      if (idAparelho != null) 'id_aparelho': idAparelho,
    };

void main() {
  late _ServidorFalso srv;
  final buscaOriginal = buscarRemotoPorNumero;
  final gravarOriginal = gravarPedidoNoServidor;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('fluxo_pedido_envio_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await _limpar();
    srv = _ServidorFalso();
    buscarRemotoPorNumero = srv.buscar;
    gravarPedidoNoServidor = srv.gravar;
  });

  tearDown(() {
    buscarRemotoPorNumero = buscaOriginal;
    gravarPedidoNoServidor = gravarOriginal;
  });
  tearDownAll(_limpar);

  // ---------------------------------------------------------------- número

  group('conflito de numero', () {
    test('conflitoDeNumero', () {
      expect(conflitoDeNumero('a', 'a'), isFalse);
      expect(conflitoDeNumero('a', 'b'), isTrue);
      expect(conflitoDeNumero(null, 'b'), isFalse);
      expect(conflitoDeNumero(null, null), isFalse);
      expect(conflitoDeNumero(null, null, datahoraLocal: 'x', datahoraRemota: 'y'),
          isFalse);
      // Remoto sem id_aparelho: mesmo pedido só com a mesma datahora (instante).
      expect(
          conflitoDeNumero('a', null,
              datahoraLocal: '2026-11-23T10:00:00Z',
              datahoraRemota: '2026-11-23T07:00:00-03:00'),
          isFalse);
      expect(
          conflitoDeNumero('a', null,
              datahoraLocal: '2026-11-23T10:00:00.123456Z',
              datahoraRemota: '2026-11-23T10:00:00.123456+00:00'),
          isFalse);
      expect(
          conflitoDeNumero('a', null,
              datahoraLocal: '2026-11-23T10:00:00Z',
              datahoraRemota: '2026-11-23T10:00:01+00:00'),
          isTrue);
      expect(conflitoDeNumero('a', null), isTrue, reason: 'sem datahora é conflito');
      expect(
          conflitoDeNumero('a', null,
              datahoraLocal: '2026-11-23T10:00:00Z', datahoraRemota: 'lixo'),
          isTrue);
    });

    test('remoto sem id_aparelho e mesma datahora: eco perdido de envio antigo', () async {
      srv.linhas.add({
        ..._pedido(numero: '6', status: 'finalizado'),
        'id': 41,
        'id_aparelho': null,
        'datahora': '2026-11-23T10:00:00+00:00',
      });
      await salvarPedidoLocal(_pedido(
          id: kLocalIdBase + 1, numero: '6', status: 'finalizado', idAparelho: 'a'));

      final r = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(r.enviados, 1);
      expect(r.numeroEmUso, 0);
      expect(srv.inserts, isEmpty);
      final l = (await _porNumero('6')).single;
      expect(l['id'], 41);
      expect(l['pendente_envio'], 0);
      expect(l['id_aparelho'], 'a');
    });

    test('remoto sem id_aparelho e outra datahora: numero em uso', () async {
      srv.linhas.add({
        ..._pedido(numero: '6', status: 'finalizado', total: 99.0),
        'id': 41,
        'id_aparelho': null,
        'datahora': '2026-10-01T09:00:00+00:00',
      });
      final r = await gravarPedidoEEnviar(
          _pedido(numero: '6', total: 12.0, idAparelho: 'a'), novo: true);

      expect(r, ResultadoGravacao.numeroEmUso);
      expect(srv.gravacoes, isEmpty, reason: 'o servidor não recebe escrita');
      expect(srv.linhas.single['total'], 99.0);
      expect(srv.linhas.single['id_aparelho'], isNull);
      final l = (await _porNumero('6')).single;
      expect(l['id'] as int, greaterThanOrEqualTo(kLocalIdBase));
      expect(l['total'], 12.0, reason: 'o pedido local fica como está');
      expect(l['status'], 'salvo');
      expect(l['erro_envio'], 'numero');
      expect(l['pendente_envio'], 1);
      expect(await _descartados(), 0);
    });

    test('eco de outro pedido (antigo, fechado, sem id_aparelho) nao leva o nosso',
        () async {
      const idLocal = kLocalIdBase + 1;
      final enviado = _pedido(id: idLocal, numero: '6', idAparelho: 'a');
      await salvarPedidoLocal(enviado);

      final r = await aplicarEcoDoServidor(enviado: enviado, remoto: {
        ..._pedido(id: 41, numero: '6', status: 'finalizado', total: 99.0),
        'id_aparelho': null,
        'datahora': '2026-10-01T09:00:00+00:00',
      });

      expect(r, ResultadoEco.servidorFechou);
      expect(await _descartados(), 1);
      final p = await _porId(41);
      expect(p!['id_aparelho'], isNull, reason: 'não carimba o nosso id_aparelho');
    });

    test('sync nao leva o nosso id_aparelho para outro pedido de mesmo numero', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': kLocalIdBase + 5, 'numero': '13', 'vendedor_codigo': '0003',
        'status': 'finalizado', 'pendente_envio': 0, 'id_aparelho': 'a',
        'datahora': '2026-11-23T10:00:00Z',
      });
      await aplicarPedidosRemotos([
        {
          'id': 71, 'numero': '13', 'vendedor_codigo': '0003', 'status': 'finalizado',
          'datahora': '2026-10-01T09:00:00+00:00',
        },
        {
          'id': 72, 'numero': '14', 'vendedor_codigo': '0003', 'status': 'finalizado',
          'datahora': '2026-11-23T11:00:00+00:00',
        },
      ]);
      expect((await _porId(71))!['id_aparelho'], isNull);
    });

    test('sync leva o id_aparelho quando e o mesmo pedido (mesma datahora)', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': kLocalIdBase + 5, 'numero': '13', 'vendedor_codigo': '0003',
        'status': 'finalizado', 'pendente_envio': 0, 'id_aparelho': 'a',
        'datahora': '2026-11-23T10:00:00Z',
      });
      await aplicarPedidosRemotos([
        {
          'id': 71, 'numero': '13', 'vendedor_codigo': '0003', 'status': 'finalizado',
          'datahora': '2026-11-23T10:00:00+00:00',
        },
      ]);
      expect((await _porId(71))!['id_aparelho'], 'a');
    });

    test('eco perdido nao vira numero em uso', () async {
      // O envio chegou ao servidor, mas o eco se perdeu: o local continua na
      // faixa local e pendente, com o mesmo id_aparelho que o servidor tem.
      srv.linhas.add({
        ..._pedido(numero: '6', idAparelho: 'a'),
        'id': 41,
        'enviado_em': '2026-11-23T10:00:01+00:00',
      });
      await salvarPedidoLocal(_pedido(id: kLocalIdBase + 1, numero: '6', idAparelho: 'a'));

      final r = await gravarPedidoEEnviar(
        _pedido(id: kLocalIdBase + 1, numero: '6', idAparelho: 'a'),
        novo: false,
      );

      expect(r, ResultadoGravacao.enviado);
      expect(srv.gravacoes, hasLength(1));
      final linhas = await _porNumero('6');
      expect(linhas, hasLength(1));
      expect(linhas.single['id'], 41);
      expect(linhas.single['pendente_envio'], 0);
      expect(linhas.single['erro_envio'], isNull);
    });

    test('dois aparelhos mesmo numero', () async {
      srv.linhas.add({..._pedido(numero: '5', idAparelho: 'b'), 'id': 40});

      final r = await gravarPedidoEEnviar(_pedido(numero: '5', idAparelho: 'a'), novo: true);

      expect(r, ResultadoGravacao.numeroEmUso);
      final l = (await _porNumero('5')).single;
      expect(l['erro_envio'], 'numero');
      expect(l['pendente_envio'], 1);
      expect(l['id_aparelho'], 'a');
      expect(srv.gravacoes, isEmpty, reason: 'o servidor não pode receber update');
      expect(srv.linhas.single['id_aparelho'], 'b');
    });

    test('pedido que ja chegou ao servidor nao consulta o numero', () async {
      srv.linhas.add({..._pedido(numero: '8', idAparelho: 'a'), 'id': 43});
      await salvarPedidoLocal(_pedido(id: 43, numero: '8', idAparelho: 'a'));
      final r = await gravarPedidoEEnviar(
          _pedido(id: 43, numero: '8', total: 20, datahora: '2026-11-23T11:00:00Z'),
          novo: false);
      expect(r, ResultadoGravacao.enviado);
      expect(srv.consultas, isEmpty);
      expect(srv.linhas.single['total'], 20);
    });

    test('numeroLivreNoServidor', () async {
      srv.linhas.add({..._pedido(numero: '5', idAparelho: 'b'), 'id': 40});
      expect(await numeroLivreNoServidor('5', '0003'), isFalse);
      expect(await numeroLivreNoServidor('6', '0003'), isTrue);
      expect(await numeroLivreNoServidor('5', '0002'), isTrue);
      buscarRemotoPorNumero = (n, v) async => throw const SocketException('sem rede');
      expect(await numeroLivreNoServidor('5', '0003'), isTrue,
          reason: 'sem internet não bloqueia salvar');
    });
  });

  // ---------------------------------------------------------------- eco

  group('eco do servidor', () {
    test('decidirEco', () {
      final enviado = _pedido(id: kLocalIdBase + 1);
      final local = Map<String, dynamic>.from(enviado);

      final finalizadoManual = {
        ...enviado,
        'id': 40,
        'status': 'finalizado',
        'finalizado_manual': true,
      };
      expect(decidirEco(local, enviado, finalizadoManual), ResultadoEco.servidorFechou);

      expect(decidirEco(local, enviado, {...enviado, 'id': 40}), ResultadoEco.aplicado);

      final finalizado = _pedido(id: kLocalIdBase + 1, status: 'finalizado');
      expect(decidirEco(finalizado, finalizado, {...finalizado, 'id': 40}),
          ResultadoEco.aplicado);

      final editado = {...local, 'total': 25.0, 'datahora': '2026-11-23T11:00:00Z'};
      expect(decidirEco(editado, enviado, finalizadoManual),
          ResultadoEco.edicaoLocalMaisNova);
      expect(decidirEco(editado, enviado, {...enviado, 'id': 40}),
          ResultadoEco.edicaoLocalMaisNova);
    });

    test('decidirEco: cancelado sobre finalizado e finalizado com outros itens', () {
      final cancelado = _pedido(id: 40, status: 'cancelado');
      expect(
          decidirEco(cancelado, cancelado, {...cancelado, 'status': 'finalizado'}),
          ResultadoEco.servidorFechou);
      expect(decidirEco(cancelado, cancelado, {...cancelado}), ResultadoEco.aplicado);

      final fin = _pedido(id: 40, status: 'finalizado');
      final outro = {
        ...fin,
        'produtos': jsonEncode([
          {'nome': 'Leite ninho', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
        ]),
      };
      expect(decidirEco(fin, fin, outro), ResultadoEco.servidorFechou);
      // Mesmo conteúdo em outro formato (JSON texto, quantidade double).
      final igual = {
        ...fin,
        'produtos': jsonEncode([
          {'nome': 'Pudim', 'preco': 10, 'quantidade': 1.0, 'subtotal': 10},
        ]),
      };
      expect(decidirEco(fin, fin, igual), ResultadoEco.aplicado);
    });

    test('servidor fechou guarda a versao local', () async {
      const idLocal = 40;
      final enviado = _pedido(id: idLocal, total: 30.0, idAparelho: 'a');
      await salvarPedidoLocal(enviado);

      final r = await aplicarEcoDoServidor(
        enviado: enviado,
        remoto: {
          ..._pedido(id: idLocal, status: 'finalizado', total: 10.0),
          'id_aparelho': 'a',
          'finalizado_manual': true,
          'finalizado_em': '2026-11-23T10:30:00+00:00',
          'finalizado_por': '0001',
        },
      );

      expect(r, ResultadoEco.servidorFechou);
      expect(await _descartados(), 1);
      final db = await getDb();
      final d = (await db.query('pedidos_descartados')).single;
      expect(d['motivo'], 'fechado no Controle');
      final copia = jsonDecode(d['pedido_json'] as String) as Map<String, dynamic>;
      expect(copia['total'], 30.0, reason: 'a versão local que perdeu fica guardada');
      final p = await _porId(idLocal);
      expect(p!['status'], 'finalizado');
      expect(p['total'], 10.0);
      expect(p['pendente_envio'], 0);
      expect(p['finalizado_manual'], 'true');
      expect(p['finalizado_por'], '0001');
    });

    test('gravarPedidoEEnviar: edicao de pedido fechado no Controle', () async {
      srv.linhas.add({
        ..._pedido(numero: '7', status: 'finalizado', idAparelho: 'a'),
        'id': 42,
        'finalizado_manual': true,
      });
      await salvarPedidoLocal(_pedido(id: 42, numero: '7', idAparelho: 'a'));

      final r = await gravarPedidoEEnviar(
        _pedido(id: 42, numero: '7', total: 50.0, datahora: '2026-11-23T11:00:00Z'),
        novo: false,
      );

      expect(r, ResultadoGravacao.fechadoNoControle);
      expect(await _descartados(), 1);
      final p = await _porId(42);
      expect(p!['status'], 'finalizado');
      expect(p['total'], 10.0);
      expect(p['pendente_envio'], 0);
    });

    test('eco preenche as copias de auditoria, guarda id_aparelho e limpa erro_envio',
        () async {
      const idLocal = kLocalIdBase + 1;
      final enviado = _pedido(id: idLocal, idAparelho: 'a');
      await salvarPedidoLocal({...enviado, 'erro_envio': 'numero'});

      final r = await aplicarEcoDoServidor(
        enviado: enviado,
        remoto: {
          ..._pedido(id: 60),
          'enviado_em': '2026-11-23T10:00:01+00:00',
          'alterado_em': '2026-11-23T10:05:00+00:00',
          'finalizado_manual': false,
        },
      );

      expect(r, ResultadoEco.aplicado);
      expect(await _porId(idLocal), isNull);
      final p = await _porId(60);
      expect(p!['id_aparelho'], 'a', reason: 'o remoto sem id_aparelho mantém o local');
      expect(p['enviado_em'], '2026-11-23T10:00:01+00:00');
      expect(p['alterado_em'], '2026-11-23T10:05:00+00:00');
      expect(p['finalizado_manual'], 'false');
      expect(p['so_local'], 0);
      expect(p['erro_envio'], isNull);
      expect(p['pendente_envio'], 0);
    });
  });

  // ---------------------------------------------------------------- sync

  group('sincronizacao', () {
    test('sync nao duplica pedido aberto ja enviado', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 500,
        'numero': '9',
        'vendedor_codigo': '0003',
        'status': 'salvo',
        'pendente_envio': 0,
      });
      await aplicarPedidosRemotos([
        {'id': 500, 'numero': '9', 'vendedor_codigo': '0003', 'status': 'salvo'},
      ]);
      final rows = await _porNumero('9');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 500);
      expect(await db.query('pedidos'), hasLength(1));
    });

    test('sync ainda protege rascunho de outro numero com id colidindo', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 10, 'numero': '20', 'vendedor_codigo': '0003', 'status': 'salvo',
        'total': 4.0,
      });
      await aplicarPedidosRemotos([
        {'id': 10, 'numero': '10', 'vendedor_codigo': '0003', 'status': 'salvo', 'total': 7},
      ]);
      expect((await _porId(10))!['numero'], '10');
      final rasc = (await _porNumero('20')).single;
      expect(rasc['id'] as int, greaterThanOrEqualTo(kLocalIdBase));
    });

    test('sync mantem o id_aparelho local e copia a auditoria', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 50, 'numero': '3', 'vendedor_codigo': '0003', 'status': 'salvo',
        'pendente_envio': 0, 'id_aparelho': 'x',
      });
      await aplicarPedidosRemotos([
        {
          'id': 50, 'numero': '3', 'vendedor_codigo': '0003', 'status': 'finalizado',
          'finalizado_manual': true,
          'finalizado_em': '2026-11-23T10:30:00+00:00',
          'finalizado_por': '0001',
          'enviado_em': '2026-11-23T10:00:00+00:00',
        },
        {
          'id': 51, 'numero': '4', 'vendedor_codigo': '0003', 'status': 'cancelado',
          'id_aparelho': 'y',
          'cancelado_em': '2026-11-23T10:40:00+00:00',
          'cancelado_por': '0003',
        },
      ]);
      final p = await _porId(50);
      expect(p!['id_aparelho'], 'x');
      expect(p['so_local'], 0);
      expect(p['finalizado_manual'], 'true');
      expect(p['finalizado_em'], '2026-11-23T10:30:00+00:00');
      expect(p['finalizado_por'], '0001');
      expect(p['enviado_em'], '2026-11-23T10:00:00+00:00');
      final c = await _porId(51);
      expect(c!['id_aparelho'], 'y');
      expect(c['cancelado_em'], '2026-11-23T10:40:00+00:00');
      expect(c['cancelado_por'], '0003');
      expect(c['status'], 'cancelado');
    });

    test('sync nao apaga rascunho antigo (so_local) de mesmo numero', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': kLocalIdBase + 7, 'numero': '12', 'vendedor_codigo': '0003',
        'status': 'salvo', 'pendente_envio': 0, 'so_local': 1, 'total': 3.0,
      });
      await aplicarPedidosRemotos([
        {'id': 70, 'numero': '12', 'vendedor_codigo': '0003', 'status': 'finalizado'},
      ]);
      final p = await _porId(kLocalIdBase + 7);
      expect(p, isNotNull);
      expect(p!['so_local'], 1);
      expect(p['total'], 3.0);
    });
  });

  // ---------------------------------------------------------------- envio

  group('envio e gravacao', () {
    test('subirPedidosPendentes pula numero em uso', () async {
      await salvarPedidoLocal(
          {..._pedido(id: kLocalIdBase + 1, numero: '1'), 'erro_envio': 'numero'});
      await salvarPedidoLocal(_pedido(id: kLocalIdBase + 2, numero: '2'));

      final chamados = <String>[];
      final r = await subirPedidosPendentes(
        vendedorCodigo: '0003',
        enviar: (p) async {
          chamados.add('${p['numero']}');
          final db = await getDb();
          await db.update('pedidos', {'pendente_envio': 0},
              where: 'id = ?', whereArgs: [p['id']]);
        },
      );
      expect(chamados, ['2']);
      expect(r.enviados, 1);
      expect(r.falhas, 0);
      expect(r.numeroEmUso, 1);
      expect((await _porId(kLocalIdBase + 1))!['pendente_envio'], 1);
    });

    test('subirPedidosPendentes: NumeroEmUso grava erro_envio e nao conta falha',
        () async {
      await salvarPedidoLocal(_pedido(id: kLocalIdBase + 1, numero: '5', idAparelho: 'a'));
      srv.linhas.add({..._pedido(numero: '5', idAparelho: 'b'), 'id': 40});

      final r = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(r.enviados, 0);
      expect(r.falhas, 0);
      expect(r.numeroEmUso, 1);
      final p = await _porId(kLocalIdBase + 1);
      expect(p!['erro_envio'], 'numero');
      expect(p['pendente_envio'], 1);
      expect(srv.gravacoes, isEmpty);

      // Na próxima vez nem tenta.
      final r2 = await subirPedidosPendentes(vendedorCodigo: '0003');
      expect(r2.numeroEmUso, 1);
      expect(srv.consultas, hasLength(1));
    });

    test('gravarPedidoEEnviar salvo enviado', () async {
      var envios = 0;
      final r = await gravarPedidoEEnviar(_pedido(), novo: true, enviar: (p) async {
        envios++;
      });
      expect(r, ResultadoGravacao.enviado);
      expect(envios, 1);
    });

    test('gravarPedidoEEnviar so_local continua rascunho', () async {
      var envios = 0;
      final r = await gravarPedidoEEnviar({..._pedido(), 'so_local': 1},
          novo: true, enviar: (p) async => envios++);
      expect(r, ResultadoGravacao.rascunho);
      expect(envios, 0);
    });

    test('pedido aberto novo vai ao servidor com id_aparelho e status', () async {
      final r = await gravarPedidoEEnviar(_pedido(numero: '15'), novo: true);
      expect(r, ResultadoGravacao.enviado);

      final payload = srv.gravacoes.single;
      expect(payload['status'], 'salvo');
      expect((payload['id_aparelho'] as String).length, 36);
      for (final c in const [
        'id', 'so_local', 'erro_envio', 'pendente_envio', 'assinatura_path',
        'enviado_em', 'alterado_em', 'finalizado_em', 'finalizado_por',
        'finalizado_manual', 'cancelado_em', 'cancelado_por',
      ]) {
        expect(payload.containsKey(c), isFalse, reason: '$c não vai no payload');
      }
      expect(payload['produtos'], isA<List>(), reason: 'produtos vai como lista');

      final l = (await _porNumero('15')).single;
      expect(l['id'], 100);
      expect(l['pendente_envio'], 0);
      expect(l['id_aparelho'], payload['id_aparelho'],
          reason: 'o id_aparelho enviado é o guardado no aparelho');
      expect(l['enviado_em'], '2026-11-23T12:00:00+00:00');
    });

    test('cancelado sobe ao servidor', () async {
      srv.linhas.add({..._pedido(numero: '16', idAparelho: 'a'), 'id': 44});
      await salvarPedidoLocal(_pedido(id: 44, numero: '16', idAparelho: 'a'));
      final r = await gravarPedidoEEnviar(
          _pedido(id: 44, numero: '16', status: 'cancelado', datahora: '2026-11-23T11:00:00Z'),
          novo: false);
      expect(r, ResultadoGravacao.enviado);
      expect(srv.gravacoes.single['status'], 'cancelado');
      expect((await _porId(44))!['status'], 'cancelado');
    });

    test('pendente v16 sem id_aparelho ganha um antes de enviar', () async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': kLocalIdBase + 3, 'numero': '30', 'vendedor_codigo': '0003',
        'status': 'finalizado', 'total': 5.0, 'produtos': '[]',
        'datahora': '2026-11-01T10:00:00Z', 'pendente_envio': 1,
      });
      expect((await _porId(kLocalIdBase + 3))!['id_aparelho'], isNull);

      String? guardadoNoEnvio;
      gravarPedidoNoServidor = (payload, {int? idServidor}) async {
        guardadoNoEnvio =
            (await _porId(kLocalIdBase + 3))?['id_aparelho']?.toString();
        return srv.gravar(payload, idServidor: idServidor);
      };

      final r = await subirPedidosPendentes(vendedorCodigo: '0003');

      expect(r.enviados, 1);
      final enviadoId = srv.gravacoes.single['id_aparelho'] as String;
      expect(enviadoId.length, 36);
      expect(guardadoNoEnvio, enviadoId, reason: 'gravado no SQLite antes de enviar');
      final l = (await _porNumero('30')).single;
      expect(l['id_aparelho'], enviadoId);
      expect(l['pendente_envio'], 0);
    });

    test('falha de rede deixa pendente', () async {
      gravarPedidoNoServidor =
          (p, {int? idServidor}) async => throw const SocketException('sem rede');
      final r = await gravarPedidoEEnviar(_pedido(numero: '17'), novo: true);
      expect(r, ResultadoGravacao.pendente);
      final l = (await _porNumero('17')).single;
      expect(l['pendente_envio'], 1);
      expect(l['erro_envio'], isNull);
    });
  });

  // ---------------------------------------------------- correções (rodada 1)

  group('rodada 1', () {
    Future<void> pedidoJaEnviado500() async {
      final db = await getDb();
      await db.insert('pedidos', {
        'id': 500, 'numero': '9', 'vendedor_codigo': '0003', 'status': 'salvo',
        'pendente_envio': 0, 'id_aparelho': 'x', 'total': 40.0,
        'datahora': '2026-11-22T10:00:00Z', 'cliente_nome': 'Cliente antigo',
      });
    }

    test('pedido novo com o numero de um pedido ja enviado nao sobrescreve', () async {
      await pedidoJaEnviado500();
      final db = await getDb();
      final antes = (await db.query('pedidos', where: 'id = 500')).single;

      await expectLater(
          salvarPedidoLocal(_pedido(numero: '9', total: 5.0)), throwsA(isA<NumeroEmUso>()));

      var envios = 0;
      await expectLater(
        gravarPedidoEEnviar(_pedido(numero: '9', total: 5.0), novo: true,
            enviar: (p) async => envios++),
        throwsA(isA<NumeroEmUso>()),
      );
      expect(envios, 0);

      final linhas = await db.query('pedidos');
      expect(linhas, hasLength(1), reason: 'nada foi gravado nem apagado');
      expect(linhas.single, antes, reason: 'a linha 500 continua igual');
    });

    test('pedido novo ainda reaproveita a linha nunca enviada de mesmo numero', () async {
      await salvarPedidoLocal(_pedido(numero: '9', total: 5.0));
      final db = await getDb();
      final id1 = (await db.query('pedidos')).single['id'];
      await salvarPedidoLocal(_pedido(numero: '9', total: 7.0));
      final rows = await db.query('pedidos');
      expect(rows, hasLength(1));
      expect(rows.single['id'], id1);
      expect(rows.single['total'], 7.0);
    });

    test('trocar o numero para o de outra linha nao apaga a outra', () async {
      await pedidoJaEnviado500();
      await salvarPedidoLocal(_pedido(id: kLocalIdBase + 1, numero: '10'));
      await expectLater(
          atualizarPedidoLocal(_pedido(id: kLocalIdBase + 1, numero: '9')),
          throwsA(isA<NumeroEmUso>()));
      await expectLater(salvarPedidoLocal(_pedido(id: kLocalIdBase + 1, numero: '9')),
          throwsA(isA<NumeroEmUso>()));
      expect((await _porId(500))!['total'], 40.0);
      expect((await _porId(kLocalIdBase + 1))!['numero'], '10');
    });

    test('pedido ja enviado com numero trocado atualiza a mesma linha do servidor',
        () async {
      srv.linhas.add({..._pedido(numero: '20', idAparelho: 'a'), 'id': 45});
      await salvarPedidoLocal(_pedido(id: 45, numero: '20', idAparelho: 'a'));

      final r = await gravarPedidoEEnviar(
          _pedido(id: 45, numero: '21', datahora: '2026-11-23T11:00:00Z'),
          novo: false);

      expect(r, ResultadoGravacao.enviado);
      expect(srv.inserts, isEmpty, reason: 'sem insert de outra linha');
      expect(srv.linhas, hasLength(1));
      expect(srv.linhas.single['id'], 45);
      expect(srv.linhas.single['numero'], '21');
      final l = (await _porNumero('21')).single;
      expect(l['id'], 45);
      expect(l['pendente_envio'], 0);
      expect(await _porNumero('20'), isEmpty);
    });

    test('erro_envio numero some ao regravar com numero livre', () async {
      await salvarPedidoLocal(
          {..._pedido(id: kLocalIdBase + 1, numero: '5', idAparelho: 'a'), 'erro_envio': 'numero'});
      gravarPedidoNoServidor =
          (p, {int? idServidor}) async => throw const SocketException('sem rede');

      final r = await gravarPedidoEEnviar(
          _pedido(id: kLocalIdBase + 1, numero: '25', datahora: '2026-11-23T11:00:00Z'),
          novo: false);

      expect(r, ResultadoGravacao.pendente);
      final l = (await _porId(kLocalIdBase + 1))!;
      expect(l['erro_envio'], isNull);
      expect(l['pendente_envio'], 1);

      final chamados = <String>[];
      final s = await subirPedidosPendentes(
          vendedorCodigo: '0003', enviar: (p) async => chamados.add('${p['numero']}'));
      expect(chamados, ['25']);
      expect(s.numeroEmUso, 0);
    });

    test('fechado no servidor com mesma situacao e itens mas outra datahora guarda copia',
        () async {
      // Edição de cliente/anotação de um pedido que o Controle já finalizou:
      // mesmos itens, total e situação; o gatilho devolve a versão antiga.
      final enviado = {
        ..._pedido(id: 42, status: 'finalizado', datahora: '2026-11-23T11:00:00Z'),
        'cliente_nome': 'Nome corrigido',
        'cliente_anotacao': 'Entregar na portaria',
      };
      await salvarPedidoLocal(enviado);
      final remoto = {
        ..._pedido(id: 42, status: 'finalizado', datahora: '2026-11-23T10:00:00+00:00'),
        'finalizado_manual': true,
      };

      expect(decidirEco(enviado, enviado, remoto), ResultadoEco.servidorFechou);
      final r = await aplicarEcoDoServidor(enviado: enviado, remoto: remoto);

      expect(r, ResultadoEco.servidorFechou);
      expect(await _descartados(), 1);
      final db = await getDb();
      final copia = jsonDecode(
              (await db.query('pedidos_descartados')).single['pedido_json'] as String)
          as Map<String, dynamic>;
      expect(copia['cliente_anotacao'], 'Entregar na portaria');
      expect((await _porId(42))!['cliente_nome'], 'Cliente');
    });

    test('fechado no servidor igual ao enviado (mesma datahora) aplica sem copia', () {
      final f = _pedido(id: 42, status: 'finalizado', datahora: '2026-11-23T11:00:00Z');
      expect(
          decidirEco(f, f, {...f, 'datahora': '2026-11-23T11:00:00+00:00'}),
          ResultadoEco.aplicado);
    });
  });

  test('montarPayloadPedido tira campos locais e de auditoria', () {
    final p = montarPayloadPedido({
      ..._pedido(id: 40, idAparelho: 'a'),
      'produtos': jsonEncode([
        {'nome': 'Pudim', 'preco': 10, 'quantidade': 1, 'subtotal': 10},
      ]),
      'so_local': 0,
      'erro_envio': 'numero',
      'pendente_envio': 1,
      'assinatura_path': '/x.png',
      'enviado_em': 'x',
      'alterado_em': 'x',
      'finalizado_em': 'x',
      'finalizado_por': 'x',
      'finalizado_manual': 'true',
      'cancelado_em': 'x',
      'cancelado_por': 'x',
      'cliente_email': 'a@b',
    });
    expect(p['id_aparelho'], 'a');
    expect(p['status'], 'salvo');
    expect(p['numero'], '5');
    expect(p['produtos'], isA<List>());
    for (final c in const [
      'id', 'so_local', 'erro_envio', 'pendente_envio', 'assinatura_path',
      'enviado_em', 'alterado_em', 'finalizado_em', 'finalizado_por',
      'finalizado_manual', 'cancelado_em', 'cancelado_por', 'cliente_email',
    ]) {
      expect(p.containsKey(c), isFalse, reason: c);
    }
  });
}
