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
            const [CategoriaSaida(id: 1, nome: 'Aluguel', ativa: true, ordem: 1)];

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

Future<void> _abrir(WidgetTester t, _FonteFalsa f, DateTime agora) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(body: FinanceiroTab(fonte: f, agora: () => agora)),
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
    expect(f.inicios.last, DateTime(2026, 10, 1));
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
    expect(find.text('Frete antigo'), findsWidgets);
    expect(find.text('Sem categoria'), findsNothing);
  });
}
