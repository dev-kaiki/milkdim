// test/meus_pedidos_atualizar_test.dart
//
// Meus pedidos traz do servidor o que a fábrica mudou (Produção concluída,
// Finalizar manual, Cancelar): ao abrir a tela e no Recarregar. Antes, os dois
// só reliam o SQLite e o pedido ficava "Em aberto" até a sincronização
// completa. Dados falsos; o "servidor" é uma função de teste.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/db.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';

Map<String, dynamic> _remoto(String status) => {
      'id': 42,
      'numero': '70',
      'status': status,
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor Teste',
      'datahora': '2026-11-23T09:00:00+00:00',
      'enviado_em': '2026-11-23T09:00:01+00:00',
      'total': 10.0,
      'cliente_nome': 'Cliente Teste',
      'produtos': [
        {'nome': 'Pudim', 'quantidade': 1, 'preco': 10.0, 'subtotal': 10.0},
      ],
      if (status == 'pronto') ...{
        'pronto_em': '2026-11-23T09:30:00+00:00',
        'pronto_por': '0001',
      },
      if (status == 'finalizado') ...{
        'finalizado_em': '2026-11-23T10:00:00+00:00',
        'finalizado_por': '0001',
        'finalizado_manual': true,
      },
    };

/// Deixa as operações reais do SQLite (ffi) terminarem e redesenha.
Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

Future<void> _abrir(WidgetTester tester, Future<void> Function(String) baixar) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: PedidosPage(vendedorCodigo: '0003', baixarPedidos: baixar),
  ));
  await _esperar(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Pasta só deste arquivo: os testes rodam em paralelo.
    final dir = await Directory.systemTemp.createTemp('meus_pedidos_atualizar_test');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await fecharDbParaTeste();
    await databaseFactory
        .deleteDatabase(join(await databaseFactory.getDatabasesPath(), 'milkdim.db'));
    // No aparelho: o pedido enviado, ainda em aberto.
    await aplicarPedidosRemotos([_remoto('salvo')]);
  });

  tearDown(fecharDbParaTeste);

  testWidgets('ao abrir, o pedido finalizado no Controle sai de Em aberto', (tester) async {
    final chamados = <String>[];
    await _abrir(tester, (codigo) async {
      chamados.add(codigo);
      await aplicarPedidosRemotos([_remoto('finalizado')]);
    });

    expect(chamados, ['0003']);
    expect(find.text('Em aberto (0)'), findsOneWidget);
    expect(find.text('Entregues (1)'), findsOneWidget);
  });

  testWidgets('Recarregar busca no servidor de novo (Produção concluída vira Pronto)',
      (tester) async {
    var vezes = 0;
    await _abrir(tester, (_) async {
      vezes++;
      if (vezes == 2) await aplicarPedidosRemotos([_remoto('pronto')]);
    });
    expect(find.text('Pronto'), findsNothing);

    await tester.tap(find.byIcon(Icons.refresh));
    await _esperar(tester);

    expect(vezes, 2);
    expect(find.text('Em aberto (1)'), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);
  });

  testWidgets('sem internet: ao abrir fica quieto; no Recarregar avisa e mostra o do aparelho',
      (tester) async {
    await _abrir(tester, (_) async => throw Exception('sem rede'));
    expect(find.text(kMsgSemServidorMeusPedidos), findsNothing);
    expect(find.text('Em aberto (1)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await _esperar(tester);

    expect(find.text(kMsgSemServidorMeusPedidos), findsOneWidget);
    expect(find.text('Em aberto (1)'), findsOneWidget);
  });
}
