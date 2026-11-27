// test/minhas_vendas_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/minhas_vendas.dart';

/// Pedido finalizado em [quando] (hora local), guardado em UTC como o app.
Map<String, dynamic> _ped({
  Object? total = 100,
  String status = 'finalizado',
  String vendedor = '0003',
  DateTime? quando,
  String? finalizadoEm,
  String? erroEnvio,
  Object? clienteId,
  String? nome,
  String? fantasia,
  List<Map<String, dynamic>>? produtos,
}) =>
    {
      'status': status,
      'vendedor_codigo': vendedor,
      'finalizado_em': finalizadoEm ??
          (quando ?? DateTime(2026, 11, 10, 12)).toUtc().toIso8601String(),
      'erro_envio': erroEnvio,
      'total': total,
      'cliente_id': clienteId,
      'cliente_nome': nome,
      'cliente_nome_fantasia': fantasia,
      'produtos': produtos ?? const [],
    };

Map<String, dynamic> _item(String nome, Object? qtd,
        {Object? subtotal, Object? preco}) =>
    {
      'nome': nome,
      'quantidade': qtd,
      if (subtotal != null) 'subtotal': subtotal,
      if (preco != null) 'preco': preco,
    };

ResumoVendas _res(List<Map<String, dynamic>> p, {int ano = 2026, int mes = 11}) =>
    resumoDoMes(p, vendedorCodigo: '0003', ano: ano, mes: mes);

void main() {
  group('resumoDoMes: venda', () {
    test('soma, conta e ticket médio', () {
      final r = _res([_ped(total: 100), _ped(total: '50,50'), _ped(total: 49.5)]);
      expect(r.vendido, 200.0);
      expect(r.pedidos, 3);
      expect(r.ticketMedio, closeTo(66.666, 0.01));
    });

    test('sem pedido: ticket médio null', () {
      final r = _res([]);
      expect(r.vendido, 0);
      expect(r.pedidos, 0);
      expect(r.ticketMedio, isNull);
    });

    test('status com trim e sem diferença de caixa', () {
      expect(_res([_ped(status: ' Finalizado ')]).pedidos, 1);
    });

    test('23h30 de 30/11 local conta em novembro, não em dezembro', () {
      final p = _ped(quando: DateTime(2026, 11, 30, 23, 30));
      expect(_res([p]).pedidos, 1);
      expect(_res([p], mes: 12).pedidos, 0);
    });

    test('fronteira do mês vale em qualquer fuso (derivada de toLocal)', () {
      final u = DateTime.utc(2026, 12, 1, 2, 30);
      final l = u.toLocal();
      final p = _ped(finalizadoEm: u.toIso8601String());
      final outro = l.month == 12 ? (l.year, 11) : (l.year, 12);
      expect(_res([p], ano: l.year, mes: l.month).pedidos, 1);
      expect(_res([p], ano: outro.$1, mes: outro.$2).pedidos, 0);
    });

    test('00h30 de 01/12 local conta em dezembro', () {
      final p = _ped(quando: DateTime(2026, 12, 1, 0, 30));
      expect(_res([p]).pedidos, 0);
      expect(_res([p], mes: 12).pedidos, 1);
    });

    test('outro vendedor, apagado, outro mês e data ilegível ficam fora', () {
      final r = _res([
        _ped(),
        _ped(vendedor: '0002'),
        _ped(erroEnvio: kErroApagadoNoControle),
        _ped(quando: DateTime(2026, 10, 31, 12)),
        _ped(finalizadoEm: 'lixo'),
        _ped(finalizadoEm: ''),
        _ped(status: 'salvo'),
        _ped(status: 'cancelado'),
      ]);
      expect(r.pedidos, 1);
      expect(r.vendido, 100);
    });
  });

  group('resumoDoMes: a entregar', () {
    test('salvo e pronto entram; cancelado, finalizado e apagado não', () {
      final r = _res([
        _ped(status: 'salvo', total: 10, finalizadoEm: ''),
        _ped(status: 'pronto', total: '20,5', finalizadoEm: ''),
        _ped(status: 'cancelado', total: 999),
        _ped(status: 'salvo', vendedor: '0002', total: 999),
        _ped(status: 'pronto', erroEnvio: kErroApagadoNoControle, total: 999),
        _ped(total: 5),
      ]);
      expect(r.aEntregarPedidos, 2);
      expect(r.aEntregarValor, 30.5);
      expect(r.vendido, 5);
    });

    test('não depende do mês pedido', () {
      final r = _res([_ped(status: 'salvo', total: 10)], mes: 1, ano: 2020);
      expect(r.aEntregarPedidos, 1);
    });
  });

  group('resumoDoMes: por produto', () {
    test('soma por nome (trim, caixa), nome do primeiro, ordem por R\$', () {
      final r = _res([
        _ped(produtos: [
          _item('Copo', 2, subtotal: 20.0),
          _item('Pote', 1, subtotal: 80.0),
        ]),
        _ped(produtos: [
          _item(' copo ', 3, subtotal: 30.0),
        ]),
      ]);
      expect(r.porProduto.map((e) => e.nome).toList(), ['Pote', 'Copo']);
      expect(r.porProduto[0].valor, 80.0);
      expect(r.porProduto[1].nome, 'Copo');
      expect(r.porProduto[1].unidades, 5);
      expect(r.porProduto[1].valor, 50.0);
    });

    test('subtotal em texto com vírgula, ausente (preço x quantidade)', () {
      final r = _res([
        _ped(produtos: [
          _item('A', 1, subtotal: '12,50'),
          _item('B', 4, preco: 2.5),
          _item('C', 2, preco: '3,00'),
        ]),
      ]);
      double v(String n) => r.porProduto.firstWhere((e) => e.nome == n).valor;
      expect(v('A'), 12.5);
      expect(v('B'), 10.0);
      expect(v('C'), 6.0);
    });

    test('produtos em JSON string; só pedidos que contam', () {
      final p = _ped()..['produtos'] = '[{"nome":"X","quantidade":2,"subtotal":8}]';
      final fora = _ped(status: 'salvo', produtos: [_item('Y', 1, subtotal: 1)]);
      final r = _res([p, fora]);
      expect(r.porProduto.length, 1);
      expect(r.porProduto.single.nome, 'X');
      expect(r.porProduto.single.unidades, 2);
    });
  });

  group('resumoDoMes: melhores clientes', () {
    test('mesmo finalizado_em: o nome exibido é o menor (sem caixa)', () {
      final t = DateTime(2026, 11, 10, 12);
      final r = _res([
        _ped(clienteId: 1, nome: 'Zeca', quando: t),
        _ped(clienteId: 1, nome: 'ana', quando: t),
      ]);
      expect(r.melhoresClientes.single.nome, 'ana');
      final r2 = _res([
        _ped(clienteId: 1, nome: 'ana', quando: t),
        _ped(clienteId: 1, nome: 'Zeca', quando: t),
      ]);
      expect(r2.melhoresClientes.single.nome, 'ana');
    });

    test('5 melhores por R\$, agrupando por cliente_id', () {
      final ps = <Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _ped(clienteId: i, nome: 'C$i', total: i * 10),
        _ped(clienteId: 1, nome: 'C1', total: 100),
      ];
      final r = _res(ps);
      expect(r.melhoresClientes.length, 5);
      expect(r.melhoresClientes.first.nome, 'C1');
      expect(r.melhoresClientes.first.pedidos, 2);
      expect(r.melhoresClientes.first.valor, 110);
      expect(r.melhoresClientes.map((c) => c.nome).toList(),
          ['C1', 'C6', 'C5', 'C4', 'C3']);
    });

    test('sem cliente_id agrupa pelo nome exibido', () {
      final r = _res([
        _ped(nome: 'Ana', total: 10),
        _ped(nome: 'ana ', total: 15),
        _ped(nome: 'Bia', total: 5),
      ]);
      expect(r.melhoresClientes.length, 2);
      expect(r.melhoresClientes.first.pedidos, 2);
      expect(r.melhoresClientes.first.valor, 25);
    });

    test('nome vem do pedido mais recente (fantasia primeiro)', () {
      final r = _res([
        _ped(clienteId: 1, nome: 'Velho', total: 10, quando: DateTime(2026, 11, 2, 9)),
        _ped(
            clienteId: 1,
            nome: 'Novo',
            fantasia: 'Mercado Novo',
            total: 10,
            quando: DateTime(2026, 11, 20, 9)),
      ]);
      expect(r.melhoresClientes.single.nome, 'Mercado Novo');
    });

    test('empate de R\$ desempata pelo nome', () {
      final r = _res([
        _ped(clienteId: 1, nome: 'Zeca', total: 10),
        _ped(clienteId: 2, nome: 'Ana', total: 10),
      ]);
      expect(r.melhoresClientes.map((c) => c.nome).toList(), ['Ana', 'Zeca']);
    });
  });

  group('resumoDoMes: revisão final', () {
    test('I1: finalizado sem finalizado_em fica fora do vendido e aparece aguardando', () {
      final r = _res([
        _ped(),
        _ped(total: 40, finalizadoEm: ''),
        _ped(total: '10,5', finalizadoEm: 'lixo'),
        _ped(total: 99, finalizadoEm: '', erroEnvio: kErroApagadoNoControle),
        _ped(total: 99, finalizadoEm: '', vendedor: '0002'),
      ]);
      expect(r.vendido, 100);
      expect(r.pedidos, 1);
      expect(r.aguardandoEnvioPedidos, 2);
      expect(r.aguardandoEnvioValor, 50.5);
    });

    test('I2: ate corta o mês anterior no mesmo dia e hora', () {
      final doze = _ped(total: 10, quando: DateTime(2026, 10, 14, 12));
      final tarde = _ped(total: 20, quando: DateTime(2026, 10, 20, 12));
      final agora = DateTime(2026, 11, 15, 10);
      final r = resumoDoMes([doze, tarde],
          vendedorCodigo: '0003', ano: 2026, mes: 10, ate: limiteMesAnterior(agora));
      expect(r.vendido, 10);
      expect(r.pedidos, 1);
      expect(_res([doze, tarde], mes: 10).vendido, 30);
    });

    test('I2: 31/03 compara com fevereiro inteiro', () {
      final lim = limiteMesAnterior(DateTime(2026, 3, 31, 10));
      final p = _ped(total: 10, quando: DateTime(2026, 2, 28, 23, 59));
      final r = resumoDoMes([p],
          vendedorCodigo: '0003', ano: 2026, mes: 2, ate: lim);
      expect(r.vendido, 10);
    });

    test('I2: janeiro olha dezembro do ano anterior', () {
      final lim = limiteMesAnterior(DateTime(2027, 1, 5, 8));
      expect(lim, DateTime(2026, 12, 5, 8));
    });

    test('M4: vendidoNoMes segue a mesma regra do resumo', () {
      final ps = [
        _ped(total: 100),
        _ped(total: '50,50'),
        _ped(vendedor: '0002'),
        _ped(erroEnvio: kErroApagadoNoControle),
        _ped(status: 'salvo'),
        _ped(finalizadoEm: ''),
        _ped(quando: DateTime(2026, 10, 10)),
      ];
      expect(vendidoNoMes(ps, vendedorCodigo: '0003', ano: 2026, mes: 11), 150.5);
      expect(_res(ps).vendido, 150.5);
    });

    test('M6: rascunho so_local não entra em "A entregar"', () {
      final r = _res([
        {..._ped(status: 'salvo', total: 30), 'so_local': 1},
        {..._ped(status: 'pronto', total: 20), 'so_local': 0},
      ]);
      expect(r.aEntregarPedidos, 1);
      expect(r.aEntregarValor, 20);
    });

    test('M7: cliente sem nome aparece como "Cliente sem nome"', () {
      final r = _res([_ped(clienteId: 1, nome: '  ')]);
      expect(r.melhoresClientes.single.nome, 'Cliente sem nome');
    });
  });

  group('textoVariacao', () {
    test('sobe', () => expect(textoVariacao(150, 100), '▲ 50%'));
    test('cai', () => expect(textoVariacao(50, 100), '▼ 50%'));
    test('igual', () => expect(textoVariacao(100, 100), '= 0%'));
    test('anterior zero', () {
      expect(textoVariacao(100, 0), isNull);
      expect(textoVariacao(0, 0), isNull);
    });
    test('arredonda', () => expect(textoVariacao(110.4, 100), '▲ 10%'));
  });

  group('listarPedidosParaVendas', () {
    Future<void> limpar() async {
      await fecharDbParaTeste();
      await databaseFactory.deleteDatabase(
          join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
    }

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('minhas_vendas_test');
      await databaseFactory.setDatabasesPath(dir.path);
    });
    setUp(limpar);
    tearDownAll(limpar);

    test('só vêm os pedidos do vendedor pedido, com as colunas certas', () async {
      Map<String, dynamic> ped(int id, String vend) => {
            'id': id,
            'numero': '$id',
            'status': 'finalizado',
            'vendedor_codigo': vend,
            'datahora': '2026-11-10T10:00:00Z',
            'finalizado_em': '2026-11-10T10:00:00Z',
            'total': 10.0,
            'cliente_id': 7,
            'cliente_nome': 'Cliente',
            'id_aparelho': 'ap-$id',
            'assinatura': '0xABCDEF',
            'produtos': [
              {'nome': 'Copo', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
            ],
          };
      await salvarPedidoLocal(ped(1, '0003'));
      await salvarPedidoLocal(ped(2, '0002'));
      await salvarPedidoLocal(ped(3, '0003'));

      final r = await listarPedidosParaVendas('0003');
      expect(r.length, 2);
      expect(r.every((p) => p['vendedor_codigo'] == '0003'), isTrue);
      expect(r.first.keys.toSet(), {
        'id', 'numero', 'status', 'vendedor_codigo', 'finalizado_em', 'total',
        'produtos', 'erro_envio', 'cliente_id', 'cliente_nome',
        'cliente_nome_fantasia', 'datahora', 'pendente_envio', 'so_local',
      });
      expect(resumoDoMes(r, vendedorCodigo: '0003', ano: 2026, mes: 11).pedidos, 2);
    });

    test('M4: listarVendasDoMesParaHome traz só as colunas leves e o período', () async {
      await limpar();
      Map<String, dynamic> ped(int id, String quando) => {
            'id': id,
            'numero': '$id',
            'status': 'finalizado',
            'vendedor_codigo': '0003',
            'datahora': quando,
            'finalizado_em': quando,
            'total': 10.0,
            'cliente_id': 7,
            'cliente_nome': 'Cliente',
            'id_aparelho': 'ap-$id',
            'assinatura': '0xABCDEF',
            'produtos': const [],
          };
      await salvarPedidoLocal(ped(1, '2026-09-10T10:00:00Z'));
      await salvarPedidoLocal(ped(2, '2026-11-10T10:00:00Z'));
      final r = await listarVendasDoMesParaHome('0003', DateTime.utc(2026, 11, 1));
      expect(r.length, 1);
      expect(r.single.keys.toSet(),
          {'total', 'status', 'finalizado_em', 'erro_envio', 'vendedor_codigo'});
    });
  });
}
