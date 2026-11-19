// test/login_msg_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:milkdim_app/pages/login_page.dart';
import 'package:milkdim_app/utils/auth.dart';

void main() {
  group('mensagemErroLogin', () {
    test('LoginRecusado usa a mensagem dele (mesmo offline)', () {
      const e = LoginRecusado('Há pedidos do vendedor 0002 aguardando envio neste aparelho.');
      expect(mensagemErroLogin(e, online: true), e.mensagem);
      expect(mensagemErroLogin(e, online: false), e.mensagem);
    });

    test('offline: primeiro acesso precisa de internet', () {
      expect(
        mensagemErroLogin(AuthRetryableFetchException(), online: false),
        'O primeiro acesso precisa de internet.',
      );
      expect(
        mensagemErroLogin(const AuthException('Invalid login credentials', statusCode: '400'),
            online: false),
        'O primeiro acesso precisa de internet.',
      );
    });

    test('AuthException 400: código ou senha inválidos', () {
      expect(
        mensagemErroLogin(
            AuthApiException('Invalid login credentials',
                statusCode: '400', code: 'invalid_credentials'),
            online: true),
        'Código ou senha inválidos.',
      );
    });

    test('banido: vendedor inativo', () {
      expect(
        mensagemErroLogin(
            AuthApiException('User is banned', statusCode: '400', code: 'user_banned'),
            online: true),
        'Vendedor inativo. Fale com o administrador.',
      );
      expect(
        mensagemErroLogin(const AuthException('user banned'), online: true),
        'Vendedor inativo. Fale com o administrador.',
      );
    });

    test('outro erro: tente de novo', () {
      expect(mensagemErroLogin(Exception('boom'), online: true),
          'Não foi possível entrar. Tente de novo.');
      expect(mensagemErroLogin(AuthRetryableFetchException(), online: true),
          'Não foi possível entrar. Tente de novo.');
      expect(
          mensagemErroLogin(const AuthException('Erro interno', statusCode: '500'),
              online: true),
          'Não foi possível entrar. Tente de novo.');
    });
  });
}
