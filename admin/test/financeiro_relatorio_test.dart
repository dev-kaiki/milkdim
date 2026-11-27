import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/financeiro/modelos_financeiro.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/services/financeiro_service.dart';
import 'package:milkdim_admin/services/supabase_service.dart';
import 'package:milkdim_admin/tabs/financeiro_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Pedido _ped(int id, double total) => Pedido(
      id: id,
      itens: [PedidoItem(nome: 'Queijo', preco: total, quantidade: 1)],
      total: total,
      status: 'finalizado',
      vendedorNome: 'Ana',
      finalizadoEm: DateTime(2026, 11, 5, 10),
    );

class _Fonte implements FonteFinanceiro {
  bool falhar;
  _Fonte({this.falhar = false});

  @override
  Future<List<Pedido>> pedidosEntregues(DateTime i, DateTime f) async {
    if (falhar) throw RepoFailure('Sem conexão.');
    return [_ped(1, 100), _ped(2, 50)];
  }

  @override
  Future<List<Pedido>> pedidosProntos() async => [];
  @override
  Future<List<Saida>> saidasEntre(DateTime i, DateTime f) async => [
        Saida(
            id: 1,
            data: DateTime(2026, 11, 5),
            categoriaId: 1,
            descricao: 'Conta de luz',
            valorCentavos: 3000),
      ];
  @override
  Future<List<CategoriaSaida>> categorias() async =>
      const [CategoriaSaida(id: 1, nome: 'Aluguel', ativa: true, ordem: 1)];
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

Future<void> _abrir(WidgetTester t, _Fonte f,
    {Future<void> Function(Uint8List, String)? imprimir}) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(
      body: FinanceiroTab(
        fonte: f,
        agora: () => DateTime(2026, 11, 25, 9, 30),
        imprimirRelatorio: imprimir,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Finder get _botao => find.widgetWithText(OutlinedButton, 'Relatório (PDF)');

void main() {
  testWidgets('botão fica desligado com erro', (t) async {
    await _abrir(t, _Fonte(falhar: true));
    expect(_botao, findsOneWidget);
    expect(t.widget<OutlinedButton>(_botao).onPressed, isNull);
  });

  testWidgets('botão fica desligado enquanto carrega e liga depois',
      (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
        body: FinanceiroTab(
            fonte: _Fonte(), agora: () => DateTime(2026, 11, 25)),
      ),
    ));
    expect(t.widget<OutlinedButton>(_botao).onPressed, isNull);
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(_botao).onPressed, isNotNull);
  });

  testWidgets('toque entrega o PDF e o nome do mês na tela', (t) async {
    Uint8List? bytes;
    String? nome;
    var chamadas = 0;
    await _abrir(t, _Fonte(), imprimir: (b, n) async {
      chamadas++;
      bytes = b;
      nome = n;
    });
    await t.tap(_botao);
    await t.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await t.pumpAndSettle();
    expect(chamadas, 1);
    expect(nome, 'Relatorio_MilkDim_2026-11.pdf');
    expect(String.fromCharCodes(bytes!.sublist(0, 4)), '%PDF');
  });

  testWidgets('falha ao imprimir mostra aviso e não quebra', (t) async {
    await _abrir(t, _Fonte(), imprimir: (b, n) async {
      throw Exception('sem impressora');
    });
    await t.tap(_botao);
    await t.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await t.pumpAndSettle();
    expect(find.text('Não foi possível gerar o relatório.'), findsOneWidget);
    expect(find.text('Novembro 2026'), findsOneWidget);
    expect(t.widget<OutlinedButton>(_botao).onPressed, isNotNull);
  });

  testWidgets('nome do arquivo é do mês em que o botão foi tocado',
      (t) async {
    String? nome;
    await _abrir(t, _Fonte(), imprimir: (b, n) async => nome = n);
    await t.tap(_botao);
    await t.pump();
    await t.tap(find.byTooltip('Próximo mês'));
    await t.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await t.pumpAndSettle();
    expect(nome, 'Relatorio_MilkDim_2026-11.pdf');
  });

  testWidgets('segundo toque durante a geração não imprime duas vezes',
      (t) async {
    final libera = Completer<void>();
    var chamadas = 0;
    await _abrir(t, _Fonte(), imprimir: (b, n) async {
      chamadas++;
      await libera.future;
    });
    await t.tap(_botao);
    await t.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await t.pump();
    expect(t.widget<OutlinedButton>(_botao).onPressed, isNull);
    await t.tap(_botao, warnIfMissed: false);
    await t.pump();
    libera.complete();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(chamadas, 1);
  });
}
