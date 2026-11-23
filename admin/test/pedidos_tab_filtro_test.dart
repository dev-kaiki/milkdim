import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/tabs/pedidos_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Pedido _p(int id, String status, String cliente) => Pedido(
      id: id,
      numero: '$id',
      status: status,
      total: 10,
      clienteNome: cliente,
      itens: const [PedidoItem(nome: 'Pudim', preco: 1, quantidade: 1)],
    );

void main() {
  testWidgets('filtro por situação filtra a lista carregada', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
        body: PedidosTab(carregar: () async => [
              _p(1, 'salvo', 'Cliente Aberto'),
              _p(2, 'finalizado', 'Cliente Pronto'),
              _p(3, 'cancelado', 'Cliente Cancelado'),
            ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Cliente Aberto'), findsOneWidget);
    expect(find.text('Cliente Pronto'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('Em aberto')));
    await tester.pumpAndSettle();
    expect(find.text('Cliente Aberto'), findsOneWidget);
    expect(find.text('Cliente Pronto'), findsNothing);

    await tester.tap(find.text('Cancelados'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente Cancelado'), findsOneWidget);
    expect(find.text('Cliente Aberto'), findsNothing);

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente Pronto'), findsOneWidget);
  });

  testWidgets('tocar no pedido abre o detalhe com Apagar', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = _p(5, 'finalizado', 'Cliente Detalhe');
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
        body: PedidosTab(
          carregar: () async => [p],
          buscarDetalhe: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cliente Detalhe'));
    await tester.pumpAndSettle();

    expect(find.text('Dados do cliente'), findsOneWidget);
    expect(find.byTooltip('Apagar pedido'), findsOneWidget);
  });
}
