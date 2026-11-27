import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/financeiro/painel_financeiro.dart';
import 'package:milkdim_admin/financeiro/relatorio_mes.dart';
import 'package:milkdim_admin/financeiro/resumo_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';

Pedido _pedido(int id,
    {String? numero,
    String? cliente,
    String? fantasia,
    DateTime? fim,
    double total = 10,
    String vendedor = 'Ana'}) {
  return Pedido(
    id: id,
    numero: numero ?? '$id',
    itens: [PedidoItem(nome: 'Queijo', preco: total, quantidade: 1)],
    total: total,
    status: 'finalizado',
    vendedorNome: vendedor,
    clienteNome: cliente,
    clienteNomeFantasia: fantasia,
    finalizadoEm: fim,
  );
}

Saida _saida(DateTime d, int cat, int c, {String desc = ''}) =>
    Saida(data: d, categoriaId: cat, descricao: desc, valorCentavos: c);

RelatorioMes _monta({
  int ano = 2026,
  int mes = 11,
  bool mesAtual = false,
  ComparacaoMes? comparacao,
  List<Saida> saidas = const [],
  List<Pedido> entregues = const [],
}) {
  final resumo = resumirMes(
    entregues: entregues,
    prontos: const [],
    saidas: saidas,
    nomesCategorias: const {1: 'Frete'},
  );
  return montarRelatorio(
    ano: ano,
    mes: mes,
    geradoEm: DateTime(2026, 11, 27, 9, 5),
    mesAtual: mesAtual,
    resumo: resumo,
    comparacao: comparacao,
    saidas: saidas,
    nomesCategorias: const {1: 'Frete'},
    entregues: entregues,
  );
}

int _paginas(List<int> bytes) =>
    RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('título, gerado em e nome do arquivo saem exatos', () {
    final r = _monta();
    expect(r.titulo, 'MilkDim · Relatório de novembro de 2026');
    expect(r.geradoEm, 'Gerado em 27/11/2026 09:05');
    expect(nomeArquivoRelatorio(2026, 3), 'Relatorio_MilkDim_2026-03.pdf');
    expect(nomeArquivoRelatorio(2027, 12), 'Relatorio_MilkDim_2027-12.pdf');
    expect(_monta(mes: 3).titulo, 'MilkDim · Relatório de março de 2026');
  });

  test('resumo traz as cinco linhas com variação da tela', () {
    final r = _monta(
      entregues: [_pedido(1, total: 100), _pedido(2, total: 50)],
      saidas: [_saida(DateTime(2026, 11, 3), 1, 3000)],
      comparacao: const ComparacaoMes(
        vendas: Variacao(pct: 12, sentido: 1),
        saidas: Variacao(pct: -5, sentido: 1),
        resultado: Variacao(texto: 'virou positivo', sentido: 1),
      ),
    );
    expect(r.resumo.map((l) => l.rotulo).toList(),
        ['Vendas', 'Pedidos entregues', 'Saídas', 'Resultado', 'Margem']);
    expect(r.resumo[0].valor, 'R\$ 150,00');
    expect(r.resumo[0].variacao, '+12%');
    expect(r.resumo[1].valor, '2');
    expect(r.resumo[1].variacao, isNull);
    expect(r.resumo[2].valor, 'R\$ 30,00');
    expect(r.resumo[2].variacao, '-5%');
    expect(r.resumo[3].valor, 'R\$ 120,00');
    expect(r.resumo[3].variacao, 'virou positivo');
    expect(r.resumo[4].valor, '80%');
    expect(r.resumo[4].variacao, isNull);
  });

  test('sem vendas a margem é traço e sem comparação não há variação', () {
    final r = _monta();
    expect(r.resumo[4].valor, '—');
    expect(r.resumo[0].valor, 'R\$ 0,00');
    expect(r.resumo[0].variacao, isNull);
  });

  test('saídas e entregues em ordem de data; ausentes viram traço', () {
    final r = _monta(
      saidas: [
        _saida(DateTime(2026, 11, 20), 1, 100, desc: 'B'),
        _saida(DateTime(2026, 11, 2), 9, 200, desc: 'A'),
      ],
      entregues: [
        _pedido(2, numero: '2', cliente: 'Zé', fim: DateTime(2026, 11, 9)),
        _pedido(3, numero: '3'),
        _pedido(1,
            numero: '1',
            fantasia: 'Mercado',
            cliente: 'João',
            fim: DateTime(2026, 11, 4)),
      ],
    );
    expect(r.saidas.map((l) => l.first).toList(), ['02/11/2026', '20/11/2026']);
    expect(r.saidas.first, ['02/11/2026', 'Sem categoria', 'A', 'R\$ 2,00']);
    expect(r.entregues[0], ['04/11/2026', '1', 'Mercado', 'R\$ 10,00']);
    expect(r.entregues[1], ['09/11/2026', '2', 'Zé', 'R\$ 10,00']);
    expect(r.entregues[2], ['—', '3', '—', 'R\$ 10,00']);
  });

  test('A receber só no mês atual; aviso só até novembro de 2026', () {
    final resumo = resumirMes(
      entregues: const [],
      prontos: [_pedido(1, total: 25)],
      saidas: const [],
      nomesCategorias: const {},
    );
    RelatorioMes m(int ano, int mes, bool atual) => montarRelatorio(
          ano: ano,
          mes: mes,
          geradoEm: DateTime(2026, 11, 27),
          mesAtual: atual,
          resumo: resumo,
          saidas: const [],
          nomesCategorias: const {},
          entregues: const [],
        );
    expect(m(2026, 11, true).aReceber, '1 pedido · R\$ 25,00');
    expect(m(2026, 10, false).aReceber, isNull);
    expect(m(2026, 11, true).aviso, 'Até 23/11/2026, a data é a do pedido.');
    expect(m(2026, 10, false).aviso, isNotNull);
    expect(m(2025, 12, false).aviso, isNotNull);
    expect(m(2026, 12, false).aviso, isNull);
    expect(m(2027, 1, false).aviso, isNull);
  });

  test('mês vazio gera PDF válido', () async {
    final bytes = await pdfDoRelatorio(_monta());
    expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
    expect(_paginas(bytes), 1);
  });

  test('150 pedidos quebram em várias páginas', () async {
    final r = _monta(entregues: [
      for (var i = 1; i <= 150; i++)
        _pedido(i, cliente: 'Cliente $i', fim: DateTime(2026, 11, 1 + i % 28)),
    ]);
    final bytes = await pdfDoRelatorio(r);
    expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
    expect(_paginas(bytes), greaterThan(1));
  });

  test('variação no PDF não usa setas (a fonte não as tem)', () {
    final r = _monta(
      comparacao: const ComparacaoMes(
        vendas: Variacao(pct: 0, sentido: 0),
        saidas: Variacao(pct: 7, sentido: -1),
      ),
    );
    expect(r.resumo[0].variacao, '= 0%');
    expect(r.resumo[2].variacao, '+7%');
    for (final l in r.resumo) {
      expect(l.variacao ?? '', isNot(contains('▲')));
      expect(l.variacao ?? '', isNot(contains('▼')));
    }
  });

  test('data do pedido sai no horário local, não em UTC', () {
    final utc = DateTime.utc(2026, 12, 1, 1, 0);
    final l = utc.toLocal();
    final esperado = '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
    final r = _monta(entregues: [_pedido(1, fim: utc)]);
    expect(r.entregues.single[0], esperado);
  });

  test('mês só com saídas: resultado negativo e margem em traço', () {
    final r = _monta(saidas: [_saida(DateTime(2026, 11, 3), 1, 3000)]);
    expect(r.resumo[3].valor, '-R\$ 30,00');
    expect(r.resumo[4].valor, '—');
  });

  test('textos longos continuam gerando um PDF válido', () async {
    final r = _monta(
      saidas: [
        _saida(DateTime(2026, 11, 3), 1, 3000, desc: 'D' * 120),
      ],
      entregues: [
        _pedido(1,
            cliente: 'C' * 80, fim: DateTime(2026, 11, 4), total: 10),
      ],
    );
    final bytes = await pdfDoRelatorio(r);
    expect(utf8.decode(bytes.sublist(0, 4), allowMalformed: true), '%PDF');
  });

  test('aviso histórico: um predicado e um texto', () {
    expect(avisoHistoricoAte(2026, 11), isTrue);
    expect(avisoHistoricoAte(2025, 12), isTrue);
    expect(avisoHistoricoAte(2026, 12), isFalse);
    expect(textoAvisoHistorico, 'Até 23/11/2026, a data é a do pedido.');
  });
}
