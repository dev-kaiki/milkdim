import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/services/auth_admin.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('emailDoUsuario', () {
    test('usuario simples', () {
      expect(emailDoUsuario('kaiki'), 'kaiki@milkdim.local');
    });
    test('trim e minusculas', () {
      expect(emailDoUsuario(' Kaiki '), 'kaiki@milkdim.local');
    });
    test('com @ usa como esta (trim)', () {
      expect(emailDoUsuario('kaiki@milkdim.local'), 'kaiki@milkdim.local');
      expect(emailDoUsuario(' a@b.com '), 'a@b.com');
    });
  });

  group('concluirEntradaAdmin', () {
    test('rpc false: signOut e AcessoNegado', () async {
      var saiu = 0;
      await expectLater(
        concluirEntradaAdmin(
          rpc: () async => false,
          encerrarSessao: () async => saiu++,
        ),
        throwsA(isA<AcessoNegado>()),
      );
      expect(saiu, 1);
    });

    test('rpc lanca: signOut e erro original', () async {
      var saiu = 0;
      final erro = StateError('rede');
      await expectLater(
        concluirEntradaAdmin(
          rpc: () async => throw erro,
          encerrarSessao: () async => saiu++,
        ),
        throwsA(same(erro)),
      );
      expect(saiu, 1);
    });

    test('signOut offline nao troca o erro original', () async {
      final erro = StateError('rede');
      await expectLater(
        concluirEntradaAdmin(
          rpc: () async => throw erro,
          encerrarSessao: () async => throw const SocketException('x'),
        ),
        throwsA(same(erro)),
      );
    });

    test('rpc true: nao desloga', () async {
      var saiu = 0;
      await concluirEntradaAdmin(
        rpc: () async => true,
        encerrarSessao: () async => saiu++,
      );
      expect(saiu, 0);
    });
  });

  group('mensagemErroLoginAdmin', () {
    test('credenciais invalidas', () {
      expect(
        mensagemErroLoginAdmin(
            const AuthException('Invalid login credentials', statusCode: '400')),
        'Usuário ou senha inválidos.',
      );
    });
    test('banido', () {
      expect(
        mensagemErroLoginAdmin(
            const AuthException('User is banned', statusCode: '400')),
        'Acesso desativado.',
      );
    });
    test('offline', () {
      expect(mensagemErroLoginAdmin(const SocketException('x')),
          'Não foi possível entrar. Verifique a internet.');
      expect(mensagemErroLoginAdmin(StateError('y')),
          'Não foi possível entrar. Verifique a internet.');
    });
    test('AcessoNegado', () {
      expect(mensagemErroLoginAdmin(const AcessoNegado()),
          'Sem acesso ao controle.');
    });
  });

  group('sessaoAindaEhAdmin', () {
    test('rpc false: nao e mais admin', () async {
      expect(await sessaoAindaEhAdmin(rpc: () async => false), isFalse);
    });
    test('rpc true: segue', () async {
      expect(await sessaoAindaEhAdmin(rpc: () async => true), isTrue);
    });
    test('rpc lanca (rede): mantem a sessao', () async {
      expect(
        await sessaoAindaEhAdmin(rpc: () async => throw const SocketException('x')),
        isTrue,
      );
    });
  });
}
