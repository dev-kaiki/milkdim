import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/services/supabase_service.dart';
import 'package:milkdim_admin/tabs/producao_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

const _textoFinalizar =
    'Use só se o pedido já foi entregue. Se o vendedor finalizar com assinatura depois, vale a dele.';

Pedido _ped(int id, String numero, int qtd,
        {DateTime? alteradoEm,
        String status = 'salvo',
        DateTime? prontoEm,
        String? alteradoEmBruto}) =>
    Pedido(
      id: id,
      numero: numero,
      status: status,
      prontoEm: prontoEm,
      alteradoEmBruto: alteradoEmBruto,
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
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [_ped(1, '318', 10), _ped(2, '319', 5)],
    )));
    await tester.pumpAndSettle();

    expect(find.text('A fabricar'), findsOneWidget);
    expect(find.text('Pedidos em aberto'), findsOneWidget);
    expect(find.text('Prontos para entrega'), findsOneWidget);
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
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => <Pedido>[])));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum pedido em aberto'), findsOneWidget);
    expect(find.text('Nenhum pedido pronto'), findsOneWidget);
  });

  testWidgets('secao Prontos lista so pronto', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [
        _ped(1, '318', 3),
        _ped(2, '319', 4, status: 'pronto', prontoEm: DateTime.now()),
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Produção concluída'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Marcar como entregue'), findsOneWidget);
    expect(find.text('Nenhum pedido em aberto'), findsNothing);
    expect(find.text('Nenhum pedido pronto'), findsNothing);
    // pronto nao conta no A fabricar: na linha do total so entram as 3 un do 'salvo'
    final linha = find.ancestor(of: find.text('Pudim tradicional'), matching: find.byType(Row)).first;
    expect(find.descendant(of: linha, matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: linha, matching: find.text('7')), findsNothing);
    // cada cartão na sua seção: #318 antes do cabeçalho, #319 depois
    final cabecalho = tester.getTopLeft(find.text('Prontos para entrega')).dy;
    expect(tester.getTopLeft(find.text('Pedido #318')).dy, lessThan(cabecalho));
    expect(tester.getTopLeft(find.text('Pedido #319')).dy, greaterThan(cabecalho));
  });

  testWidgets('detalhe mostra "—" na assinatura que falta', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final p = _ped(7, '318', 3, status: 'pronto', prontoEm: DateTime.now())
        .copyWith(assinaturaPedidoBytes: png);
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [p],
      buscarDetalhe: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente 318'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('assinatura_pedido')), findsOneWidget);
    expect(find.byKey(const ValueKey('assinatura_entrega')), findsNothing);
    final linha = find
        .ancestor(of: find.text('Assinatura da entrega'), matching: find.byType(Row))
        .first;
    expect(find.descendant(of: linha, matching: find.text('—')), findsOneWidget);
  });

  testWidgets('selo alterado depois de pronto tem prioridade sobre alterado as', (tester) async {
    final pronto = DateTime.now().subtract(const Duration(hours: 2));
    final p = _ped(1, '318', 3,
        prontoEm: pronto,
        alteradoEm: DateTime.now().subtract(const Duration(hours: 1)));
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => [p])));
    await tester.pumpAndSettle();
    expect(find.text('alterado depois de pronto'), findsOneWidget);
    expect(find.textContaining('alterado às'), findsNothing);
  });

  testWidgets('Producao concluida chama marcarPronto uma vez (com alterado_em bruto) e recarrega',
      (tester) async {
    var cargas = 0;
    final chamadas = <(int, String?)>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async {
        cargas++;
        return [_ped(7, '318', 3, alteradoEmBruto: '2026-11-23T10:00:00.123456+00:00')];
      },
      marcarPronto: (id, bruto) async => chamadas.add((id, bruto)),
    )));
    await tester.pumpAndSettle();
    expect(cargas, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Produção concluída'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar como pronto para entrega?'), findsOneWidget);
    expect(find.text(_textoFinalizar), findsNothing);
    expect(chamadas, isEmpty);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirmar'),
    ));
    await tester.pumpAndSettle();

    expect(chamadas, [(7, '2026-11-23T10:00:00.123456+00:00')]);
    expect(cargas, 2);
    expect(find.text('Pedido pronto para entrega.'), findsOneWidget);
  });

  testWidgets('erro MD001 mostra a mensagem e recarrega', (tester) async {
    var cargas = 0;
    const msg = 'O pedido mudou depois que a tela foi atualizada. Atualize e confira.';
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async {
        cargas++;
        return [_ped(7, '318', 3)];
      },
      marcarPronto: (id, bruto) async => throw RepoFailure(msg),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Produção concluída'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirmar'),
    ));
    await tester.pumpAndSettle();
    expect(find.text(msg), findsOneWidget);
    expect(cargas, 2);
  });

  testWidgets('Marcar como entregue chama finalizarManual (confirma com o texto da Fase A)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var cargas = 0;
    final finalizados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async {
        cargas++;
        return [_ped(7, '318', 3, status: 'pronto', prontoEm: DateTime.now())];
      },
      finalizar: (id) async => finalizados.add(id),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Marcar como entregue'));
    await tester.pumpAndSettle();
    expect(find.text(_textoFinalizar), findsOneWidget);
    expect(finalizados, isEmpty);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Marcar como entregue'),
    ));
    await tester.pumpAndSettle();

    expect(finalizados, [7]);
    expect(cargas, 2);
    expect(find.text('Pedido marcado como entregue.'), findsOneWidget);
  });

  testWidgets('Voltar no diálogo de entregue não chama finalizar', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final finalizados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [_ped(7, '318', 3, status: 'pronto', prontoEm: DateTime.now())],
      finalizar: (id) async => finalizados.add(id),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Marcar como entregue'));
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

  testWidgets('ação concluída durante uma carga em andamento recarrega depois', (tester) async {
    var cargas = 0;
    var fechado = false;
    final lenta = Completer<List<Pedido>>();
    await tester.pumpWidget(_app(ProducaoTab(
      intervalo: const Duration(seconds: 30),
      carregar: () {
        cargas++;
        if (cargas == 2) return lenta.future; // carga do timer, demorada
        return Future.value(fechado ? <Pedido>[] : [_ped(7, '318', 3)]);
      },
      marcarPronto: (id, _) async => fechado = true,
    )));
    await tester.pumpAndSettle();
    expect(cargas, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Produção concluída'));
    await tester.pumpAndSettle();
    // Um tick do timer começa uma carga que fica pendente...
    await tester.pump(const Duration(seconds: 31));
    expect(cargas, 2);
    // ...e a ação termina enquanto ela está em andamento.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirmar'),
    ));
    await tester.pump();
    await tester.pump();
    lenta.complete([_ped(7, '318', 3)]); // resposta velha, ainda com o pedido
    await tester.pumpAndSettle();

    expect(cargas, 3);
    expect(find.text('Nenhum pedido em aberto'), findsOneWidget);
  });

  testWidgets('mostra "Atualizado às" depois de carregar', (tester) async {
    await tester.pumpWidget(_app(ProducaoTab(carregar: () async => [_ped(1, '318', 3)])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Atualizado às'), findsOneWidget);
  });

  testWidgets('dois toques rápidos em Produção concluída chamam marcarPronto uma vez',
      (tester) async {
    final finalizados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [_ped(7, '318', 3)],
      marcarPronto: (id, _) async => finalizados.add(id),
    )));
    await tester.pumpAndSettle();
    final botao = find.widgetWithText(FilledButton, 'Produção concluída');
    await tester.tap(botao);
    await tester.tap(botao, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Confirmar'),
    ));
    await tester.pumpAndSettle();
    expect(finalizados, [7]);
  });

  testWidgets('tocar no pedido abre o detalhe (sem Apagar)', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = _ped(7, '318', 3);
    final buscados = <int>[];
    await tester.pumpWidget(_app(ProducaoTab(
      carregar: () async => [p],
      buscarDetalhe: (id) async {
        buscados.add(id);
        return (
          raw: <String, dynamic>{'id': id, 'cliente_nome': 'Cliente 318'},
          parsed: p,
        );
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Dados do cliente'), findsNothing);

    await tester.tap(find.text('Cliente 318'));
    await tester.pumpAndSettle();

    expect(buscados, [7]);
    expect(find.text('Dados do cliente'), findsOneWidget);
    expect(find.text('Cliente 318'), findsNWidgets(3),
        reason: 'cartão, título do detalhe e linha Nome');
    expect(find.byTooltip('Apagar pedido'), findsNothing,
        reason: 'pedido em aberto se cancela, não se apaga');
  });
}
