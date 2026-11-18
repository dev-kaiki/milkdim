// lib/utils/auth.dart
//
// Sessão do vendedor via Supabase Auth (`<codigo>@milkdim.local`).
// - Pedido local nunca é apagado por login, logout ou sessão expirada.
// - Outro vendedor não entra num aparelho com pedidos de alguém aguardando envio.
// - "Sair" fica bloqueado enquanto o vendedor tiver pedido finalizado sem enviar.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'db.dart';

/// E-mail técnico do vendedor no Supabase Auth.
String emailDoCodigo(String codigo) => '${codigo.trim().toLowerCase()}@milkdim.local';

enum RotaInicial { login, home }

/// Decide a tela de abertura só pela existência da sessão salva
/// (nunca por `isExpired`: offline com sessão vencida ainda abre a Home).
RotaInicial rotaInicial({required bool temSessao}) =>
    temSessao ? RotaInicial.home : RotaInicial.login;

class LoginRecusado implements Exception {
  final String mensagem;
  const LoginRecusado(this.mensagem);

  @override
  String toString() => mensagem;
}

String _normCodigo(String c) => c.trim().toLowerCase();

/// Mensagem de recusa se o aparelho tem pedidos aguardando envio de outro
/// vendedor que não [codigo]; `null` se o login pode seguir.
Future<String?> bloqueioLogin(String codigo) async {
  final meu = _normCodigo(codigo);
  final outros = (await codigosComPendentesEnvio())
      .where((c) => _normCodigo(c) != meu)
      .toList()
    ..sort();
  if (outros.isEmpty) return null;
  return 'Há pedidos do vendedor ${outros.join(', ')} aguardando envio neste aparelho.';
}

/// Mensagem de recusa se o vendedor do aparelho tem pedidos aguardando envio;
/// `null` se pode sair.
Future<String?> bloqueioSair() async {
  final v = await vendedorLocal();
  final codigo = v?['codigo']?.toString();
  if (codigo == null || codigo.isEmpty) return null;
  final n = await contarPedidosPendentesEnvio(codigo);
  if (n == 0) return null;
  return n == 1
      ? 'Há 1 pedido aguardando envio. Envie antes de sair.'
      : 'Há $n pedidos aguardando envio. Envie antes de sair.';
}

/// Login online. Lança [LoginRecusado] (pendentes de outro vendedor ou conta sem
/// vendedor) ou o erro do Supabase (senha errada, sem internet).
Future<Map<String, dynamic>> entrar(String codigo, String senha) async {
  // Antes da rede: aparelho com pendentes de outro vendedor recusa já.
  final antes = await bloqueioLogin(codigo);
  if (antes != null) throw LoginRecusado(antes);

  final client = Supabase.instance.client;
  final res = await client.auth
      .signInWithPassword(email: emailDoCodigo(codigo), password: senha);
  final user = res.user;
  if (user == null) {
    throw const LoginRecusado('Login ou senha inválidos!');
  }

  return concluirEntrada(
    codigoDigitado: codigo,
    buscarVendedor: () => client
        .from('vendedores')
        .select('id, codigo, nome, ativo')
        .eq('auth_user_id', user.id)
        .maybeSingle(),
    encerrarSessao: client.auth.signOut,
  );
}

/// Passo de [entrar] depois do `signInWithPassword` (separado para testar sem
/// rede). Qualquer falha aqui encerra a sessão antes de propagar o erro: nunca
/// fica sessão salva sem vendedor local.
@visibleForTesting
Future<Map<String, dynamic>> concluirEntrada({
  required String codigoDigitado,
  required Future<Map<String, dynamic>?> Function() buscarVendedor,
  required Future<void> Function() encerrarSessao,
}) async {
  try {
    final row = await buscarVendedor();
    if (row == null) {
      throw const LoginRecusado('Conta sem vendedor cadastrado. Consulte o administrador.');
    }
    final vendedor = Map<String, dynamic>.from(row);

    // O código real pode diferir do digitado (maiúsculas): confere de novo.
    final depois = await bloqueioLogin(vendedor['codigo']?.toString() ?? codigoDigitado);
    if (depois != null) throw LoginRecusado(depois);

    await salvarVendedorLocal(vendedor);
    return vendedor;
  } catch (_) {
    // signOut offline não pode trocar a mensagem original por erro de rede.
    try {
      await encerrarSessao();
    } catch (_) {}
    rethrow;
  }
}

/// Encerra a sessão. Lança [LoginRecusado] se houver pedido aguardando envio.
/// Nunca apaga pedidos locais.
Future<void> sair() async {
  final bloqueio = await bloqueioSair();
  if (bloqueio != null) throw LoginRecusado(bloqueio);
  await Supabase.instance.client.auth.signOut();
}

/// O vendedor guardado no aparelho (há no máximo um).
Future<Map<String, dynamic>?> vendedorLocal() async {
  final db = await getDb();
  final rows = await db.query('vendedores', limit: 1);
  return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
}
