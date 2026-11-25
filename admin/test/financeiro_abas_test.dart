import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/services/financeiro_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart';
import 'package:milkdim_admin/tabs/financeiro_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Pedido _ped(int id, double total, DateTime quando,
        {String cliente = 'Mercado Sol', int clienteId = 5}) =>
    Pedido(
      id: id,
      itens: [PedidoItem(nome: 'Queijo', preco: total, quantidade: 1)],
      total: total,
      status: 'finalizado',
      vendedorNome: 'Ana',
      clienteId: clienteId,
      clienteNome: cliente,
      finalizadoEm: quando,
    );

Saida _saida(int cent, DateTime data) => Saida(
      id: 1,
      data: data,
      categoriaId: 1,
      descricao: 'Conta de luz',
      valorCentavos: cent,
    );

class _Fonte implements FonteFinanceiro {
  List<Pedido> entregues;
  List<Saida> saidas;
  bool falhar;
  final inicios = <DateTime>[];

  _Fonte({this.entregues = const [], this.saidas = const [], this.falhar = false});

  @override
  Future<List<Pedido>> pedidosEntregues(DateTime i, DateTime f) async {
    inicios.add(i);
    if (falhar) throw RepoFailure('Sem conexão.');
    return entregues;
  }

  @override
  Future<List<Pedido>> pedidosProntos() async => [];
  @override
  Future<List<Saida>> saidasEntre(DateTime i, DateTime f) async => saidas;
  @override
  Future<List<CategoriaSaida>> categorias() async => const [
        CategoriaSaida(id: 1, nome: 'Aluguel', ativa: true, ordem: 1)
      ];
  @override
  Future<void> inserirSaida(Saida s) async {}
  @override
  Future<void> alterarSaida(Saida s) async {}
  @override
  Future<void> apagarSaida(int id) async {}
  @override
  Future<void> criarCategoria(String nome) async {}
  @override
  Future<void> renomearCategoria(int id, String nome) async {}
  @override
  Future<void> definirCategoriaAtiva(int id, bool ativa) async {}
}

Future<void> _abrir(WidgetTester t, _Fonte f, DateTime agora,
    {double largura = 1000}) async {
  t.view.physicalSize = Size(largura, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(body: FinanceiroTab(fonte: f, agora: () => agora)),
  ));
  await t.pumpAndSettle();
}

Future<void> _aba(WidgetTester t, String nome) async {
  await t.tap(find.widgetWithText(Tab, nome));
  await t.pumpAndSettle();
}

void main() {
  final agora = DateTime(2026, 11, 25);

  testWidgets('mostra as quatro abas e abre no Resumo', (t) async {
    await _abrir(t, _Fonte(), agora);
    for (final n in ['Resumo', 'Vendas', 'Saídas', 'Ano']) {
      expect(find.widgetWithText(Tab, n), findsOneWidget);
    }
    expect(find.text('Resultado do mês'), findsOneWidget);
  });

  testWidgets('Resumo mostra variação e ticket médio', (t) async {
    final f = _Fonte(entregues: [
      _ped(1, 100, DateTime(2026, 10, 10)),
      _ped(2, 150, DateTime(2026, 11, 5)),
    ]);
    await _abrir(t, f, agora);
    expect(find.textContaining('50%'), findsWidgets);
    expect(find.textContaining('▲ 50%'), findsNWidgets(2),
        reason: 'vendas e resultado');
    expect(find.textContaining('1 pedido · ticket médio R\$ 150,00'),
        findsOneWidget);
  });

  testWidgets('Resumo: ticket e margem com traço sem vendas', (t) async {
    await _abrir(t, _Fonte(), agora);
    expect(find.textContaining('0 pedidos · ticket médio —'), findsOneWidget);
    expect(find.text('margem —'), findsOneWidget);
  });

  testWidgets('Resumo: destaques com — quando não há saídas', (t) async {
    await _abrir(t, _Fonte(entregues: [_ped(1, 100, DateTime(2026, 11, 5))]),
        agora);
    expect(find.text('Maior gasto'), findsOneWidget);
    final card = find.ancestor(
        of: find.text('Maior gasto'), matching: find.byType(MdCard));
    expect(find.descendant(of: card, matching: find.text('—')), findsOneWidget);
    expect(find.text('Queijo'), findsOneWidget);
    expect(find.text('1 un · 100% das vendas'), findsOneWidget);
  });

  testWidgets('Vendas mostra melhores clientes', (t) async {
    await _abrir(
        t, _Fonte(entregues: [_ped(1, 100, DateTime(2026, 11, 5))]), agora);
    await _aba(t, 'Vendas');
    expect(find.text('Melhores clientes'), findsOneWidget);
    expect(find.text('Mercado Sol'), findsOneWidget);
    expect(find.text('Vendas por produto'), findsOneWidget);
    expect(find.text('Vendas por vendedor'), findsOneWidget);
  });

  testWidgets('Saídas tem Lançar saída e Categorias', (t) async {
    await _abrir(
        t, _Fonte(saidas: [_saida(3000, DateTime(2026, 11, 5))]), agora);
    expect(find.text('Lançar saída'), findsNothing);
    await _aba(t, 'Saídas');
    expect(find.text('Lançar saída'), findsOneWidget);
    expect(find.byTooltip('Categorias'), findsOneWidget);
    expect(find.text('Saídas do mês'), findsOneWidget);
  });

  testWidgets('Ano mostra 12 meses, — nos meses sem dado e Total', (t) async {
    final f = _Fonte(
      entregues: [_ped(1, 100, DateTime(2025, 8, 10))],
      saidas: [_saida(3000, DateTime(2025, 9, 5))],
    );
    await _abrir(t, f, DateTime(2025, 9, 25));
    await _aba(t, 'Ano');
    expect(find.text('Total'), findsOneWidget);
    // 10 meses sem dado (5 traços cada) + a margem de set/25 (sem vendas).
    expect(find.text('—'), findsNWidgets(51));
    expect(find.text('Ago/25'), findsOneWidget);
    expect(find.text('Set/25'), findsOneWidget);
    expect(find.text('Out/24'), findsOneWidget);
    expect(find.byKey(const ValueKey('grafico-ano')), findsOneWidget);
  });

  testWidgets('erro de carga: todas as abas mostram Tentar de novo',
      (t) async {
    await _abrir(t, _Fonte(falhar: true), agora);
    for (final n in ['Resumo', 'Vendas', 'Saídas', 'Ano']) {
      await _aba(t, n);
      expect(find.text('Tentar de novo'), findsOneWidget, reason: n);
      expect(find.text('R\$ 0,00'), findsNothing, reason: n);
    }
  });

  testWidgets('360 px: nenhuma aba estoura', (t) async {
    final f = _Fonte(
      entregues: [
        _ped(1, 8420, DateTime(2026, 11, 5)),
        _ped(2, 50, DateTime(2026, 10, 5), cliente: 'Padaria Muito Longa Ltda'),
      ],
      saidas: [_saida(329000, DateTime(2026, 11, 5))],
    );
    await _abrir(t, f, agora, largura: 360);
    for (final n in ['Resumo', 'Vendas', 'Saídas', 'Ano']) {
      await _aba(t, n);
      expect(t.takeException(), isNull, reason: n);
    }
  });

  testWidgets('Resumo: card de Saídas mostra o mês todo, seta usa o recorte',
      (t) async {
    final f = _Fonte(saidas: [
      _saida(10000, DateTime(2026, 10, 10)),
      _saida(20000, DateTime(2026, 11, 10)),
      _saida(30000, DateTime(2026, 11, 28)), // futura: fora da seta
    ]);
    await _abrir(t, f, agora);
    expect(find.text('R\$ 500,00'), findsWidgets, reason: 'mês todo no card');
    final seta = find.textContaining('▲ 100%');
    expect(seta, findsOneWidget, reason: '200 vs 100 no recorte');
    final card = find.ancestor(of: seta, matching: find.byType(MdCard));
    expect(find.descendant(of: card, matching: find.text('Saídas')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('R\$ 500,00')),
        findsOneWidget);
    final cor = t.widget<Text>(seta).style!.color;
    expect(cor, Theme.of(t.element(seta)).colorScheme.error);
  });

  testWidgets('Saídas do mês não lista saída do mês anterior', (t) async {
    final f = _Fonte(saidas: [
      Saida(
          id: 1,
          data: DateTime(2026, 10, 20),
          categoriaId: 1,
          descricao: 'Conta antiga',
          valorCentavos: 1111),
      Saida(
          id: 2,
          data: DateTime(2026, 11, 5),
          categoriaId: 1,
          descricao: 'Conta nova',
          valorCentavos: 2222),
    ]);
    await _abrir(t, f, agora);
    await _aba(t, 'Saídas');
    expect(find.textContaining('Conta nova'), findsWidgets);
    expect(find.textContaining('Conta antiga'), findsNothing);
  });

  testWidgets('pedido finalizado 31/10 23:30 local não conta em novembro',
      (t) async {
    final instante = DateTime(2026, 10, 31, 23, 30).toUtc();
    await _abrir(t, _Fonte(entregues: [_ped(1, 100, instante)]), agora);
    expect(find.textContaining('0 pedidos · ticket médio —'), findsOneWidget);
  });

  testWidgets('pedido finalizado 31/10 23:30 local conta em outubro',
      (t) async {
    final instante = DateTime(2026, 10, 31, 23, 30).toUtc();
    await _abrir(t, _Fonte(entregues: [_ped(1, 100, instante)]),
        DateTime(2026, 10, 31, 23, 45));
    expect(find.textContaining('1 pedido · ticket médio R\$ 100,00'),
        findsOneWidget);
  });

  testWidgets('carga busca 12 meses', (t) async {
    final f = _Fonte();
    await _abrir(t, f, agora);
    expect(f.inicios.last, DateTime(2025, 12, 1));
  });
}
