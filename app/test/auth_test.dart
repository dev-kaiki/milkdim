// test/auth_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/auth.dart';
import 'package:milkdim_app/utils/db.dart';

Future<void> _limpar() async {
  await fecharDbParaTeste();
  await databaseFactory
      .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
}

void main() {
  group('emailDoCodigo', () {
    test('tira espacos e usa o dominio tecnico', () {
      expect(emailDoCodigo(' 0003 '), '0003@milkdim.local');
    });
    test('minusculas e sem completar zeros', () {
      expect(emailDoCodigo('ABC'), 'abc@milkdim.local');
      expect(emailDoCodigo('3'), '3@milkdim.local');
    });
  });

  group('rotaInicial', () {
    test('com sessao salva vai para a Home (mesmo vencida/offline)', () {
      expect(rotaInicial(temSessao: true), RotaInicial.home);
    });
    test('sem sessao vai para o login', () {
      expect(rotaInicial(temSessao: false), RotaInicial.login);
    });
  });

  group('SQLite', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('auth_test');
      await databaseFactory.setDatabasesPath(dir.path);
    });

    setUp(_limpar);
    tearDownAll(_limpar);

    test('vendedorLocal devolve null sem vendedor e a linha depois de salvar', () async {
      expect(await vendedorLocal(), isNull);
      await salvarVendedorLocal({'id': 7, 'codigo': '0003', 'nome': 'Fulano', 'ativo': true});
      final v = await vendedorLocal();
      expect(v, isNotNull);
      expect(v!['codigo'], '0003');
      expect(v['nome'], 'Fulano');
    });

    test('bloqueioLogin recusa codigo diferente do dono dos pendentes', () async {
      await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0003'});
      expect(await bloqueioLogin('0004'),
          'Há pedidos do vendedor 0003 aguardando envio neste aparelho.');
    });

    test('bloqueioLogin deixa o proprio dono entrar (com espacos)', () async {
      await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0003'});
      expect(await bloqueioLogin(' 0003 '), isNull);
    });

    test('bloqueioLogin sem pendentes deixa qualquer um entrar', () async {
      await salvarPedidoLocal({'numero': '1', 'status': 'salvo', 'vendedor_codigo': '0003'});
      expect(await bloqueioLogin('0004'), isNull);
    });

    test('bloqueioSair recusa enquanto o vendedor local tem pendentes', () async {
      await salvarVendedorLocal({'codigo': '0003', 'nome': 'Fulano', 'ativo': 1});
      expect(await bloqueioSair(), isNull);
      await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0003'});
      expect(await bloqueioSair(), isNotNull);
    });

    group('concluirEntrada (depois do signIn)', () {
      late int signOuts;
      Future<void> signOutOk() async => signOuts++;
      Future<void> signOutOffline() async {
        signOuts++;
        throw Exception('sem internet no signOut');
      }

      setUp(() => signOuts = 0);

      test('busca do vendedor que lanca encerra a sessao e propaga o erro', () async {
        final erro = Exception('timeout');
        await expectLater(
          concluirEntrada(
            codigoDigitado: '0003',
            buscarVendedor: () async => throw erro,
            encerrarSessao: signOutOk,
          ),
          throwsA(same(erro)),
        );
        expect(signOuts, 1);
        expect(await vendedorLocal(), isNull);
      });

      test('signOut offline nao troca o erro original', () async {
        final erro = Exception('PostgREST');
        await expectLater(
          concluirEntrada(
            codigoDigitado: '0003',
            buscarVendedor: () async => throw erro,
            encerrarSessao: signOutOffline,
          ),
          throwsA(same(erro)),
        );
        expect(signOuts, 1);
      });

      test('conta sem vendedor: LoginRecusado mesmo com signOut offline', () async {
        await expectLater(
          concluirEntrada(
            codigoDigitado: '0003',
            buscarVendedor: () async => null,
            encerrarSessao: signOutOffline,
          ),
          throwsA(isA<LoginRecusado>()),
        );
        expect(signOuts, 1);
      });

      test('codigo real com pendentes de outro: recusa e encerra a sessao', () async {
        await salvarPedidoLocal({'numero': '1', 'status': 'finalizado', 'vendedor_codigo': '0004'});
        await expectLater(
          concluirEntrada(
            codigoDigitado: '0004',
            buscarVendedor: () async => {'id': 1, 'codigo': '0003', 'nome': 'A', 'ativo': true},
            encerrarSessao: signOutOk,
          ),
          throwsA(isA<LoginRecusado>()),
        );
        expect(signOuts, 1);
        expect(await vendedorLocal(), isNull);
      });

      test('sucesso salva o vendedor local e mantem a sessao', () async {
        final v = await concluirEntrada(
          codigoDigitado: '0003',
          buscarVendedor: () async => {'id': 1, 'codigo': '0003', 'nome': 'A', 'ativo': true},
          encerrarSessao: signOutOk,
        );
        expect(v['codigo'], '0003');
        expect(signOuts, 0);
        expect((await vendedorLocal())!['codigo'], '0003');
      });
    });
  });
}
