import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/financeiro/resumo_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';

Pedido _pedido({
  required int id,
  String status = 'finalizado',
  String? nome,
  String? codigo,
  List<PedidoItem>? itens,
  double? total,
}) {
  final its = itens ??
      const [
        PedidoItem(nome: 'Queijo', preco: 0.10, quantidade: 1),
        PedidoItem(nome: 'Leite', preco: 0.20, quantidade: 1),
      ];
  return Pedido(
    id: id,
    itens: its,
    total: total ?? 0.30,
    status: status,
    vendedorNome: nome,
    vendedorCodigo: codigo,
    finalizadoEm: DateTime(2026, 11, 10),
  );
}

Saida _saida(int cat, int valor) => Saida(
      data: DateTime(2026, 11, 5),
      categoriaId: cat,
      descricao: '',
      valorCentavos: valor,
    );

void main() {
  test('parseValorCentavos aceita formato brasileiro', () {
    expect(parseValorCentavos('1.234,56'), 123456);
    expect(parseValorCentavos('480,5'), 48050);
    expect(parseValorCentavos('R\$ 480,00'), 48000);
    expect(parseValorCentavos(' 75 '), 7500);
  });
  test('parseValorCentavos recusa inválidos', () {
    for (final t in ['0', '-5', 'abc', '', '12,345', '0,00']) {
      expect(parseValorCentavos(t), isNull, reason: t);
    }
  });
  test('fmtCentavos', () {
    expect(fmtCentavos(842000), 'R\$ 8.420,00');
    expect(fmtCentavos(0), 'R\$ 0,00');
    expect(fmtCentavos(-329000), '-R\$ 3.290,00');
  });
  test('intervaloDoMes usa a hora local e vira o ano', () {
    final n = intervaloDoMes(2026, 11);
    expect(n.inicio, DateTime(2026, 11, 1));
    expect(n.fim, DateTime(2026, 12, 1));
    expect(intervaloDoMes(2026, 12).fim, DateTime(2027, 1, 1));
  });
  test('resumirMes soma em centavos, agrupa e ordena', () {
    final r = resumirMes(
      entregues: [
        _pedido(id: 1, nome: 'Ana'),
        _pedido(id: 2, nome: ' Ana ', itens: const [
          PedidoItem(nome: ' Queijo ', preco: 0.10, quantidade: 1),
          PedidoItem(nome: 'Leite', preco: 0.20, quantidade: 1),
        ]),
        _pedido(id: 3, nome: null, codigo: '07'),
        _pedido(id: 4, status: 'cancelado', nome: 'Ana', total: 99),
      ],
      prontos: [
        _pedido(id: 5, status: 'pronto', total: 15.0),
      ],
      saidas: [_saida(1, 20), _saida(2, 5)],
      nomesCategorias: {1: 'Embalagens', 2: 'Outros'},
    );
    expect(r.pedidos, 3);
    expect(r.vendasCentavos, 90);
    expect(r.porVendedor.map((l) => l.rotulo), ['Ana', '07']);
    expect(r.porVendedor.map((l) => l.centavos), [60, 30]);
    expect(r.porVendedor.map((l) => l.quantidade), [2, 1]);
    expect(r.porProduto.map((l) => l.rotulo), ['Leite', 'Queijo']);
    expect(r.porProduto.map((l) => l.centavos), [60, 30]);
    expect(r.porProduto.map((l) => l.quantidade), [3, 3]);
    expect(r.saidasCentavos, 25);
    expect(r.porCategoria.map((l) => l.rotulo), ['Embalagens', 'Outros']);
    expect(r.porCategoria.map((l) => l.centavos), [20, 5]);
    expect(r.resultadoCentavos, 65);
    expect(r.aReceberPedidos, 1);
    expect(r.aReceberCentavos, 1500);
  });
  test('categoria fora do mapa vira Sem categoria e empate ordena por rótulo', () {
    final r = resumirMes(
      entregues: [
        _pedido(id: 1, nome: 'Bia'),
        _pedido(id: 2, nome: 'Ana'),
      ],
      prontos: const [],
      saidas: [_saida(9, 10)],
      nomesCategorias: const {},
    );
    expect(r.porCategoria.single.rotulo, 'Sem categoria');
    expect(r.porVendedor.map((l) => l.rotulo), ['Ana', 'Bia']);
  });
  test('mês vazio dá zeros e listas vazias', () {
    final r = resumirMes(
      entregues: const [],
      prontos: const [],
      saidas: const [],
      nomesCategorias: const {},
    );
    expect(r.vendasCentavos, 0);
    expect(r.pedidos, 0);
    expect(r.saidasCentavos, 0);
    expect(r.resultadoCentavos, 0);
    expect(r.porVendedor, isEmpty);
    expect(r.porProduto, isEmpty);
    expect(r.porCategoria, isEmpty);
    expect(r.aReceberPedidos, 0);
    expect(r.aReceberCentavos, 0);
  });
  test('resultado negativo', () {
    final r = resumirMes(
      entregues: [_pedido(id: 1, nome: 'Ana')],
      prontos: const [],
      saidas: [_saida(1, 5000)],
      nomesCategorias: {1: 'Outros'},
    );
    expect(r.resultadoCentavos, 30 - 5000);
    expect(r.resultadoCentavos, isNegative);
  });
  test('Saida.toGravar não leva id nem auditoria', () {
    final s = Saida(
      id: 7,
      data: DateTime(2026, 11, 5),
      categoriaId: 3,
      descricao: 'Diesel',
      valorCentavos: 48000,
      criadoPor: 'x',
      criadoEm: DateTime(2026, 11, 5),
    );
    final m = s.toGravar();
    expect(m.keys.toSet(), {'data', 'categoria_id', 'descricao', 'valor'});
    expect(m['data'], '2026-11-05');
    expect(m['categoria_id'], 3);
    expect(m['valor'], 480.0);
  });
  test('Saida.fromMap lê valor numeric como texto ou número', () {
    Map<String, dynamic> base(Object v) => {
          'id': 1,
          'data': '2026-11-05',
          'categoria_id': 2,
          'descricao': 'a',
          'valor': v,
        };
    expect(Saida.fromMap(base('480.00')).valorCentavos, 48000);
    expect(Saida.fromMap(base(480)).valorCentavos, 48000);
    expect(Saida.fromMap(base(480.1)).valorCentavos, 48010);
    expect(Saida.fromMap(base('480.00')).data, DateTime(2026, 11, 5));
  });
  test('CategoriaSaida.fromMap', () {
    final c = CategoriaSaida.fromMap(
        {'id': 1, 'nome': 'Aluguel', 'ativa': true, 'ordem': 5});
    expect(c.nome, 'Aluguel');
    expect(c.ativa, isTrue);
    expect(c.ordem, 5);
  });
}
