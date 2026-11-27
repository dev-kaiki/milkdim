// test/telas_entregas_test.dart
//
// Tela "Entregas do dia" e o item da tela inicial. Dados falsos, sem SQLite
// nem rede.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/entregas_page.dart';
import 'package:milkdim_app/pages/home_page.dart';

const _vendedor = <String, dynamic>{'codigo': '0002', 'nome': 'Carlos'};

Map<String, dynamic> _ped(int id, String numero, String nome, String cidade,
        {String? endereco, String? cep, String? whats, String? prontoEm, String produtos = '[]'}) =>
    {
      'id': id,
      'numero': numero,
      'status': 'pronto',
      'vendedor_codigo': '0002',
      'cliente_nome': nome,
      'cliente_cidade': cidade,
      'cliente_endereco': endereco,
      'cliente_cep': cep,
      'cliente_whatsapp': whats,
      'pronto_em': prontoEm,
      'produtos': produtos,
      'total': 120.5,
    };

final _prontos = <Map<String, dynamic>>[
  _ped(1, '101', 'Padaria Central', 'Franca',
      endereco: 'Rua Açaí, 10',
      cep: '14400-000',
      whats: '(16) 99999-1234',
      prontoEm: DateTime(2026, 11, 26, 14, 30).toUtc().toIso8601String(),
      produtos: '[{"nome":"Pote 160g","quantidade":40,"preco":3.0}]'),
  _ped(2, '102', 'Bar Sem Dados', 'Franca'),
  _ped(3, '103', 'Mercado Sul', ''),
];

Future<List<Uri>> _abrir(
  WidgetTester tester, {
  Future<List<Map<String, dynamic>>> Function(String)? carregarPedidos,
  Future<void> Function(String)? baixarPedidos,
  Future<bool> Function(Uri)? abrirLink,
  Widget Function(Map<String, dynamic>)? paginaEntrega,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  final abertos = <Uri>[];
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: EntregasPage(
      vendedor: _vendedor,
      carregarPedidos: carregarPedidos ?? (_) async => _prontos,
      baixarPedidos: baixarPedidos ?? (_) async {},
      abrirLink: abrirLink ??
          (u) async {
            abertos.add(u);
            return true;
          },
      paginaEntrega: paginaEntrega,
    ),
  ));
  await tester.pumpAndSettle();
  return abertos;
}

Finder _botao(String texto, [int i = 0]) => find
    .ancestor(of: find.text(texto), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
    .at(i);

/// Puxa a tela para baixo o bastante para o RefreshIndicator disparar (a
/// tela de teste é alta, e o gatilho é proporcional à altura).
Future<void> _puxar(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 2500));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra grupos por cidade e cartões com os textos exatos', (tester) async {
    await _abrir(tester);
    expect(find.text('Franca'), findsOneWidget);
    expect(find.text('Sem cidade'), findsOneWidget);
    expect(find.text('Pedido nº 101'), findsOneWidget);
    expect(find.text('Padaria Central'), findsOneWidget);
    expect(find.text('Rua Açaí, 10 · CEP 14400-000'), findsOneWidget);
    expect(find.text('Pronto desde 26/11 14:30'), findsOneWidget);
    expect(find.textContaining('Pote 160g ×40'), findsOneWidget);
    // Só o pedido com pronto_em mostra a linha.
    expect(find.textContaining('Pronto desde'), findsOneWidget);
    expect(find.text('Registrar entrega'), findsNWidgets(3));
  });

  testWidgets('lista vazia mostra a mensagem', (tester) async {
    await _abrir(tester, carregarPedidos: (_) async => []);
    expect(find.text('Nenhum pedido pronto para entregar.'), findsOneWidget);
  });

  testWidgets('falha ao baixar ainda mostra a lista local, sem aviso', (tester) async {
    await _abrir(tester, baixarPedidos: (_) async => throw Exception('sem rede'));
    expect(find.text('Pedido nº 101'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('baixar ao abrir recarrega a lista', (tester) async {
    var chamadas = 0;
    var baixou = false;
    await _abrir(
      tester,
      baixarPedidos: (_) async => baixou = true,
      carregarPedidos: (_) async {
        chamadas++;
        return _prontos;
      },
    );
    expect(baixou, isTrue);
    expect(chamadas, 2);
  });

  testWidgets('Mapa e Avisar chamam abrirLink com os links certos', (tester) async {
    final abertos = await _abrir(tester);
    await tester.tap(_botao('Mapa', 1));
    await tester.pumpAndSettle();
    expect(abertos.single.host, 'www.google.com');
    expect(abertos.single.toString(), contains('Rua%20A%C3%A7a%C3%AD%2C%2010'));
    abertos.clear();
    await tester.tap(_botao('Avisar', 1));
    await tester.pumpAndSettle();
    expect(abertos.single.host, 'wa.me');
    expect(abertos.single.path, '/5516999991234');
    expect(abertos.single.queryParameters['text'], contains('pedido nº 101'));
    expect(abertos.single.queryParameters['text'], contains('Carlos'));
  });

  testWidgets('sem endereço ou telefone, Mapa e Avisar ficam desligados', (tester) async {
    await _abrir(tester);
    // Primeiro cartão (Bar Sem Dados, ordem alfabética): sem endereço nem telefone.
    expect(tester.widget<ButtonStyleButton>(_botao('Mapa', 0)).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(_botao('Avisar', 0)).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(_botao('Mapa', 1)).onPressed, isNotNull);
  });

  testWidgets('Mapa que não abre mostra o aviso', (tester) async {
    await _abrir(tester, abrirLink: (_) async => false);
    await tester.tap(_botao('Mapa', 1));
    await tester.pump();
    expect(find.text('Não foi possível abrir o mapa.'), findsOneWidget);
  });

  testWidgets('Avisar que lança erro mostra o aviso', (tester) async {
    await _abrir(tester, abrirLink: (_) async => throw Exception('sem app'));
    await tester.tap(_botao('Avisar', 1));
    await tester.pump();
    expect(find.text('Não foi possível abrir o WhatsApp.'), findsOneWidget);
  });

  testWidgets('voltar de Registrar entrega recarrega a lista', (tester) async {
    var entregue = false;
    var chamadas = 0;
    await _abrir(
      tester,
      carregarPedidos: (_) async {
        chamadas++;
        return entregue ? [_prontos[0], _prontos[2]] : _prontos;
      },
      paginaEntrega: (p) => Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () {
              entregue = true;
              Navigator.pop(ctx, p);
            },
            child: const Text('voltar'),
          ),
        ),
      ),
    );
    final antes = chamadas;
    expect(find.text('Pedido nº 102'), findsOneWidget);
    await tester.tap(_botao('Registrar entrega')); // primeiro cartão: pedido 102
    await tester.pumpAndSettle();
    await tester.tap(find.text('voltar'));
    await tester.pumpAndSettle();
    expect(chamadas, greaterThan(antes));
    expect(find.text('Pedido nº 102'), findsNothing);
    expect(find.text('Pedido nº 101'), findsOneWidget);
  });

  testWidgets('puxar para atualizar baixa de novo', (tester) async {
    var baixou = 0;
    await _abrir(tester, baixarPedidos: (_) async => baixou++);
    expect(baixou, 1);
    await _puxar(tester);
    await tester.pumpAndSettle();
    expect(baixou, 2);
  });

  testWidgets('puxar para atualizar funciona também com a lista vazia', (tester) async {
    var baixou = 0;
    await _abrir(tester,
        carregarPedidos: (_) async => [], baixarPedidos: (_) async => baixou++);
    await _puxar(tester);
    await tester.pumpAndSettle();
    expect(baixou, 2);
  });

  testWidgets('erro ao recarregar não apaga a lista na tela', (tester) async {
    var chamadas = 0;
    await _abrir(
      tester,
      carregarPedidos: (_) async {
        chamadas++;
        if (chamadas > 1) throw Exception('banco ocupado');
        return _prontos;
      },
    );
    // A segunda leitura (depois do download) falhou: a primeira segue na tela.
    expect(chamadas, 2);
    expect(find.text('Pedido nº 101'), findsOneWidget);
    expect(find.text('Não foi possível carregar as entregas.'), findsNothing);
  });

  testWidgets('erro na primeira leitura mostra a mensagem', (tester) async {
    await _abrir(tester, carregarPedidos: (_) async => throw Exception('x'));
    expect(find.text('Não foi possível carregar as entregas.'), findsOneWidget);
  });

  testWidgets('toque duplo em Registrar entrega abre uma tela só', (tester) async {
    var abertas = 0;
    await _abrir(
      tester,
      paginaEntrega: (p) {
        abertas++;
        return const Scaffold(body: Text('editor'));
      },
    );
    final botao = _botao('Registrar entrega');
    tester.widget<ButtonStyleButton>(botao).onPressed!();
    tester.widget<ButtonStyleButton>(botao).onPressed!();
    await tester.pumpAndSettle();
    expect(abertas, 1);
    expect(find.text('editor'), findsOneWidget);
  });

  testWidgets('tela inicial: item Entregas do dia mostra a contagem', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(vendedor: _vendedor, pendentesParaCaptura: 0, prontosParaCaptura: 4),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Entregas do dia'), findsOneWidget);
    expect(find.text('4 prontos para entregar'), findsOneWidget);
  });

  testWidgets('tela inicial: sem contagem mostra o texto neutro', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(vendedor: _vendedor, pendentesParaCaptura: 0),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Entregas do dia'), findsOneWidget);
    expect(find.text('Pedidos prontos para entregar'), findsOneWidget);
  });

  test('subtituloEntregas', () {
    expect(subtituloEntregas(null), 'Pedidos prontos para entregar');
    expect(subtituloEntregas(0), '0 prontos para entregar');
    expect(subtituloEntregas(1), '1 pronto para entregar');
    expect(subtituloEntregas(3), '3 prontos para entregar');
  });
}
