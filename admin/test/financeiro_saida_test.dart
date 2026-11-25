import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/dialogo_saida.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/services/financeiro_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart';
import 'package:milkdim_admin/tabs/financeiro_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

class _Fonte implements FonteFinanceiro {
  List<Saida> saidas;
  List<CategoriaSaida> cats;
  final inseridas = <Saida>[];
  final alteradas = <Saida>[];
  final apagadas = <int>[];
  final criadas = <String>[];
  final renomeadas = <(int, String)>[];
  final ativas = <(int, bool)>[];
  RepoFailure? erroCriar;
  int carregamentos = 0;

  _Fonte({this.saidas = const [], List<CategoriaSaida>? cats})
      : cats = cats ??
            const [
              CategoriaSaida(
                  id: 1, nome: 'Matéria-prima', ativa: true, ordem: 1),
              CategoriaSaida(id: 2, nome: 'Aluguel', ativa: true, ordem: 2),
              CategoriaSaida(
                  id: 3, nome: 'Frete antigo', ativa: false, ordem: 3),
            ];

  @override
  Future<List<Pedido>> pedidosEntregues(DateTime i, DateTime f) async {
    carregamentos++;
    return [];
  }

  @override
  Future<List<Pedido>> pedidosProntos() async => [];
  @override
  Future<List<Saida>> saidasEntre(DateTime i, DateTime f) async => saidas;
  @override
  Future<List<CategoriaSaida>> categorias() async => cats;
  @override
  Future<void> inserirSaida(Saida s) async => inseridas.add(s);
  @override
  Future<void> alterarSaida(Saida s) async => alteradas.add(s);
  @override
  Future<void> apagarSaida(int id) async => apagadas.add(id);
  @override
  Future<void> criarCategoria(String nome) async {
    if (erroCriar != null) throw erroCriar!;
    criadas.add(nome);
  }

  @override
  Future<void> renomearCategoria(int id, String nome) async =>
      renomeadas.add((id, nome));
  @override
  Future<void> definirCategoriaAtiva(int id, bool ativa) async =>
      ativas.add((id, ativa));
}

final _hoje = DateTime(2026, 11, 25);

Future<void> _abrir(WidgetTester t, _Fonte f, {double largura = 1000}) async {
  t.view.physicalSize = Size(largura, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(body: FinanceiroTab(fonte: f, agora: () => _hoje)),
  ));
  await t.pumpAndSettle();
}

Saida _saidaExistente() => Saida(
      id: 7,
      data: DateTime(2026, 11, 5),
      categoriaId: 2,
      descricao: 'Conta de luz',
      valorCentavos: 30000,
    );

void main() {
  testWidgets('lançar saída válida chama inserirSaida com centavos', (t) async {
    final f = _Fonte();
    await _abrir(t, f);
    await t.tap(find.text('Lançar saída'));
    await t.pumpAndSettle();

    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Matéria-prima').last);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Valor'), '1.234,56');
    await t.enterText(find.widgetWithText(TextField, 'Descrição'), 'Leite');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();

    expect(f.inseridas, hasLength(1));
    final s = f.inseridas.single;
    expect(s.valorCentavos, 123456);
    expect(s.categoriaId, 1);
    expect(s.descricao, 'Leite');
    expect(s.data, _hoje);
    expect(f.carregamentos, 2, reason: 'recarrega o mês depois de gravar');
  });

  testWidgets('valor inválido não grava', (t) async {
    final f = _Fonte();
    await _abrir(t, f);
    await t.tap(find.text('Lançar saída'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Matéria-prima').last);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Valor'), '0');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('Valor inválido.'), findsOneWidget);
    expect(f.inseridas, isEmpty);
  });

  testWidgets('sem categoria mostra Escolha a categoria.', (t) async {
    final f = _Fonte();
    await _abrir(t, f);
    await t.tap(find.text('Lançar saída'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Valor'), '10');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('Escolha a categoria.'), findsOneWidget);
    expect(f.inseridas, isEmpty);
  });

  testWidgets('categoria desativada não aparece para lançar', (t) async {
    final f = _Fonte();
    await _abrir(t, f);
    await t.tap(find.text('Lançar saída'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    expect(find.text('Frete antigo'), findsNothing);
    expect(find.text('Aluguel'), findsWidgets);
  });

  testWidgets('editar saída de categoria desativada mantém a seleção',
      (t) async {
    final f = _Fonte(saidas: [
      Saida(
          id: 9,
          data: DateTime(2026, 11, 5),
          categoriaId: 3,
          valorCentavos: 100),
    ]);
    await _abrir(t, f);
    await t.tap(find.text('Frete antigo').last);
    await t.pumpAndSettle();
    // Selecionada no campo do diálogo (além da linha da lista e do quadro).
    expect(find.text('Frete antigo'), findsWidgets);
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(f.alteradas.single.categoriaId, 3);
  });

  testWidgets('apagar pede confirmação', (t) async {
    final f = _Fonte(saidas: [_saidaExistente()]);
    await _abrir(t, f);
    await t.tap(find.byTooltip('Apagar saída'));
    await t.pumpAndSettle();
    expect(find.text('Apagar esta saída?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(f.apagadas, isEmpty);

    await t.tap(find.byTooltip('Apagar saída'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apagar'));
    await t.pumpAndSettle();
    expect(f.apagadas, [7]);
    expect(f.carregamentos, 2);
  });

  testWidgets('editar mantém o id e chama alterarSaida', (t) async {
    final f = _Fonte(saidas: [_saidaExistente()]);
    await _abrir(t, f);
    await t.tap(find.text('Conta de luz'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Valor'), '50');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(f.alteradas, hasLength(1));
    expect(f.alteradas.single.id, 7);
    expect(f.alteradas.single.valorCentavos, 5000);
    expect(f.alteradas.single.categoriaId, 2);
    expect(f.inseridas, isEmpty);
  });

  testWidgets('categoria duplicada mostra a mensagem do serviço', (t) async {
    final f = _Fonte()
      ..erroCriar = RepoFailure('Já existe uma categoria com esse nome.');
    await _abrir(t, f);
    await t.tap(find.byTooltip('Categorias'));
    await t.pumpAndSettle();
    expect(find.text('Frete antigo (desativada)'), findsOneWidget);
    await t.tap(find.text('Nova categoria'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Aluguel');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(find.text('Já existe uma categoria com esse nome.'), findsOneWidget);
    expect(f.criadas, isEmpty);
  });

  testWidgets('criar, renomear e desativar categoria chamam o serviço',
      (t) async {
    final f = _Fonte();
    await _abrir(t, f);
    await t.tap(find.byTooltip('Categorias'));
    await t.pumpAndSettle();

    await t.tap(find.text('Nova categoria'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Telefone');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(f.criadas, ['Telefone']);

    await t.tap(find.byTooltip('Renomear').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Insumos');
    await t.tap(find.text('Salvar'));
    await t.pumpAndSettle();
    expect(f.renomeadas, [(1, 'Insumos')]);

    await t.tap(find.byTooltip('Desativar').first);
    await t.pumpAndSettle();
    expect(f.ativas, [(1, false)]);

    await t.tap(find.byTooltip('Reativar'));
    await t.pumpAndSettle();
    expect(f.ativas.last, (3, true));
  });

  group('validarDataSaida', () {
    test('aceita hoje e até 365 dias à frente', () {
      expect(validarDataSaida(_hoje, _hoje), isNull);
      expect(validarDataSaida(_hoje.add(const Duration(days: 365)), _hoje),
          isNull);
    });
    test('recusa depois de 365 dias', () {
      expect(validarDataSaida(_hoje.add(const Duration(days: 366)), _hoje),
          'Data muito no futuro.');
    });
  });

  testWidgets('em 360px não estoura; Lançar saída e Categorias aparecem',
      (t) async {
    final f = _Fonte(saidas: [_saidaExistente()]);
    await _abrir(t, f, largura: 360);
    expect(t.takeException(), isNull);
    expect(find.text('Lançar saída'), findsOneWidget);
    expect(find.byTooltip('Categorias'), findsOneWidget);
  });
}
