// test/prazo_envio_test.dart
//
// Salvar pedido não fica preso na rede: a conferência do número no servidor
// tem prazo (sem resposta = livre, regra do offline) e a tela não espera o
// envio além do prazo (o pedido já está gravado e pendente).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';
import 'package:milkdim_app/widgets/pedido_ui.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

Map<String, dynamic> _pedido(String numero) => {
      'numero': numero,
      'status': 'salvo',
      'vendedor_codigo': '0003',
      'datahora': '2026-11-23T10:00:00Z',
      'total': 10.0,
      'cliente_nome': 'Cliente',
      'produtos': [
        {'nome': 'Pudim', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
      ],
      'so_local': 0,
    };

void main() {
  final buscaOriginal = buscarRemotoPorNumero;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('prazo_envio_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(_limpar);
  tearDown(() => buscarRemotoPorNumero = buscaOriginal);
  tearDownAll(_limpar);

  test('prazos: 3 s para conferir o numero, 10 s para o envio na tela', () {
    expect(kPrazoConsultaNumero, const Duration(seconds: 3));
    expect(kPrazoEnvioNaTela, const Duration(seconds: 10));
  });

  group('conferencia do numero', () {
    test('servidor que nao responde: livre dentro do prazo', () async {
      final nunca = Completer<Map<String, dynamic>?>();
      buscarRemotoPorNumero = (n, v) => nunca.future;

      final relogio = Stopwatch()..start();
      final livre = await numeroLivreNoServidor('7', '0003',
          prazo: const Duration(milliseconds: 200));

      expect(livre, isTrue, reason: 'sem resposta vale a regra do offline');
      expect(relogio.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('numeroLivreParaVendedor tambem respeita o prazo', () async {
      buscarRemotoPorNumero = (n, v) => Completer<Map<String, dynamic>?>().future;
      final relogio = Stopwatch()..start();
      expect(
          await numeroLivreParaVendedor('7', '0003',
              prazo: const Duration(milliseconds: 200)),
          isTrue);
      expect(relogio.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('servidor que responde a tempo continua valendo', () async {
      buscarRemotoPorNumero = (n, v) async => {'id': 1, 'id_aparelho': null};
      expect(await numeroLivreNoServidor('7', '0003'), isFalse);
    });

    test('sugestao do proximo numero: o prazo e do total, nao por tentativa', () async {
      // Servidor lento que diz "ocupado" a cada consulta: sem prazo total
      // seriam 20 x 150 ms.
      var consultas = 0;
      buscarRemotoPorNumero = (n, v) async {
        consultas++;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return {'id': 1, 'id_aparelho': null};
      };

      final relogio = Stopwatch()..start();
      final n = await proximoNumeroLivreDoVendedor('0003',
          prazo: const Duration(milliseconds: 400));

      expect(relogio.elapsed, lessThan(const Duration(milliseconds: 1500)));
      expect(n, isNotNull, reason: 'esgotado o prazo, vale o número livre no aparelho');
      expect(consultas, lessThan(20));
    });
  });

  group('envio da tela com prazo', () {
    test('envio que nao termina: pendente no prazo, pedido gravado', () async {
      final nunca = Completer<void>();
      final relogio = Stopwatch()..start();
      final r = await gravarPedidoEEnviar(_pedido('70'),
          novo: true,
          enviar: (p) => nunca.future,
          prazoEnvio: const Duration(milliseconds: 200));

      expect(r, ResultadoGravacao.pendente);
      expect(relogio.elapsed, lessThan(const Duration(seconds: 2)));
      final db = await getDb();
      final l = (await db.query('pedidos', where: 'numero = ?', whereArgs: ['70'])).single;
      expect(l['pendente_envio'], 1, reason: 'continua aguardando envio');
      expect(l['status'], 'salvo');
    });

    test('envio que termina depois do prazo com numero em uso ainda marca o erro',
        () async {
      final libera = Completer<void>();
      final r = await gravarPedidoEEnviar(_pedido('71'),
          novo: true,
          enviar: (p) async {
            await libera.future;
            throw const NumeroEmUso('71', '0003');
          },
          prazoEnvio: const Duration(milliseconds: 100));
      expect(r, ResultadoGravacao.pendente);

      libera.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final db = await getDb();
      final l = (await db.query('pedidos', where: 'numero = ?', whereArgs: ['71'])).single;
      expect(l['erro_envio'], kErroNumeroEmUso);
      expect(l['pendente_envio'], 1);
    });

    test('envio rapido continua enviado', () async {
      final r = await gravarPedidoEEnviar(_pedido('72'), novo: true, enviar: (p) async {});
      expect(r, ResultadoGravacao.enviado);
    });
  });

  testWidgets('barra do resumo mostra o progresso enquanto grava', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const Scaffold(
        bottomNavigationBar: BarraResumo(total: 10, onPressed: null, ocupado: true),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(bottomNavigationBar: BarraResumo(total: 10, onPressed: () {})),
    ));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
