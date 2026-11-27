// test/telas_clientes_sumidos_test.dart
//
// Tela "Clientes sumidos", item da tela inicial e pedido com cliente escolhido.
// Dados falsos, relógio fixo em 27/11/2026, sem SQLite nem rede.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/clientes_sumidos_page.dart';
import 'package:milkdim_app/pages/home_page.dart';
import 'package:milkdim_app/pages/pedido_page.dart';
import 'package:milkdim_app/utils/produto.dart';

const _vendedor = <String, dynamic>{'codigo': '0002', 'nome': 'Carlos'};

final _agora = DateTime(2026, 11, 27, 12);

const _clientes = <Map<String, dynamic>>[
  {'id': 1, 'nome': 'Padaria Central', 'whatsapp': '(16) 99999-1234', 'telefone': '(16) 3333-4444'},
  {'id': 2, 'nome': 'Mercado Sul', 'telefone': '(16) 3333-5555'},
  {'id': 3, 'nome': 'Bar Sem Fone'},
];

Map<String, dynamic> _ped(int id, int cliente, String data) => {
      'id': id,
      'vendedor_codigo': '0002',
      'status': 'enviado',
      'cliente_id': cliente,
      'datahora': data,
    };

// Padaria: 20/10 (38 dias, 2 pedidos). Mercado: 13/10 (45 dias, 1 pedido).
// Bar: 01/09 (87 dias, 1 pedido).
final _pedidos = <Map<String, dynamic>>[
  _ped(1, 1, '2026-10-20T15:00:00'),
  _ped(2, 1, '2026-10-05T15:00:00'),
  _ped(3, 2, '2026-10-13T15:00:00'),
  _ped(4, 3, '2026-09-01T15:00:00'),
];

Future<List<Uri>> _abrir(
  WidgetTester tester, {
  Widget Function(Map<String, dynamic>, int)? paginaPedido,
  Future<bool> Function(Uri)? abrirLink,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  final abertos = <Uri>[];
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: ClientesSumidosPage(
      vendedor: _vendedor,
      relogio: () => _agora,
      carregarClientes: () async => _clientes,
      carregarPedidos: (_) async => _pedidos,
      abrirLink: abrirLink ??
          (u) async {
            abertos.add(u);
            return true;
          },
      paginaPedido: paginaPedido,
    ),
  ));
  await tester.pumpAndSettle();
  return abertos;
}

/// Botão (qualquer ButtonStyleButton) com o [texto], na posição [i] da lista.
Finder _botao(String texto, [int i = 0]) => find
    .ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
    .at(i);

void main() {
  testWidgets('mostra os sumidos com data, dias e pedidos', (tester) async {
    await _abrir(tester);
    expect(find.text('Padaria Central'), findsOneWidget);
    expect(find.text('Última compra 20/10 · há 38 dias'), findsOneWidget);
    expect(find.text('2 pedidos'), findsOneWidget);
    expect(find.text('Última compra 13/10 · há 45 dias'), findsOneWidget);
    expect(find.text('1 pedido'), findsNWidgets(2)); // Mercado e Bar
    expect(find.text('Última compra 01/09 · há 87 dias'), findsOneWidget);
  });

  testWidgets('trocar para 60 dias esconde quem tem 45', (tester) async {
    await _abrir(tester);
    expect(find.text('Mercado Sul'), findsOneWidget);
    await tester.tap(find.text('60 dias'));
    await tester.pumpAndSettle();
    expect(find.text('Mercado Sul'), findsNothing);
    expect(find.text('Padaria Central'), findsNothing);
    expect(find.text('Bar Sem Fone'), findsOneWidget);
  });

  testWidgets('lista vazia mostra a mensagem', (tester) async {
    await _abrir(tester);
    await tester.tap(find.text('90 dias'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum cliente sumido há 90 dias ou mais.'), findsOneWidget);
  });

  testWidgets('WhatsApp chama abrirLink com wa.me e o nome do vendedor', (tester) async {
    final abertos = await _abrir(tester);
    await tester.tap(_botao('WhatsApp'));
    await tester.pumpAndSettle();
    expect(abertos, hasLength(1));
    expect(abertos.single.host, 'wa.me');
    expect(abertos.single.path, '/5516999991234');
    expect(abertos.single.queryParameters['text'], contains('Carlos'));
  });

  testWidgets('Ligar chama abrirLink com tel:', (tester) async {
    final abertos = await _abrir(tester);
    await tester.tap(_botao('Ligar'));
    await tester.pumpAndSettle();
    expect(abertos.single.toString(), 'tel:551633334444');
  });

  testWidgets('sem telefone válido, WhatsApp e Ligar ficam desligados', (tester) async {
    await _abrir(tester);
    // Terceira linha (Bar Sem Fone): sem telefone nem whatsapp.
    expect(tester.widget<ButtonStyleButton>(_botao('WhatsApp', 2)).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(_botao('Ligar', 2)).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(_botao('WhatsApp', 0)).onPressed, isNotNull);
  });

  testWidgets('WhatsApp que não abre mostra o aviso', (tester) async {
    await _abrir(tester, abrirLink: (_) async => false);
    await tester.tap(_botao('WhatsApp'));
    await tester.pump();
    expect(find.text('Não foi possível abrir o WhatsApp.'), findsOneWidget);
  });

  testWidgets('Ligar que lança erro mostra o aviso', (tester) async {
    await _abrir(tester, abrirLink: (_) async => throw Exception('sem app'));
    await tester.tap(_botao('Ligar'));
    await tester.pump();
    expect(find.text('Não foi possível abrir o discador.'), findsOneWidget);
  });

  testWidgets('Novo pedido abre PedidoPage com clienteInicialId', (tester) async {
    int? recebido;
    await _abrir(tester, paginaPedido: (v, id) {
      recebido = id;
      return const Scaffold(body: Text('pagina do pedido'));
    });
    await tester.tap(_botao('Novo pedido'));
    await tester.pumpAndSettle();
    expect(find.text('pagina do pedido'), findsOneWidget);
    expect(recebido, 1);
  });

  testWidgets('PedidoPage com clienteInicialId preenche o Nome', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: PedidoPage(
        vendedor: _vendedor,
        clienteInicialId: 2,
        dadosParaCaptura: (
          clientes: const [
            {'id': 1, 'nome': 'Padaria Central'},
            {'id': 2, 'nome': 'Mercado Sul'},
          ],
          produtos: const [Produto(id: 1, nome: 'Pote 160g', preco: 3.5)],
        ),
        carregarPedidosDoCliente: (_) async => const [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(TextField), matching: find.text('Mercado Sul')),
        findsOneWidget);
    expect(find.descendant(of: find.byType(TextField), matching: find.text('Padaria Central')),
        findsNothing);
  });

  testWidgets('tela inicial: item Clientes sumidos mostra a contagem', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(vendedor: _vendedor, pendentesParaCaptura: 0, sumidosParaCaptura: 3),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Clientes sumidos'), findsOneWidget);
    expect(find.text('3 sem comprar há 30 dias ou mais'), findsOneWidget);
  });

  test('subtituloSumidos', () {
    expect(subtituloSumidos(0), '0 sem comprar há 30 dias ou mais');
    expect(subtituloSumidos(12), '12 sem comprar há 30 dias ou mais');
  });
}
