// lib/utils/entrega_qr.dart
//
// Fase B: o que fazer depois de ler o QR da etiqueta e as chamadas das RPCs
// `pedido_por_qr` e `pedido_entregar_por_qr`.
import 'dart:typed_data';

import 'package:milkdim_ui/milkdim_ui.dart' show codigoDoQrEntrega;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'convert.dart';
import 'db.dart';
import 'supabase_helper.dart';

// ---------------------- Decisão depois da leitura ----------------------

sealed class DestinoLeitura {
  const DestinoLeitura();
}

/// O conteúdo lido não é de uma etiqueta da MilkDim.
class QrInvalido extends DestinoLeitura {
  const QrInvalido();
}

/// O código bate com um pedido do celular: abre o fluxo atual de entrega.
class AbrirPedidoLocal extends DestinoLeitura {
  final Map<String, dynamic> pedido;
  const AbrirPedidoLocal(this.pedido);
}

/// Pedido que não está no celular: a tela "Entrega de pedido" consulta o servidor.
class AbrirEntregaServidor extends DestinoLeitura {
  final String codigoQr;
  const AbrirEntregaServidor(this.codigoQr);
}

class SemInternet extends DestinoLeitura {
  const SemInternet();
}

/// Ordem: QR inválido, pedido local do vendedor logado (mesmo aguardando
/// envio), internet ou não. Pedido de outro vendedor guardado no celular não
/// abre como local: vai pelo servidor, que aplica a regra de "só pronto" e
/// registra quem entregou.
Future<DestinoLeitura> decidirDestinoDaLeitura(
  String lido, {
  required String vendedorCodigo,
  Future<bool> Function()? internet,
}) async {
  final codigo = codigoDoQrEntrega(lido);
  if (codigo == null) return const QrInvalido();
  final local = await buscarPedidoLocalPorCodigoQr(codigo, vendedorCodigo);
  if (local != null) return AbrirPedidoLocal(local);
  if (await (internet ?? temInternet)()) return AbrirEntregaServidor(codigo);
  return const SemInternet();
}

// ---------------------- Pedido lido pelo QR ----------------------

String? _t(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

class PedidoQr {
  final int? id;
  final String numero;
  final String status;
  final String? vendedorCodigo;
  final String? vendedorNome;
  final String? clienteNome;
  final String? clienteNomeFantasia;
  final String? cidade;
  final List<({String nome, int quantidade})> itens;
  final bool doProprioVendedor;

  const PedidoQr({
    this.id,
    required this.numero,
    required this.status,
    this.vendedorCodigo,
    this.vendedorNome,
    this.clienteNome,
    this.clienteNomeFantasia,
    this.cidade,
    this.itens = const [],
    this.doProprioVendedor = false,
  });

  /// Nome fantasia, ou o nome do cliente quando não há fantasia.
  String get clienteTitulo => clienteNomeFantasia ?? clienteNome ?? '';

  /// Aceita também a forma reduzida (só `numero` e `status`) de pedido
  /// entregue ou cancelado.
  factory PedidoQr.fromJson(Map<String, dynamic> j) {
    final itens = <({String nome, int quantidade})>[];
    final brutos = j['itens'];
    if (brutos is List) {
      for (final it in brutos) {
        if (it is! Map) continue;
        final q = it['quantidade'];
        itens.add((
          nome: (it['nome'] ?? '').toString(),
          quantidade: q is num ? q.toInt() : int.tryParse('${q ?? ''}') ?? 0,
        ));
      }
    }
    final id = j['id'];
    return PedidoQr(
      id: id is int ? id : int.tryParse('${id ?? ''}'),
      numero: (j['numero'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      vendedorCodigo: _t(j['vendedor_codigo']),
      vendedorNome: _t(j['vendedor_nome']),
      clienteNome: _t(j['cliente_nome']),
      clienteNomeFantasia: _t(j['cliente_nome_fantasia']),
      cidade: _t(j['cliente_cidade']),
      itens: itens,
      doProprioVendedor: j['do_proprio_vendedor'] == true,
    );
  }

  /// `null` quando a entrega é possível; senão, o motivo para a tela.
  String? get motivoSemEntrega {
    if (status == 'finalizado') return 'Este pedido já foi entregue.';
    if (status == 'cancelado') return 'Este pedido foi cancelado.';
    if (!doProprioVendedor && status != 'pronto') {
      return 'Este pedido ainda não está pronto para entrega.';
    }
    return null;
  }
}

// ---------------------- RPCs ----------------------

class FalhaEntregaQr implements Exception {
  final String mensagem;
  const FalhaEntregaQr(this.mensagem);
  @override
  String toString() => 'FalhaEntregaQr($mensagem)';
}

const String _msgFalhaGeral = 'Não deu para confirmar a entrega. Leia a etiqueta de novo.';

String mensagemErroEntregaQr(String? code) => switch (code) {
      'P0002' => 'Pedido não encontrado.',
      'MD002' => 'Este pedido já foi entregue.',
      'MD003' => 'Este pedido ainda não está pronto para entrega.',
      'MD004' => 'Este pedido foi cancelado.',
      _ => _msgFalhaGeral,
    };

Future<Map<String, dynamic>> _rpcPedidoPorQrSupabase(String codigoQr) async {
  final r = await supabase.rpc('pedido_por_qr', params: {'p_codigo': codigoQr});
  return Map<String, dynamic>.from(r as Map);
}

Future<Map<String, dynamic>> _rpcEntregarPorQrSupabase(
    String codigoQr, String assinaturaHex) async {
  final r = await supabase.rpc('pedido_entregar_por_qr',
      params: {'p_codigo': codigoQr, 'p_assinatura': assinaturaHex});
  return Map<String, dynamic>.from(r as Map);
}

/// Trocáveis nos testes (mesmo padrão de `buscarRemotoPorId`).
Future<Map<String, dynamic>> Function(String codigoQr) rpcPedidoPorQr =
    _rpcPedidoPorQrSupabase;
Future<Map<String, dynamic>> Function(String codigoQr, String assinaturaHex)
    rpcEntregarPorQr = _rpcEntregarPorQrSupabase;

String? _codigoDoErro(Object e) => e is PostgrestException ? e.code : null;

Future<PedidoQr> buscarPedidoPorQr(String codigoQr) async {
  try {
    return PedidoQr.fromJson(await rpcPedidoPorQr(codigoQr));
  } catch (e) {
    final code = _codigoDoErro(e);
    throw FalhaEntregaQr(code == 'P0002'
        ? mensagemErroEntregaQr(code)
        : 'Não deu para ler o pedido. Leia a etiqueta de novo.');
  }
}

/// Registra a entrega no servidor. Nada é gravado no banco local.
/// A assinatura vai como `\x` + hex (bytea), o mesmo formato dos envios.
Future<void> entregarPorQr(String codigoQr, Uint8List assinaturaPng) async {
  try {
    await rpcEntregarPorQr(codigoQr, bytesToPgByteaHex(assinaturaPng));
  } catch (e) {
    throw FalhaEntregaQr(mensagemErroEntregaQr(_codigoDoErro(e)));
  }
}
