// test/telas_repetir_pedido_test.dart
//
// "Repetir pedido": o quadro "Partir de um pedido anterior" na tela de novo
// pedido. Dados falsos, sem SQLite nem rede.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/pedido_page.dart';
import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/db.dart' show kErroApagadoNoControle, kLimparAssinaturaPedido;
import 'package:milkdim_app/utils/moeda.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';
import 'package:milkdim_app/utils/produto.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/supabase_helper.dart';
import 'package:milkdim_app/widgets/pedido_ui.dart';
import 'package:milkdim_app/widgets/pedidos_anteriores.dart';

const _vendedor = <String, dynamic>{'codigo': '0003', 'nome': 'Vendedor Teste'};

const _catalogo = <Produto>[
  Produto(id: 1, nome: 'Pote 160g', preco: 3.5),
  Produto(id: 2, nome: 'Copo', preco: 2.0),
  Produto(id: 3, nome: 'Pudim', preco: 4.0),
];

const _clientes = <Map<String, dynamic>>[
  {'id': 7, 'nome': 'Padaria Central'},
  {'id': 8, 'nome': 'Mercado Sul'},
];

Map<String, dynamic> _pedido(int id, String itens, {String data = '2026-11-20T12:00:00+00:00'}) => {
      'id': id,
      'numero': '$id',
      'status': 'enviado',
      'datahora': data,
      'total': 180.0,
      'produtos': itens,
    };

const _itensA = '[{"nome":"Pote 160g","quantidade":40,"preco":3.5,"subtotal":140},'
    '{"nome":"Copo","quantidade":20,"preco":2.0,"subtotal":40}]';

/// Abre a tela de novo pedido com os pedidos que o falso devolve por cliente.
Future<void> _abrir(
  WidgetTester tester,
  Map<int, List<Map<String, dynamic>>> porCliente, {
  Future<Uint8List?> Function(TipoAssinatura, {String? aviso})? pedirAssinatura,
  Future<ResultadoGravacao> Function(Map<String, dynamic>, {required bool novo})? gravar,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => PedidoPage(
                  vendedor: _vendedor,
                  dadosParaCaptura: (clientes: _clientes, produtos: _catalogo),
                  carregarPedidosDoCliente: (id) async => porCliente[id] ?? const [],
                  pedirAssinatura: pedirAssinatura,
                  gravar: gravar,
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _escolherCliente(WidgetTester tester, String nome) async {
  await tester.tap(find.byTooltip('Buscar cliente'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(nome)));
  await tester.pumpAndSettle();
}

Finder _campoQtd(String produto) => find.descendant(
      of: find.byWidgetPredicate((w) => w is ProdutoQtdTile && w.nome == produto),
      matching: find.byType(TextField),
    );

String _qtd(WidgetTester tester, String produto) =>
    tester.widget<TextField>(_campoQtd(produto)).controller!.text;

Future<void> _usar(WidgetTester tester, {int linha = 0}) async {
  final botao = find.widgetWithText(OutlinedButton, 'Usar').at(linha);
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// Abre o resumo e toca [botao] (as abas do resumo ficam fora da tela).
Future<void> _tocarResumo(WidgetTester tester, String botao, {bool assentar = true}) async {
  await tester.tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(botao));
  await tester.pumpAndSettle();
  await tester.tap(find.text(botao));
  if (assentar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

const _pergunta = 'Trocar as quantidades da tela pelas deste pedido?';

void main() {
  testWidgets('quadro aparece depois de escolher o cliente', (tester) async {
    await _abrir(tester, {
      7: [_pedido(1, _itensA), _pedido(2, _itensA, data: '2026-11-10T12:00:00+00:00')],
    });
    expect(find.text('Partir de um pedido anterior'), findsNothing);

    await _escolherCliente(tester, 'Padaria Central');

    expect(find.text('Partir de um pedido anterior'), findsOneWidget);
    expect(find.text('Usar'), findsNWidgets(2));
    expect(find.text('20/11  ·  ${formatarReais(180)}'), findsOneWidget);
    expect(find.text('10/11  ·  ${formatarReais(180)}'), findsOneWidget);
    expect(find.text('Pote 160g ×40, Copo ×20'), findsNWidgets(2));
  });

  testWidgets('cliente sem pedidos não mostra o quadro', (tester) async {
    await _abrir(tester, {});
    await _escolherCliente(tester, 'Padaria Central');
    expect(find.text('Partir de um pedido anterior'), findsNothing);
  });

  testWidgets('Usar com a tela vazia preenche sem perguntar', (tester) async {
    await _abrir(tester, {7: [_pedido(1, _itensA)]});
    await _escolherCliente(tester, 'Padaria Central');

    await _usar(tester);

    expect(find.text(_pergunta), findsNothing);
    expect(_qtd(tester, 'Pote 160g'), '40');
    expect(_qtd(tester, 'Copo'), '20');
    expect(_qtd(tester, 'Pudim'), '');
  });

  testWidgets('Usar com quantidades na tela pergunta antes', (tester) async {
    await _abrir(tester, {7: [_pedido(1, _itensA)]});
    await _escolherCliente(tester, 'Padaria Central');
    await tester.enterText(_campoQtd('Pudim'), '5');
    await tester.pumpAndSettle();

    // Cancelar: mantém o que foi digitado.
    await _usar(tester);
    expect(find.text(_pergunta), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(_qtd(tester, 'Pudim'), '5');
    expect(_qtd(tester, 'Pote 160g'), '');

    // Trocar: aplica as do pedido e zera o que não está nele.
    await _usar(tester);
    await tester.tap(find.text('Trocar'));
    await tester.pumpAndSettle();
    expect(_qtd(tester, 'Pote 160g'), '40');
    expect(_qtd(tester, 'Copo'), '20');
    expect(_qtd(tester, 'Pudim'), '');
  });

  testWidgets('produto que sumiu mostra o aviso', (tester) async {
    await _abrir(tester, {
      7: [
        _pedido(1,
            '[{"nome":"Pote 160g","quantidade":40},{"nome":"Geladinho","quantidade":6}]'),
      ],
    });
    await _escolherCliente(tester, 'Padaria Central');

    await _usar(tester);

    expect(_qtd(tester, 'Pote 160g'), '40');
    expect(find.text('Ficaram de fora (não estão mais à venda): Geladinho'), findsOneWidget);
  });

  testWidgets('trocar de cliente atualiza o quadro', (tester) async {
    await _abrir(tester, {
      7: [_pedido(1, _itensA)],
      8: [_pedido(2, '[{"nome":"Pudim","quantidade":9}]')],
    });
    await _escolherCliente(tester, 'Padaria Central');
    expect(find.text('Pote 160g ×40, Copo ×20'), findsOneWidget);

    await _escolherCliente(tester, 'Mercado Sul');

    expect(find.text('Usar'), findsOneWidget);
    expect(find.text('Pudim ×9'), findsOneWidget);
    expect(find.text('Pote 160g ×40, Copo ×20'), findsNothing);
  });

  testWidgets('Usar fica desligado enquanto o pedido está sendo gravado', (tester) async {
    final liberar = Completer<ResultadoGravacao>();
    await _abrir(
      tester,
      {7: [_pedido(1, _itensA)]},
      pedirAssinatura: (tipo, {aviso}) async => _png,
      gravar: (pedido, {required novo}) => liberar.future,
    );
    await _escolherCliente(tester, 'Padaria Central');
    await tester.enterText(_campoQtd('Pudim'), '5');
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Usar')).onPressed,
        isNotNull);

    await _tocarResumo(tester, 'Enviar pedido', assentar: false);

    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Usar')).onPressed,
        isNull,
        reason: 'gravando: "Usar" não pode mexer na tela');
    liberar.complete(ResultadoGravacao.enviado);
    await tester.pumpAndSettle();
  });

  testWidgets('assinou, usou outro pedido (Trocar) e Salvar rascunho: sem assinatura velha',
      (tester) async {
    final pedidos = <(TipoAssinatura, String?)>[];
    final gravados = <Map<String, dynamic>>[];
    Uint8List? resposta = _png;
    await _abrir(
      tester,
      {7: [_pedido(1, _itensA)]},
      pedirAssinatura: (tipo, {aviso}) async {
        pedidos.add((tipo, aviso));
        return resposta;
      },
      gravar: (pedido, {required novo}) async {
        gravados.add(Map<String, dynamic>.from(pedido));
        return ResultadoGravacao.enviado;
      },
    );
    await _escolherCliente(tester, 'Padaria Central');
    await tester.enterText(_campoQtd('Pudim'), '5');
    await tester.pumpAndSettle();

    // O cliente assina o que está na tela (Pudim ×5) e fecha o resumo.
    await tester.tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Assinar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assinar'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    expect(pedidos, [(TipoAssinatura.pedido, null)]);

    // O vendedor troca os itens pelos de um pedido anterior.
    await _usar(tester);
    await tester.tap(find.text('Trocar'));
    await tester.pumpAndSettle();
    expect(_qtd(tester, 'Pote 160g'), '40');

    // Rascunho: a assinatura antiga não cobre os itens novos, não vai junto.
    await _tocarResumo(tester, 'Salvar rascunho');
    expect(gravados.single.containsKey('assinatura_pedido'), isFalse);
    expect(gravados.single[kLimparAssinaturaPedido], isTrue);
  });

  testWidgets('assinou, usou outro pedido e Enviar pede a assinatura de novo', (tester) async {
    final pedidos = <(TipoAssinatura, String?)>[];
    final gravados = <Map<String, dynamic>>[];
    Uint8List? resposta = _png;
    await _abrir(
      tester,
      {7: [_pedido(1, _itensA)]},
      pedirAssinatura: (tipo, {aviso}) async {
        pedidos.add((tipo, aviso));
        return resposta;
      },
      gravar: (pedido, {required novo}) async {
        gravados.add(Map<String, dynamic>.from(pedido));
        return ResultadoGravacao.enviado;
      },
    );
    await _escolherCliente(tester, 'Padaria Central');
    await tester.enterText(_campoQtd('Pudim'), '5');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BarraResumo), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Assinar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assinar'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();

    await _usar(tester);
    await tester.tap(find.text('Trocar'));
    await tester.pumpAndSettle();

    resposta = null; // o cliente não assina de novo
    await _tocarResumo(tester, 'Enviar pedido');

    expect(pedidos.last, (TipoAssinatura.pedido, kAvisoAssinarPedidoDeNovo));
    expect(gravados, isEmpty, reason: 'a assinatura antiga não cobre os itens novos');
  });

  testWidgets('QuadroPedidosAnteriores vazio não ocupa espaço', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(body: QuadroPedidosAnteriores(pedidos: const [], onUsar: (_) {})),
    ));
    expect(find.text('Partir de um pedido anterior'), findsNothing);
  });

  mainLista();
}

/// Pedido para a lista (Meus pedidos).
Map<String, dynamic> _naLista(int id, String status,
        {int? clienteId = 7, String? erroEnvio}) =>
    {
      'id': id,
      'numero': '$id',
      'status': status,
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor Teste',
      'datahora': '2026-11-20T15:00:00+00:00',
      'total': 180.0,
      'cliente_id': clienteId,
      'cliente_nome': 'Padaria Central',
      'produtos': _itensA,
      if (erroEnvio != null) 'erro_envio': erroEnvio,
    };

Future<void> _abrirLista(
  WidgetTester tester,
  List<Map<String, dynamic>> pedidos, {
  List<Map<String, dynamic>> clientesDoAparelho = _clientes,
  int aba = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: PedidosPage(
      vendedorCodigo: '0003',
      vendedor: _vendedor,
      pedidosParaCaptura: pedidos,
      abaInicialParaCaptura: aba,
      listarClientesDoAparelho: () async => clientesDoAparelho,
    ),
  ));
  await tester.pumpAndSettle();
}

void mainLista() {
  testWidgets('Repetir aparece em pedido com cliente', (tester) async {
    await _abrirLista(tester, [
      _naLista(1, 'salvo'),
      _naLista(2, 'salvo', clienteId: null),
      _naLista(3, 'salvo', erroEnvio: kErroApagadoNoControle),
      _naLista(4, 'finalizado'),
    ]);
    // Em aberto: só o pedido 1 tem cliente e não está apagado.
    expect(find.text('Repetir'), findsOneWidget);

    await tester.tap(find.textContaining('Entregues'));
    await tester.pumpAndSettle();
    expect(find.text('Repetir'), findsOneWidget);
  });

  testWidgets('Repetir com cliente apagado avisa e não abre', (tester) async {
    await _abrirLista(tester, [_naLista(1, 'salvo')], clientesDoAparelho: const []);
    await tester.tap(find.text('Repetir'));
    await tester.pumpAndSettle();

    expect(find.text('Este cliente não está mais cadastrado'), findsOneWidget);
    expect(find.byType(PedidoPage), findsNothing);
    expect(find.byType(PedidosPage), findsOneWidget);
  });

  testWidgets('PedidoPage com partirDe abre preenchida', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: PedidoPage(
        vendedor: _vendedor,
        dadosParaCaptura: (clientes: _clientes, produtos: _catalogo),
        carregarPedidosDoCliente: (id) async => const [],
        partirDe: _naLista(9, 'finalizado'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_pergunta), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Padaria Central')).controller!.text,
        'Padaria Central');
    expect(_qtd(tester, 'Pote 160g'), '40');
    expect(_qtd(tester, 'Copo'), '20');
    expect(_qtd(tester, 'Pudim'), '');
  });
}
