import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/volumes.dart';
import 'package:milkdim_admin/models/produto.dart';
import 'package:milkdim_admin/services/caixas_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart' show RepoFailure;
import 'package:milkdim_admin/tabs/produtos_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

class _Fonte implements FonteCaixas {
  List<TipoCaixa> tipos;
  final defs = <(int, int?)>[];
  final criados = <(String, int, bool)>[];
  final alterados = <TipoCaixa>[];
  Object? erroCriar;
  _Fonte(this.tipos);

  @override
  Future<List<TipoCaixa>> tiposCaixa() async => tipos;
  @override
  Future<void> criarTipo(String nome, int capacidade, bool mistura) async {
    if (erroCriar != null) throw erroCriar!;
    criados.add((nome, capacidade, mistura));
  }

  @override
  Future<void> alterarTipo(TipoCaixa t) async => alterados.add(t);
  @override
  Future<VolumesPedido?> volumesSalvos(int pedidoId) async => null;
  @override
  Future<void> salvarVolumes(int pedidoId, VolumesPedido v) async {}
  @override
  Future<void> definirTipoDoProduto(int produtoId, int? tipoId) async =>
      defs.add((produtoId, tipoId));
}

const _copo = TipoCaixa(id: 7, nome: 'Copo', capacidade: 20, misturaSabores: true, ativo: true);
const _pote = TipoCaixa(id: 8, nome: 'Pote', capacidade: 16, misturaSabores: true, ativo: true);
const _velho = TipoCaixa(id: 9, nome: 'Velho', capacidade: 5, misturaSabores: true, ativo: false);

Produto _p(int id, String nome, {int? tipo}) =>
    Produto(id: id, nome: nome, preco: 5, ativo: true, tipoCaixaId: tipo);

Future<void> _abrir(WidgetTester tester, _Fonte f, List<Produto> ps,
    {Size tamanho = const Size(900, 1600),
    Future<int> Function(Map<String, dynamic>, int?)? gravar}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(
      body: ProdutosTab(
        carregar: () async => List.of(ps),
        fonteCaixas: f,
        gravar: gravar ?? (m, id) async => id ?? 99,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _escolher(WidgetTester tester, String texto) async {
  await tester.tap(find.byType(DropdownButtonFormField<int?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(texto).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista mostra Avulso e Caixa: Copo (20)', (tester) async {
    await _abrir(tester, _Fonte([_copo]), [_p(1, 'Pudim'), _p(2, 'Copo leite', tipo: 7)]);
    expect(find.text('Avulso'), findsOneWidget);
    expect(find.text('Caixa: Copo (20)'), findsOneWidget);
  });

  testWidgets('escolher Copo e salvar chama definirTipoDoProduto', (tester) async {
    final f = _Fonte([_copo, _pote, _velho]);
    await _abrir(tester, f, [_p(1, 'Pudim')]);
    await tester.tap(find.text('Pudim'));
    await tester.pumpAndSettle();
    await _escolher(tester, 'Copo (20)');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(f.defs, [(1, 7)]);
  });

  testWidgets('produto novo grava o tipo com o id devolvido', (tester) async {
    final f = _Fonte([_copo]);
    await _abrir(tester, f, [], gravar: (m, id) async => 42);
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Novo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Preço *'), '3,50');
    await _escolher(tester, 'Copo (20)');
    await tester.tap(find.text('Adicionar').last);
    await tester.pumpAndSettle();
    expect(f.defs, [(42, 7)]);
  });

  testWidgets('Sem caixa (avulso) grava null', (tester) async {
    final f = _Fonte([_copo]);
    await _abrir(tester, f, [_p(1, 'Copo leite', tipo: 7)]);
    await tester.tap(find.text('Copo leite'));
    await tester.pumpAndSettle();
    await _escolher(tester, 'Sem caixa (avulso)');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(f.defs, [(1, null)]);
  });

  testWidgets('sem mudar o tipo não chama definirTipoDoProduto', (tester) async {
    final f = _Fonte([_copo]);
    await _abrir(tester, f, [_p(1, 'Copo leite', tipo: 7)]);
    await tester.tap(find.text('Copo leite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(f.defs, isEmpty);
  });

  testWidgets('tipo inativo fora da lista, mas selecionado se já é do produto',
      (tester) async {
    final f = _Fonte([_copo, _velho]);
    await _abrir(tester, f, [_p(1, 'A'), _p(2, 'B', tipo: 9)]);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    expect(find.text('Velho (5) (desativado)'), findsNothing);
    expect(find.text('Copo (20)'), findsWidgets);
    await tester.tap(find.text('Sem caixa (avulso)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('Velho (5) (desativado)'), findsOneWidget);
  });

  testWidgets('dialogo de tipos: capacidade 0 mostra Capacidade inválida.',
      (tester) async {
    final f = _Fonte([_copo, _velho]);
    await _abrir(tester, f, [_p(1, 'A')]);
    await tester.tap(find.text('Tipos de caixa'));
    await tester.pumpAndSettle();
    expect(find.text('Velho (desativado)'), findsOneWidget);
    await tester.tap(find.text('Novo tipo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), ' Grande ');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Capacidade (unidades) *'), '0');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Capacidade inválida.'), findsOneWidget);
    expect(f.criados, isEmpty);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Capacidade (unidades) *'), '12');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(f.criados, [('Grande', 12, true)]);
  });

  testWidgets('erro do serviço aparece em SnackBar', (tester) async {
    final f = _Fonte([_copo])
      ..erroCriar = RepoFailure('Já existe um tipo de caixa com esse nome.');
    await _abrir(tester, f, [_p(1, 'A')]);
    await tester.tap(find.text('Tipos de caixa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo tipo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Copo');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Capacidade (unidades) *'), '20');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Já existe um tipo de caixa com esse nome.'), findsOneWidget);
  });

  testWidgets('360 px: lista e diálogos sem estourar', (tester) async {
    final f = _Fonte([_copo, _velho]);
    await _abrir(
        tester, f, [_p(1, 'Copo leite em pó 160g muito longo para quebrar linha', tipo: 7)],
        tamanho: const Size(360, 740));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Tipos de caixa'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Novo tipo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Copo leite'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
