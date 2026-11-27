// test/clientes_sumidos_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/utils/clientes_sumidos.dart';
import 'package:milkdim_app/utils/db.dart';

final _agora = DateTime(2026, 11, 27, 10);

/// Pedido de [dias] dias atrás (meio-dia local, guardado em UTC como o app).
Map<String, dynamic> _ped(int cliente, int dias,
        {String vendedor = '0003',
        String status = 'finalizado',
        String? erroEnvio,
        String? datahora}) =>
    {
      'cliente_id': cliente,
      'vendedor_codigo': vendedor,
      'status': status,
      'erro_envio': erroEnvio,
      'datahora': datahora ??
          DateTime(2026, 11, 27 - dias, 12).toUtc().toIso8601String(),
    };

Map<String, dynamic> _cli(int id, {String? tel, String? zap, Object? ativo}) =>
    {
      'id': id,
      'nome': 'Cliente $id',
      'telefone': tel,
      'whatsapp': zap,
      if (ativo != null) 'ativo': ativo,
    };

List<ClienteSumido> _lista(List<Map<String, dynamic>> clientes,
        List<Map<String, dynamic>> pedidos,
        {String vendedor = '0003', int prazo = 30}) =>
    clientesSumidos(
        clientes: clientes,
        pedidos: pedidos,
        vendedorCodigo: vendedor,
        agora: _agora,
        prazoDias: prazo);

void main() {
  group('clientesSumidos', () {
    test('30 dias certos entra, 29 não', () {
      final r = _lista([_cli(1), _cli(2)], [_ped(1, 30), _ped(2, 29)]);
      expect(r.map((s) => s.cliente['id']).toList(), [1]);
      expect(r.first.dias, 30);
    });

    test('só pedidos deste vendedor', () {
      final pedidos = [_ped(7, 40, vendedor: '0002'), _ped(7, 2, vendedor: '0003')];
      final a = _lista([_cli(7)], pedidos, vendedor: '0002');
      expect(a.length, 1);
      expect(a.first.dias, 40);
      expect(_lista([_cli(7)], pedidos, vendedor: '0003'), isEmpty);
    });

    test('ignora cancelado e apagado no Controle', () {
      final r = _lista([
        _cli(1)
      ], [
        _ped(1, 50),
        _ped(1, 5, status: 'cancelado'),
        _ped(1, 3, status: 'enviado', erroEnvio: kErroApagadoNoControle),
      ]);
      expect(r.length, 1);
      expect(r.first.dias, 50);
      expect(r.first.pedidos, 1);
    });

    test('datahora ilegível é ignorada', () {
      final r = _lista([_cli(1)], [_ped(1, 40), _ped(1, 1, datahora: 'lixo')]);
      expect(r.length, 1);
      expect(r.first.dias, 40);
    });

    test('ordem por dias crescente e pedidos conta só os válidos', () {
      final r = _lista([
        _cli(1),
        _cli(2),
        _cli(3)
      ], [
        _ped(1, 90),
        _ped(2, 31),
        _ped(2, 45),
        _ped(2, 60, status: 'cancelado'),
        _ped(3, 40),
      ]);
      expect(r.map((s) => s.cliente['id']).toList(), [2, 3, 1]);
      expect(r.map((s) => s.dias).toList(), [31, 40, 90]);
      expect(r.first.pedidos, 2);
    });

    test('prazo maior filtra mais', () {
      final r = _lista([_cli(1), _cli(2)], [_ped(1, 40), _ped(2, 70)], prazo: 60);
      expect(r.map((s) => s.cliente['id']).toList(), [2]);
    });

    test('cliente desativado não conta nem aparece; sem o campo é ativo', () {
      final r = _lista([
        _cli(1, ativo: 0),
        _cli(2, ativo: false),
        _cli(3, ativo: '0'),
        _cli(4, ativo: 'false'),
        _cli(5, ativo: 1),
        _cli(6),
      ], [for (var i = 1; i <= 6; i++) _ped(i, 40)]);
      expect(r.map((s) => s.cliente['id']).toList()..sort(), [5, 6]);
    });

    test('mesmos dias: desempata pelo nome de exibição, sem diferenciar maiúsculas', () {
      final r = _lista([
        {'id': 1, 'nome': 'Zeca'},
        {'id': 2, 'nome': 'Mercado X', 'nome_fantasia': 'abc Frios'},
        {'id': 3, 'nome': 'Bruno', 'nome_fantasia': '  '},
      ], [_ped(1, 40), _ped(2, 40), _ped(3, 40)]);
      expect(r.map((s) => s.cliente['id']).toList(), [2, 3, 1]);
    });

    test('cliente fora da lista de clientes não aparece', () {
      expect(_lista([_cli(1)], [_ped(9, 50)]), isEmpty);
    });
  });

  group('telefone e links', () {
    test('normalizarTelefone', () {
      expect(normalizarTelefone('(16) 99999-1234'), '5516999991234');
      expect(normalizarTelefone('+55 16 3333-4444'), '551633334444');
      expect(normalizarTelefone('1234'), isNull);
      expect(normalizarTelefone(''), isNull);
      expect(normalizarTelefone(null), isNull);
    });

    test('normalizarTelefone com zero na frente e números inválidos', () {
      expect(normalizarTelefone('(016) 3333-4444'), '551633334444');
      expect(normalizarTelefone('016 99999-1234'), '5516999991234');
      expect(normalizarTelefone('0 15 16 99999-1234'), '5516999991234');
      expect(normalizarTelefone('0800 123 4567'), isNull);
      expect(normalizarTelefone('(00) 3333-4444'), isNull);
      expect(normalizarTelefone('55 00 3333-4444'), isNull);
      // 11 dígitos precisam ser celular (3º dígito 9); fixo de 10 segue valendo.
      expect(normalizarTelefone('(16) 33333-4444'), isNull);
      expect(normalizarTelefone('(16) 3333-4444'), '551633334444');
    });

    test('nomeExibicao: fantasia quando houver, senão o nome', () {
      expect(nomeExibicao({'nome': 'A', 'nome_fantasia': 'B'}), 'B');
      expect(nomeExibicao({'nome': 'A', 'nome_fantasia': ' '}), 'A');
      expect(nomeExibicao({'nome': 'A'}), 'A');
    });

    test('podeAplicarClienteInicial só se o vendedor não escolheu ninguém', () {
      expect(podeAplicarClienteInicial(clienteId: null, nomeDigitado: ''), isTrue);
      expect(podeAplicarClienteInicial(clienteId: null, nomeDigitado: '  '), isTrue);
      expect(podeAplicarClienteInicial(clienteId: 3, nomeDigitado: ''), isFalse);
      expect(podeAplicarClienteInicial(clienteId: null, nomeDigitado: 'Ana'), isFalse);
    });

    test('linkWhatsApp sem whatsapp usa o telefone', () {
      final u = linkWhatsApp(_cli(1, tel: '(16) 3333-4444'), mensagemSumido('Ana'));
      expect(u, isNotNull);
      expect(u!.host, 'wa.me');
      expect(u.path, '/551633334444');
      expect(u.queryParameters['text'], mensagemSumido('Ana'));
      expect(u.toString(), contains('MilkDim'));
      expect(u.toString(), isNot(contains(' ')));
    });

    test('linkWhatsApp codifica espaços como %20, sem "+"', () {
      final u = linkWhatsApp(_cli(1, tel: '(16) 3333-4444'), mensagemSumido('Ana'));
      expect(u.toString(), contains('Faz%20um%20tempinho'));
      expect(u.toString(), isNot(contains('+')));
    });

    test('linkWhatsApp prefere o whatsapp', () {
      final u = linkWhatsApp(
          _cli(1, tel: '(16) 3333-4444', zap: '16 99999-1234'), 'oi');
      expect(u!.path, '/5516999991234');
    });

    test('linkLigar sem telefone usa o whatsapp; tudo inválido dá null', () {
      expect(linkLigar(_cli(1, zap: '16 99999-1234')).toString(), 'tel:+5516999991234');
      expect(linkLigar(_cli(1, tel: '(16) 3333-4444')).toString(), 'tel:+551633334444');
      expect(linkLigar(_cli(1, tel: '12', zap: 'x')), isNull);
      expect(linkWhatsApp(_cli(1, tel: '12'), 'oi'), isNull);
    });

    test('mensagemSumido sem nome do vendedor', () {
      const esperado =
          'Olá! Aqui é da MilkDim. Faz um tempinho que a gente não se fala, posso passar aí essa semana?';
      expect(mensagemSumido(''), esperado);
      expect(mensagemSumido('   '), esperado);
    });

    test('mensagemSumido', () {
      expect(mensagemSumido('Ana'),
          'Olá! Aqui é o Ana da MilkDim. Faz um tempinho que a gente não se fala, posso passar aí essa semana?');
    });
  });

  group('listarPedidosParaSumidos', () {
    Future<void> limpar() async {
      await fecharDbParaTeste();
      await databaseFactory.deleteDatabase(
          join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
    }

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('clientes_sumidos_test');
      await databaseFactory.setDatabasesPath(dir.path);
    });
    setUp(limpar);
    tearDownAll(limpar);

    test('só vêm os pedidos do vendedor pedido', () async {
      Map<String, dynamic> ped(int id, String vend, int? cliente) => {
            'id': id,
            'numero': '$id',
            'status': 'salvo',
            'vendedor_codigo': vend,
            'datahora': '2026-11-${10 + id}T10:00:00Z',
            'total': 10.0,
            'cliente_id': cliente,
            'cliente_nome': 'Cliente',
            'id_aparelho': 'ap-$id',
            'produtos': [
              {'nome': 'Copo', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
            ],
          };
      await salvarPedidoLocal(ped(1, '0003', 7));
      await salvarPedidoLocal(ped(2, '0002', 7));
      await salvarPedidoLocal(ped(3, '0003', 8));
      await salvarPedidoLocal(ped(4, '0003', null));

      final r = await listarPedidosParaSumidos('0003');
      expect(r.map((p) => p['cliente_id']).toList()..sort(), [7, 8]);
      expect(r.every((p) => p['vendedor_codigo'] == '0003'), isTrue);
    });

    test('listarPedidosProntos: só pronto do vendedor, tolera espaço e caixa', () async {
      Map<String, dynamic> ped(int id, String vend, String status) => {
            'id': id,
            'numero': '$id',
            'status': status,
            'vendedor_codigo': vend,
            'datahora': '2026-11-${10 + id}T10:00:00Z',
            'total': 10.0,
            'cliente_nome': 'Cliente $id',
            'cliente_cidade': 'Franca',
            'id_aparelho': 'ap-$id',
            'assinatura': '0xABCDEF',
            'produtos': [
              {'nome': 'Copo', 'preco': 10.0, 'quantidade': 1, 'subtotal': 10.0},
            ],
          };
      await salvarPedidoLocal(ped(1, '0003', 'pronto'));
      await salvarPedidoLocal(ped(2, '0003', ' Pronto '));
      await salvarPedidoLocal(ped(3, '0003', 'salvo'));
      await salvarPedidoLocal(ped(4, '0002', 'pronto'));
      await salvarPedidoLocal(ped(5, '0003', 'entregue'));

      final r = await listarPedidosProntos('0003');
      expect(r.map((p) => p['cliente_nome']).toList()..sort(),
          ['Cliente 1', 'Cliente 2']);
      expect(r.every((p) => p['vendedor_codigo'] == '0003'), isTrue);
      // Sem as colunas pesadas.
      expect(r.first.containsKey('assinatura'), isFalse);
      expect(r.first['cliente_cidade'], 'Franca');
    });

    test('buscarPedidoLocalPorId traz a linha completa; null se não existe', () async {
      final id = await salvarPedidoLocal({
        'numero': '9',
        'status': 'pronto',
        'vendedor_codigo': '0003',
        'assinatura': '0xABCDEF',
        'id_aparelho': 'ap-9',
        'produtos': [],
      });
      final p = await buscarPedidoLocalPorId(id);
      expect(p, isNotNull);
      expect(p!['numero'], '9');
      expect(p.containsKey('assinatura'), isTrue);
      expect(await buscarPedidoLocalPorId(999999), isNull);
    });
  });
}
