// test/telas_minhas_vendas_test.dart
//
// Tela "Minhas vendas" e o item da tela inicial. Dados falsos, sem SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/home_page.dart';
import 'package:milkdim_app/pages/minhas_vendas_page.dart';
import 'package:milkdim_app/utils/moeda.dart';

const _vendedor = <String, dynamic>{'codigo': '0002', 'nome': 'Carlos'};

Map<String, dynamic> _ped(String status, DateTime quando, double total,
        {int cliente = 1, String nome = 'Padaria Central', String produto = 'Pote 160g'}) =>
    {
      'status': status,
      'vendedor_codigo': '0002',
      'finalizado_em': quando.toUtc().toIso8601String(),
      'total': total,
      'cliente_id': cliente,
      'cliente_nome': nome,
      'produtos': [
        {'nome': produto, 'quantidade': 10, 'preco': total / 10, 'subtotal': total},
      ],
    };

// "Agora" nos testes: 15/11/2026.
DateTime _agora() => DateTime(2026, 11, 15, 10);

final _pedidos = <Map<String, dynamic>>[
  // novembro: 300 em 2 pedidos
  _ped('finalizado', DateTime(2026, 11, 3, 10), 100),
  _ped('finalizado', DateTime(2026, 11, 9, 10), 200,
      cliente: 2, nome: 'Mercado Sul', produto: 'Copo 200g'),
  // outubro: 200 em 1 pedido
  _ped('finalizado', DateTime(2026, 10, 5, 10), 200),
  // a entregar
  _ped('pronto', DateTime(2026, 11, 14, 10), 50),
  _ped('salvo', DateTime(2026, 11, 14, 11), 25.5),
];

Future<void> _abrir(WidgetTester tester, List<Map<String, dynamic>> pedidos,
    {DateTime Function()? relogio}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: MinhasVendasPage(
      vendedor: _vendedor,
      relogio: relogio ?? _agora,
      carregarPedidos: (_) async => pedidos,
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _anterior => find.byTooltip('Mês anterior');
Finder get _proximo => find.byTooltip('Próximo mês');

void main() {
  testWidgets('mostra mês, três números, comparações e seções', (tester) async {
    await _abrir(tester, _pedidos);
    expect(find.text('novembro de 2026'), findsOneWidget);
    expect(find.text('Vendido'), findsOneWidget);
    expect(find.text('Pedidos entregues'), findsOneWidget);
    expect(find.text('Ticket médio'), findsOneWidget);
    expect(find.text(formatarReais(300)), findsWidgets); // vendido
    expect(find.text('2'), findsOneWidget);
    expect(find.text(formatarReais(150)), findsOneWidget); // ticket
    expect(find.text('▲ 50%'), findsOneWidget); // vendido 300 x 200
    expect(find.text('▲ 100%'), findsOneWidget); // pedidos 2 x 1
    expect(find.text('▼ 25%'), findsOneWidget); // ticket 150 x 200
    expect(find.text('A entregar'), findsOneWidget);
    expect(find.text('${formatarReais(75.5)} · 2 pedidos'), findsOneWidget);
    expect(find.text('Por produto'), findsOneWidget);
    expect(find.text('Copo 200g'), findsOneWidget);
    expect(find.text('Melhores clientes'), findsOneWidget);
    expect(find.text('Mercado Sul'), findsOneWidget);
  });

  testWidgets('I1: entregues sem internet aparecem só no mês atual', (tester) async {
    final off = {..._ped('finalizado', DateTime(2026, 11, 14), 40), 'finalizado_em': null};
    await _abrir(tester, [..._pedidos, off]);
    expect(
        find.text('Entregues sem internet: 1 pedido · ${formatarReais(40)}'
            ' — entram nas vendas quando forem enviados'),
        findsOneWidget);
    await tester.tap(_anterior);
    await tester.pumpAndSettle();
    expect(find.textContaining('Entregues sem internet'), findsNothing);
  });

  testWidgets('I1: plural e oculto com zero', (tester) async {
    final a = {..._ped('finalizado', DateTime(2026, 11, 14), 40), 'finalizado_em': null};
    await _abrir(tester, [a, a]);
    expect(find.textContaining('2 pedidos · '), findsWidgets);
    expect(find.textContaining('Entregues sem internet: 2 pedidos'), findsOneWidget);
  });

  testWidgets('I1: sem pedido offline a linha não aparece', (tester) async {
    await _abrir(tester, _pedidos);
    expect(find.textContaining('Entregues sem internet'), findsNothing);
  });

  testWidgets('I2: mês atual compara só até o mesmo dia e hora do anterior', (tester) async {
    // Em 15/11 10h: 14/10 conta na base, 20/10 não.
    await _abrir(tester, [
      _ped('finalizado', DateTime(2026, 11, 3, 10), 100),
      _ped('finalizado', DateTime(2026, 10, 14, 10), 50),
      _ped('finalizado', DateTime(2026, 10, 20, 10), 500),
    ]);
    expect(find.text('▲ 100%'), findsWidgets); // 100 x 50 (e não x 550)
    await tester.tap(_anterior);
    await tester.pumpAndSettle();
    // Outubro encerrado: 550 contra setembro zero, sem comparação.
    expect(find.text('outubro de 2026'), findsOneWidget);
    expect(find.textContaining('▲'), findsNothing);
  });

  testWidgets('"‹" vai ao mês anterior, onde "A entregar" some', (tester) async {
    await _abrir(tester, _pedidos);
    await tester.tap(_anterior);
    await tester.pumpAndSettle();
    expect(find.text('outubro de 2026'), findsOneWidget);
    expect(find.text('A entregar'), findsNothing);
    expect(find.text('Por produto'), findsOneWidget);
    expect(find.text(formatarReais(200)), findsWidgets);
    // setembro não teve venda: sem comparação (anterior zero).
    expect(find.text('▲ 100%'), findsNothing);
  });

  testWidgets('"›" fica desligado no mês atual e volta a ligar ao recuar', (tester) async {
    await _abrir(tester, _pedidos);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
    await tester.tap(_anterior);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNotNull);
    await tester.tap(_proximo);
    await tester.pumpAndSettle();
    expect(find.text('novembro de 2026'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
  });

  testWidgets('virada de ano: janeiro volta para dezembro', (tester) async {
    await _abrir(tester, const [], relogio: () => DateTime(2027, 1, 5));
    await tester.tap(_anterior);
    await tester.pumpAndSettle();
    expect(find.text('dezembro de 2026'), findsOneWidget);
  });

  testWidgets('mês sem venda mostra a mensagem e ticket "—"', (tester) async {
    await _abrir(tester, const []);
    expect(find.text('Nenhuma venda entregue em novembro.'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Por produto'), findsNothing);
    expect(find.text('Melhores clientes'), findsNothing);
  });

  testWidgets('erro ao carregar mostra aviso', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: MinhasVendasPage(
        vendedor: _vendedor,
        relogio: _agora,
        carregarPedidos: (_) async => throw Exception('falha'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar as vendas.'), findsOneWidget);
  });

  testWidgets('tela inicial: item Minhas vendas depois de Clientes sumidos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(
          vendedor: _vendedor, pendentesParaCaptura: 0, vendasParaCaptura: 3450),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Minhas vendas'), findsOneWidget);
    expect(find.text('${formatarReais(3450)} em ${nomeDoMes(DateTime.now().month)}'),
        findsOneWidget);
    final sumidos = tester.getTopLeft(find.text('Clientes sumidos')).dy;
    expect(tester.getTopLeft(find.text('Minhas vendas')).dy, greaterThan(sumidos));
  });

  testWidgets('tela inicial: sem dado o subtítulo é neutro', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(vendedor: _vendedor, pendentesParaCaptura: 0),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Minhas vendas'), findsOneWidget);
    expect(find.text('Quanto você vendeu no mês'), findsOneWidget);
  });

  test('nomeDoMes e subtituloVendas', () {
    expect(nomeDoMes(1), 'janeiro');
    expect(nomeDoMes(12), 'dezembro');
    expect(subtituloVendas(null, 11), 'Quanto você vendeu no mês');
    expect(subtituloVendas(3450, 11), '${formatarReais(3450)} em novembro');
  });
}
