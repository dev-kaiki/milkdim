import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/services/financeiro_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart';
import 'package:milkdim_admin/tabs/financeiro_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Pedido _ped(int id, double total, {String status = 'finalizado'}) => Pedido(
      id: id,
      itens: [PedidoItem(nome: 'Queijo', preco: total, quantidade: 1)],
      total: total,
      status: status,
      vendedorNome: 'Ana',
      finalizadoEm: DateTime(2026, 11, 5, 10),
    );

class _FonteFalsa implements FonteFinanceiro {
  List<Pedido> entregues;
  List<Pedido> prontos;
  List<Saida> saidas;
  List<CategoriaSaida> cats;
  bool falhar;
  int chamadas = 0;
  final inicios = <DateTime>[];

  _FonteFalsa({
    this.entregues = const [],
    this.prontos = const [],
    this.saidas = const [],
    List<CategoriaSaida>? cats,
    this.falhar = false,
  }) : cats = cats ??
            const [
              CategoriaSaida(id: 1, nome: 'Aluguel', ativa: true, ordem: 1)
            ];

  @override
  Future<List<Pedido>> pedidosEntregues(DateTime i, DateTime f) async {
    chamadas++;
    inicios.add(i);
    if (falhar) throw RepoFailure('Sem conexão.');
    return entregues;
  }

  @override
  Future<List<Pedido>> pedidosProntos() async => prontos;
  @override
  Future<List<Saida>> saidasEntre(DateTime i, DateTime f) async => saidas;
  @override
  Future<List<CategoriaSaida>> categorias() async => cats;
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

Saida _saida(int cent, {int cat = 1}) => Saida(
      id: 1,
      data: DateTime(2026, 11, 5),
      categoriaId: cat,
      descricao: 'Conta de luz',
      valorCentavos: cent,
    );

Future<void> _abrir(WidgetTester t, _FonteFalsa f, DateTime agora,
    {double largura = 1000, ValueListenable<bool>? aberta}) async {
  t.view.physicalSize = Size(largura, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(body: FinanceiroTab(fonte: f, agora: () => agora, aberta: aberta)),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('mostra vendas, saídas e resultado do mês atual', (t) async {
    final f = _FonteFalsa(
      entregues: [_ped(1, 100), _ped(2, 50)],
      prontos: [_ped(3, 20, status: 'pronto')],
      saidas: [_saida(3000)],
    );
    await _abrir(t, f, DateTime(2026, 11, 25));
    expect(find.text('Novembro 2026'), findsOneWidget);
    expect(find.text('R\$ 150,00'), findsWidgets);
    expect(find.text('R\$ 30,00'), findsWidgets);
    expect(find.text('R\$ 120,00'), findsOneWidget);
    expect(find.text('A receber'), findsOneWidget);
    expect(find.text('Lançar saída'), findsNothing,
        reason: 'o botão fica na aba Saídas');
    await t.tap(find.widgetWithText(Tab, 'Saídas'));
    await t.pumpAndSettle();
    expect(find.text('Lançar saída'), findsOneWidget);
  });

  testWidgets('mês anterior não mostra A receber e mostra o aviso de histórico',
      (t) async {
    final f = _FonteFalsa(entregues: [_ped(1, 100)]);
    await _abrir(t, f, DateTime(2026, 11, 25));
    await t.tap(find.byTooltip('Mês anterior'));
    await t.pumpAndSettle();
    expect(find.text('Outubro 2026'), findsOneWidget);
    expect(find.text('A receber'), findsNothing);
    expect(find.text('Até 23/11/2026, a data é a do pedido.'), findsOneWidget);
    // Carga de 12 meses: começa 11 meses antes de outubro/2026.
    expect(f.inicios.last, DateTime(2025, 11, 1));
  });

  testWidgets('dezembro de 2026 não mostra o aviso', (t) async {
    await _abrir(t, _FonteFalsa(), DateTime(2026, 12, 10));
    expect(find.text('Dezembro 2026'), findsOneWidget);
    expect(find.text('Até 23/11/2026, a data é a do pedido.'), findsNothing);
  });

  testWidgets('erro de rede mostra Tentar de novo e não zeros', (t) async {
    final f = _FonteFalsa(falhar: true);
    await _abrir(t, f, DateTime(2026, 11, 25));
    expect(find.text('Tentar de novo'), findsOneWidget);
    expect(find.text('R\$ 0,00'), findsNothing);
    await t.tap(find.text('Tentar de novo'));
    await t.pumpAndSettle();
    expect(f.chamadas, 2);
  });

  testWidgets('resultado negativo aparece com sinal', (t) async {
    final f = _FonteFalsa(entregues: [_ped(1, 10)], saidas: [_saida(5000)]);
    await _abrir(t, f, DateTime(2026, 11, 25));
    expect(find.text('-R\$ 40,00'), findsOneWidget);
  });

  testWidgets('saída de categoria desativada aparece com o nome', (t) async {
    final f = _FonteFalsa(
      saidas: [_saida(3000, cat: 9)],
      cats: const [
        CategoriaSaida(id: 9, nome: 'Frete antigo', ativa: false, ordem: 9),
      ],
    );
    await _abrir(t, f, DateTime(2026, 11, 25));
    await t.tap(find.widgetWithText(Tab, 'Saídas'));
    await t.pumpAndSettle();
    expect(find.text('Frete antigo'), findsWidgets);
    expect(find.text('Sem categoria'), findsNothing);
  });

  testWidgets('em 360px não estoura e o botão Lançar saída aparece na aba Saídas',
      (t) async {
    final f = _FonteFalsa(
      entregues: [_ped(1, 8420), _ped(2, 50)],
      prontos: [_ped(3, 1234.5, status: 'pronto')],
      saidas: [_saida(329000)],
    );
    await _abrir(t, f, DateTime(2026, 11, 25), largura: 360);
    expect(t.takeException(), isNull);
    expect(find.text('Novembro 2026'), findsOneWidget);
    await t.tap(find.widgetWithText(Tab, 'Saídas'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Lançar saída'), findsOneWidget);
  });

  testWidgets('selecionar a aba de novo recarrega (e fechar não)', (t) async {
    final f = _FonteFalsa();
    final aberta = ValueNotifier(true);
    await _abrir(t, f, DateTime(2026, 11, 25), aberta: aberta);
    expect(f.chamadas, 1);
    aberta.value = false;
    await t.pumpAndSettle();
    expect(f.chamadas, 1);
    aberta.value = true;
    await t.pumpAndSettle();
    expect(f.chamadas, 2);
    aberta.value = false;
    aberta.value = true;
    await t.pumpAndSettle();
    expect(f.chamadas, 3);
  });

  testWidgets('virou o mês: quem olhava o mês atual pula para o novo',
      (t) async {
    final f = _FonteFalsa();
    final aberta = ValueNotifier(true);
    var agora = DateTime(2026, 11, 30);
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
          body: FinanceiroTab(
              fonte: f, agora: () => agora, aberta: aberta)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Novembro 2026'), findsOneWidget);
    agora = DateTime(2026, 12, 1);
    aberta.value = false;
    aberta.value = true;
    await t.pumpAndSettle();
    expect(find.text('Dezembro 2026'), findsOneWidget);
    expect(f.inicios.last, DateTime(2026, 1, 1)); // 12 meses até dez/2026
    expect(find.text('A receber'), findsOneWidget);
  });

  testWidgets('virou o mês: quem olhava outro mês fica onde estava',
      (t) async {
    final f = _FonteFalsa();
    final aberta = ValueNotifier(true);
    var agora = DateTime(2026, 11, 30);
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
          body: FinanceiroTab(
              fonte: f, agora: () => agora, aberta: aberta)),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Mês anterior'));
    await t.pumpAndSettle();
    agora = DateTime(2026, 12, 1);
    aberta.value = false;
    aberta.value = true;
    await t.pumpAndSettle();
    expect(find.text('Outubro 2026'), findsOneWidget);
    expect(find.text('A receber'), findsNothing);
  });

  testWidgets('A receber segue o flag da carga, não o relógio no build',
      (t) async {
    final f = _FonteFalsa();
    var agora = DateTime(2026, 11, 25);
    Widget app() => MaterialApp(
          theme: buildMilkdimTheme(),
          home: Scaffold(
              body: FinanceiroTab(fonte: f, agora: () => agora)),
        );
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.text('A receber'), findsOneWidget);
    // O relógio anda, mas sem nova carga o flag da carga vale.
    agora = DateTime(2026, 12, 1);
    await t.pumpWidget(app());
    expect(find.text('A receber'), findsOneWidget);
  });
}
