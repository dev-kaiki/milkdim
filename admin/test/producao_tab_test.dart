import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/tabs/producao_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

const _textoFinalizar =
    'Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale a dele.';

Pedido _ped(int id, String numero, int qtd, {DateTime? alteradoEm}) => Pedido(
      id: id,
      numero: numero,
      status: 'salvo',
      total: 10,
      vendedorNome: 'Vendedor Teste',
      clienteNome: 'Cliente $numero',
      enviadoEm: DateTime.now().subtract(const Duration(hours: 3)),
      alteradoEm: alteradoEm,
      itens: [PedidoItem(nome: 'Pudim tradicional', preco: 1, quantidade: qtd)],
    );

Widget _app(Widget tab) => MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(body: tab),
    );

void main() {
  testWidgets('mostra totais a fabricar e os pedidos em aberto', (tester) async {
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [_ped(1, '318', 10), _ped(2, '319', 5)],
    )));
    await tester.pumpAndSettle();

    expect(find.text('A fabricar'), findsOneWidget);
    expect(find.text('Pedidos em aberto'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.textContaining('Pudim tradicional'), findsWidgets);
    expect(find.textContaining('318'), findsWidgets);
    expect(find.textContaining('319'), findsWidgets);
  });

  testWidgets('pedido alterado depois de enviado mostra o selo "alterado às"', (tester) async {
    final p = _ped(1, '318', 3, alteradoEm: DateTime.now().subtract(const Duration(hours: 1)));
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => [p])));
    await tester.pumpAndSettle();
    expect(find.textContaining('alterado às'), findsOneWidget);
  });

  testWidgets('sem alteração não mostra o selo', (tester) async {
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => [_ped(1, '318', 3)])));
    await tester.pumpAndSettle();
    expect(find.textContaining('alterado às'), findsNothing);
  });

  testWidgets('lista vazia mostra o estado vazio', (tester) async {
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => <Pedido>[])));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum pedido em aberto'), findsOneWidget);
  });

  testWidgets('Finalizar confirma, chama finalizar(id) uma vez e recarrega', (tester) async {
    var cargas = 0;
    final finalizados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async {
        cargas++;
        return [_ped(7, '318', 3)];
      },
      finalizar: (id) async => finalizados.add(id),
    )));
    await tester.pumpAndSettle();
    expect(cargas, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Finalizar'));
    await tester.pumpAndSettle();
    expect(find.text(_textoFinalizar), findsOneWidget);
    expect(finalizados, isEmpty);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Finalizar'),
    ));
    await tester.pumpAndSettle();

    expect(finalizados, [7]);
    expect(cargas, 2);
    expect(find.text('Pedido finalizado.'), findsOneWidget);
  });

  testWidgets('Voltar no diálogo de finalizar não chama finalizar', (tester) async {
    final finalizados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [_ped(7, '318', 3)],
      finalizar: (id) async => finalizados.add(id),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finalizar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(finalizados, isEmpty);
  });

  testWidgets('Cancelar confirma, chama cancelar(id) e recarrega', (tester) async {
    var cargas = 0;
    final cancelados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async {
        cargas++;
        return [_ped(9, '320', 2)];
      },
      cancelar: (id) async => cancelados.add(id),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pedido'));
    await tester.pumpAndSettle();

    expect(cancelados, [9]);
    expect(cargas, 2);
    expect(find.text('Pedido cancelado.'), findsOneWidget);
  });

  testWidgets('atualiza sozinho a cada intervalo', (tester) async {
    var cargas = 0;
    await tester.pumpWidget(_app(ProducaoTab(
      intervalo: const Duration(seconds: 30),
      carregar: () async {
        cargas++;
        return [_ped(1, '318', 3)];
      },
    )));
    await tester.pumpAndSettle();
    expect(cargas, 1);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(cargas, 2);
  });

  testWidgets('ao sair da tela o timer é cancelado', (tester) async {
    var cargas = 0;
    await tester.pumpWidget(_app(ProducaoTab(
      intervalo: const Duration(seconds: 30),
      carregar: () async {
        cargas++;
        return <Pedido>[];
      },
    )));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pump(const Duration(seconds: 61));
    expect(cargas, 1);
  });
}
