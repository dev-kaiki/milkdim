import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/models/producao.dart';
import 'package:milkdim_admin/services/supabase_service.dart';

Pedido _p(int id, String status, List<(String, int)> itens) => Pedido(
      id: id,
      status: status,
      total: 0,
      itens: [
        for (final (n, q) in itens) PedidoItem(nome: n, preco: 1, quantidade: q),
      ],
    );

List<(String, int)> _r(List<TotalProduto> l) =>
    l.map((t) => (t.nome, t.quantidade)).toList();

void main() {
  test('totaisAFabricar soma por produto so dos abertos', () {
    final r = totaisAFabricar([
      _p(1, 'salvo', [('Pudim tradicional', 10), ('Leite ninho', 4)]),
      _p(2, 'salvo', [('Pudim tradicional', 5)]),
      _p(3, 'finalizado', [('Leite ninho', 99)]),
      _p(4, 'cancelado', [('Leite ninho', 50)]),
    ]);
    expect(_r(r), [('Pudim tradicional', 15), ('Leite ninho', 4)]);
  });

  test('pronto nao entra em A fabricar', () {
    final r = totaisAFabricar([
      _p(1, 'salvo', [('Pudim', 2)]),
      _p(2, 'pronto', [('Pudim', 50), ('Leite ninho', 9)]),
    ]);
    expect(_r(r), [('Pudim', 2)]);
  });

  test('empate ordena por nome', () {
    final r = totaisAFabricar([
      _p(1, 'salvo', [('Zebra', 3), ('Abacaxi', 3), ('Maior', 7)]),
    ]);
    expect(_r(r), [('Maior', 7), ('Abacaxi', 3), ('Zebra', 3)]);
  });

  test('nome com espacos agrupa', () {
    final r = totaisAFabricar([
      _p(1, 'salvo', [('Leite ninho ', 2), ('Leite ninho', 3)]),
    ]);
    expect(_r(r), [('Leite ninho', 5)]);
  });

  test('situacaoTexto', () {
    expect(_p(1, 'salvo', []).situacaoTexto, 'Em aberto');
    expect(_p(1, 'pronto', []).situacaoTexto, 'Pronto para entrega');
    expect(_p(1, 'finalizado', []).situacaoTexto, 'Entregue');
    expect(_p(1, 'cancelado', []).situacaoTexto, 'Cancelado');
    expect(_p(1, 'xyz', []).situacaoTexto, 'xyz');
  });

  test('alteradoDepoisDeEnviar', () {
    final e = DateTime.utc(2026, 11, 1, 10);
    expect(
        Pedido(
          id: 1,
          itens: const [],
          total: 0,
          status: 'salvo',
          enviadoEm: e,
          alteradoEm: e.add(const Duration(minutes: 5)),
        ).alteradoDepoisDeEnviar,
        isTrue);
    expect(
        Pedido(id: 1, itens: const [], total: 0, status: 'salvo', enviadoEm: e)
            .alteradoDepoisDeEnviar,
        isFalse);
    expect(
        Pedido(
          id: 1,
          itens: const [],
          total: 0,
          status: 'salvo',
          enviadoEm: e,
          alteradoEm: e,
        ).alteradoDepoisDeEnviar,
        isFalse);
  });

  test('alteradoDepoisDePronto', () {
    final e = DateTime.utc(2026, 11, 1, 10);
    Pedido ped(String status, DateTime? pronto, DateTime? alt) => Pedido(
        id: 1, itens: const [], total: 0, status: status, prontoEm: pronto, alteradoEm: alt);
    expect(ped('salvo', e, e.add(const Duration(minutes: 5))).alteradoDepoisDePronto, isTrue);
    expect(ped('salvo', e, e).alteradoDepoisDePronto, isFalse);
    expect(ped('salvo', null, e).alteradoDepoisDePronto, isFalse);
    expect(ped('pronto', e, e.add(const Duration(minutes: 5))).alteradoDepoisDePronto, isFalse);
  });

  test('fromMap guarda alterado_em bruto, pronto_em/por e as duas assinaturas', () {
    const bruto = '2026-11-23T10:00:00.123456+00:00';
    final p = Pedido.fromMap({
      'id': 1,
      'status': 'pronto',
      'alterado_em': bruto,
      'pronto_em': '2026-11-23T11:00:00+00:00',
      'pronto_por': 'Fábrica',
      'assinatura_pedido': '\\x89504e47',
      'assinatura': '\\x89504e48',
    });
    expect(p.alteradoEmBruto, bruto);
    expect(p.prontoEm, DateTime.utc(2026, 11, 23, 11));
    expect(p.prontoPor, 'Fábrica');
    expect(p.assinaturaPedidoBytes, isNotNull);
    expect(p.assinaturaBytes, isNotNull);
    expect(p.assinaturaPedidoBytes, isNot(p.assinaturaBytes));
    expect(Pedido.fromMap({'id': 2}).alteradoEmBruto, isNull);
  });

  test('paramsMarcarPronto leva o alterado_em exatamente como veio (ou null)', () {
    const bruto = '2026-11-23T10:00:00.123456+00:00';
    expect(SupabaseService.paramsMarcarPronto(5, bruto), {'p_id': 5, 'p_alterado_em': bruto});
    final m = SupabaseService.paramsMarcarPronto(5, null);
    expect(m.containsKey('p_alterado_em'), isTrue);
    expect(m['p_alterado_em'], isNull);
  });

  test('fromMap le campos de auditoria', () {
    final p = Pedido.fromMap({
      'id': 1,
      'status': 'finalizado',
      'enviado_em': '2026-11-01T10:00:00Z',
      'finalizado_em': '2026-11-02T10:00:00Z',
      'finalizado_por': 'admin',
      'finalizado_manual': 'true',
      'cancelado_em': null,
    });
    expect(p.enviadoEm, DateTime.utc(2026, 11, 1, 10));
    expect(p.finalizadoEm, DateTime.utc(2026, 11, 2, 10));
    expect(p.finalizadoPor, 'admin');
    expect(p.finalizadoManual, isTrue);
    expect(p.canceladoEm, isNull);
    expect(Pedido.fromMap({'id': 2, 'finalizado_manual': 1}).finalizadoManual, isTrue);
    expect(Pedido.fromMap({'id': 3}).finalizadoManual, isFalse);
  });

  test('filtroSituacao', () {
    expect(filtroSituacao(null), '');
    expect(filtroSituacao('todos'), '');
    expect(filtroSituacao('salvo'), 'salvo');
  });

  test('mensagemErroRpcPedido', () {
    expect(mensagemErroRpcPedido('42501'), 'Sem permissão para essa ação.');
    expect(mensagemErroRpcPedido('55000'), 'Esse pedido não está mais em aberto.');
    expect(mensagemErroRpcPedido('MD001'),
        'O pedido mudou depois que a tela foi atualizada. Atualize e confira.');
    expect(mensagemErroRpcPedido('P0002'), 'Pedido não encontrado.');
    expect(mensagemErroRpcPedido('x'), 'Erro ao atualizar pedido.');
    expect(mensagemErroRpcPedido(null), 'Erro ao atualizar pedido.');
  });
}
