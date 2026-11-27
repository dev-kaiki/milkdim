import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_app/utils/db.dart' show kErroApagadoNoControle;
import 'package:milkdim_app/utils/entregas.dart';

Map<String, dynamic> _p(
  Object numero, {
  String status = 'pronto',
  String vendedor = 'V1',
  String nome = 'Cliente',
  String? fantasia,
  String cidade = 'Franca',
  String? erro,
}) =>
    {
      'numero': numero,
      'status': status,
      'vendedor_codigo': vendedor,
      'cliente_nome': nome,
      'cliente_nome_fantasia': fantasia,
      'cliente_cidade': cidade,
      'erro_envio': erro,
    };

void main() {
  group('entregasProntas', () {
    test('só pronto deste vendedor, sem apagados no Controle', () {
      final g = entregasProntas([
        _p(1),
        _p(2, status: 'salvo'),
        _p(3, status: 'entregue'),
        _p(4, vendedor: 'V2'),
        _p(5, vendedor: ' V1 '),
        _p(6, erro: kErroApagadoNoControle),
      ], vendedorCodigo: 'V1');
      final nums = g.expand((x) => x.pedidos).map((p) => p['numero']).toList();
      expect(nums, [1, 5]);
    });

    test('agrupa sem diferença de caixa ou espaço; título do primeiro', () {
      final g = entregasProntas([
        _p(1, cidade: 'franca'),
        _p(2, cidade: 'Franca '),
        _p(3, cidade: ' FRANCA'),
      ], vendedorCodigo: 'V1');
      expect(g.length, 1);
      expect(g.first.cidade, 'franca');
      expect(g.first.pedidos.length, 3);
    });

    test('grupos em ordem alfabética e "Sem cidade" por último', () {
      final g = entregasProntas([
        _p(1, cidade: ''),
        _p(2, cidade: 'Rifaina'),
        _p(3, cidade: '   '),
        _p(4, cidade: 'Batatais'),
      ], vendedorCodigo: 'V1');
      expect(g.map((x) => x.cidade).toList(),
          ['Batatais', 'Rifaina', 'Sem cidade']);
      expect(g.last.pedidos.length, 2);
    });

    test('dentro do grupo: nomeExibicao, empate pelo número', () {
      final g = entregasProntas([
        _p(10, nome: 'Zeca'),
        _p(9, nome: 'Ana'),
        _p(8, nome: 'x', fantasia: 'Mercado Bom'),
        _p(11, nome: 'ana'),
        _p(2, nome: 'Ana'),
      ], vendedorCodigo: 'V1');
      final nums = g.single.pedidos.map((p) => p['numero']).toList();
      expect(nums, [2, 9, 11, 8, 10]);
    });

    test('lista vazia', () {
      expect(entregasProntas([], vendedorCodigo: 'V1'), isEmpty);
    });
  });

  test('clienteDoPedido troca as chaves', () {
    final c = clienteDoPedido({
      'cliente_whatsapp': '16999990000',
      'cliente_telefone': '1633330000',
      'cliente_nome': 'Maria',
      'cliente_nome_fantasia': 'Padaria',
      'cliente_cidade': 'Franca',
    });
    expect(c['whatsapp'], '16999990000');
    expect(c['telefone'], '1633330000');
    expect(c['nome'], 'Maria');
    expect(c['nome_fantasia'], 'Padaria');
    expect(c['cidade'], 'Franca');
  });

  group('linkMapa', () {
    const base = 'https://www.google.com/maps/search/?api=1&query=';
    test('endereço, cidade e CEP codificados', () {
      final u = linkMapa({
        'cliente_endereco': 'Rua São José, 10',
        'cliente_cidade': 'Franca',
        'cliente_cep': '14400-000',
      });
      expect(
          u.toString(),
          base +
              Uri.encodeComponent('Rua São José, 10, Franca, 14400-000'));
      expect(u.toString(), contains('%20'));
      expect(u.toString(), isNot(contains('+')));
    });

    test('partes vazias ficam de fora', () {
      final u = linkMapa({
        'cliente_endereco': 'Rua A, 1',
        'cliente_cidade': '  ',
        'cliente_cep': null,
      });
      expect(u.toString(), base + Uri.encodeComponent('Rua A, 1'));
    });

    test('sem endereço dá null', () {
      expect(linkMapa({'cliente_cidade': 'Franca'}), isNull);
      expect(linkMapa({'cliente_endereco': '  '}), isNull);
    });
  });

  test('mensagemPronto com e sem vendedor', () {
    expect(mensagemPronto('João', '12'),
        'Olá! Aqui é o João da MilkDim. Seu pedido nº 12 está pronto, passo aí hoje.');
    expect(mensagemPronto('', '12'),
        'Olá! Aqui é da MilkDim. Seu pedido nº 12 está pronto, passo aí hoje.');
    expect(mensagemPronto('  ', '12'),
        'Olá! Aqui é da MilkDim. Seu pedido nº 12 está pronto, passo aí hoje.');
  });

  test('contarProntos bate com a soma dos grupos', () {
    final ps = [
      _p(1),
      _p(2, cidade: 'Rifaina'),
      _p(3, cidade: ''),
      _p(4, vendedor: 'V2'),
      _p(5, status: 'salvo'),
    ];
    final soma = entregasProntas(ps, vendedorCodigo: 'V1')
        .fold<int>(0, (a, g) => a + g.pedidos.length);
    expect(contarProntos(ps, vendedorCodigo: 'V1'), soma);
    expect(soma, 3);
  });
}
