// Sessão do app de controle via Supabase Auth (`<usuario>@milkdim.local`).
// Depois do login, `app_is_admin()` precisa ser true; senão a sessão é encerrada.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// E-mail técnico do admin. Com `@` vale como digitado.
String emailDoUsuario(String usuario) {
  final u = usuario.trim();
  if (u.contains('@')) return u;
  return '${u.toLowerCase()}@milkdim.local';
}

class AcessoNegado implements Exception {
  const AcessoNegado();
  String get mensagem => 'Sem acesso ao controle.';

  @override
  String toString() => mensagem;
}

/// Login online. Lança [AcessoNegado] se a conta não é admin, ou o erro do
/// Supabase (credenciais, conta desativada, sem internet).
Future<void> entrarAdmin(String usuario, String senha) async {
  final client = Supabase.instance.client;
  await client.auth
      .signInWithPassword(email: emailDoUsuario(usuario), password: senha);
  await concluirEntradaAdmin(
    rpc: () async => (await client.rpc('app_is_admin')) == true,
    encerrarSessao: client.auth.signOut,
  );
}

/// Passo de [entrarAdmin] depois do `signInWithPassword` (separado para testar
/// sem rede). Qualquer falha encerra a sessão antes de propagar o erro.
@visibleForTesting
Future<void> concluirEntradaAdmin({
  required Future<bool> Function() rpc,
  required Future<void> Function() encerrarSessao,
}) async {
  try {
    if (!await rpc()) throw const AcessoNegado();
  } catch (_) {
    // signOut offline não pode trocar a mensagem original por erro de rede.
    try {
      await encerrarSessao();
    } catch (_) {}
    rethrow;
  }
}

/// Reconfere `app_is_admin()` para uma sessão já salva (ex.: app fechado entre o
/// login e a checagem). Só devolve false se o servidor responder false; erro de
/// rede mantém a sessão.
Future<bool> sessaoAindaEhAdmin({Future<dynamic> Function()? rpc}) async {
  try {
    final r = await (rpc ?? () => Supabase.instance.client.rpc('app_is_admin'))();
    return r != false;
  } catch (_) {
    return true;
  }
}

Future<void> sairAdmin() => Supabase.instance.client.auth.signOut();

/// Mensagem para mostrar na tela de login.
String mensagemErroLoginAdmin(Object erro) {
  if (erro is AcessoNegado) return erro.mensagem;
  if (erro is AuthException) {
    if (erro.message.toLowerCase().contains('banned')) return 'Acesso desativado.';
    if (erro.statusCode == '400') return 'Usuário ou senha inválidos.';
  }
  return 'Não foi possível entrar. Verifique a internet.';
}
