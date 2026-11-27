// test/repetir_pedido_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/produto.dart';
import 'package:milkdim_app/utils/repetir_pedido.dart';

const _pote = Produto(id: 1, nome: 'Pote 160g', preco: 5);
const _copo = Produto(id: 2, nome: 'Copo', preco: 3);
const _catalogo = [_pote, _copo];

Map<String, dynamic> _p(String numero, String status, String datahora) =>
    {'numero': numero, 'status': status, 'datahora': datahora};

void main() {
  group('preencherDePedido', () {
    test('casa por nome sem caixa e espaços', () {
      final r = preencherDePedido([
        {'nome': ' pote 160G ', 'quantidade': 40},
      ], _catalogo);
      expect(r.quantidades, {_pote: 40});
      expect(r.foraDoPedido, isEmpty);
    });

    test('soma o mesmo produto repetido', () {
      final r = preencherDePedido([
        {'nome': 'Copo', 'quantidade': 2},
        {'nome': 'Copo', 'quantidade': 3},
      ], _catalogo);
      expect(r.quantidades, {_copo: 5});
    });

    test('aceita quantidade string e double, ignora zero', () {
      final r = preencherDePedido([
        {'nome': 'Pote 160g', 'quantidade': '40'},
        {'nome': 'Copo', 'quantidade': 20.0},
        {'nome': 'Geladinho', 'quantidade': 0},
      ], _catalogo);
      expect(r.quantidades, {_pote: 40, _copo: 20});
      expect(r.foraDoPedido, isEmpty);
    });

    test('produto que sumiu vai para foraDoPedido', () {
      final r = preencherDePedido([
        {'nome': 'Geladinho', 'quantidade': 10},
        {'nome': 'Geladinho', 'quantidade': 5},
      ], _catalogo);
      expect(r.quantidades, isEmpty);
      expect(r.foraDoPedido, ['Geladinho']);
    });

    test('json corrompido não quebra', () {
      for (final entrada in <Object?>['{x', null, 42]) {
        expect(preencherDePedido(entrada, _catalogo).quantidades, isEmpty);
        expect(resumoItens(entrada), 'Sem itens');
      }
    });

    test('aceita String JSON', () {
      final itens = [
        {'nome': 'Pote 160g', 'quantidade': 40},
        {'nome': 'Copo', 'quantidade': 20},
      ];
      final deString = preencherDePedido(jsonEncode(itens), _catalogo);
      final deLista = preencherDePedido(itens, _catalogo);
      expect(deString.quantidades, deLista.quantidades);
      expect(deString.quantidades, {_pote: 40, _copo: 20});
    });
  });

  group('resumoItens', () {
    test('mostra itens com × e quantidade inteira', () {
      expect(
        resumoItens([
          {'nome': 'Pote 160g', 'quantidade': 40},
          {'nome': 'Copo', 'quantidade': 20.0},
        ]),
        'Pote 160g ×40, Copo ×20',
      );
    });

    test('resumo com reticências', () {
      final itens = [
        {'nome': 'A', 'quantidade': 1},
        {'nome': 'B', 'quantidade': 2},
        {'nome': 'C', 'quantidade': 3},
        {'nome': 'D', 'quantidade': 4},
      ];
      expect(resumoItens(itens, max: 3), 'A ×1, B ×2, C ×3 …');
      expect(resumoItens(itens.take(3).toList(), max: 3), 'A ×1, B ×2, C ×3');
    });
  });

  test('pedidosParaRepetir', () {
    final r = pedidosParaRepetir([
      _p('1', 'finalizado', '2026-11-01T10:00:00Z'),
      _p('2', 'cancelado', '2026-11-20T10:00:00Z'),
      _p('3', 'salvo', 'lixo'),
      _p('4', 'pronto', '2026-11-10T10:00:00Z'),
      _p('5', 'finalizado', '2026-11-05T10:00:00Z'),
      _p('6', 'finalizado', '2026-11-15T10:00:00Z'),
      _p('7', 'salvo', '2026-11-12T10:00:00Z'),
    ]);
    expect(r.length, 5);
    expect(r.map((p) => p['numero']).toList(), ['6', '7', '4', '5', '1']);
    expect(r.any((p) => p['status'] == 'cancelado'), isFalse);

    final curta = pedidosParaRepetir([
      _p('a', 'salvo', 'lixo'),
      _p('b', 'salvo', '2026-11-01T10:00:00Z'),
    ]);
    expect(curta.map((p) => p['numero']).toList(), ['b', 'a']);
  });

  group('listarPedidosDoCliente', () {
    Future<void> limpar() async {
      await fecharDbParaTeste();
      await databaseFactory.deleteDatabase(
          join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
    }

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('repetir_pedido_test');
      await databaseFactory.setDatabasesPath(dir.path);
    });
    setUp(limpar);
    tearDownAll(limpar);

    test('só devolve os pedidos do cliente pedido', () async {
      Map<String, dynamic> ped(int id, int cliente, {String status = 'salvo'}) => {
            'id': id,
            'numero': '$id',
            'status': status,
            'vendedor_codigo': '0003',
            'datahora': '2026-11-${10 + id}T10:00:00Z',
            'total': 10.0,
            'cliente_id': cliente,
            'cliente_nome': 'Cliente $cliente',
            'id_aparelho': 'ap-$id',
            'produtos': [
              {'nome': 'Copo', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
            ],
          };
      await salvarPedidoLocal(ped(1, 7));
      await salvarPedidoLocal(ped(2, 8));
      await salvarPedidoLocal(ped(3, 7));
      await salvarPedidoLocal(ped(4, 7, status: 'cancelado'));

      final r = await listarPedidosDoCliente(7);
      expect(r.map((p) => p['cliente_id']).toSet(), {7});
      expect(r.map((p) => p['numero']).toList(), ['3', '1']);
    });
  });
}
