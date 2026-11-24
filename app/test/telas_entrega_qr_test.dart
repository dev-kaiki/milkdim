// test/telas_entrega_qr_test.dart
//
// Fase B nas telas do vendedor: ler a etiqueta (QR) e registrar a entrega
// pelo servidor. Dados falsos; a câmera é trocada por um Stream de leituras.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/entrega_qr_page.dart';
import 'package:milkdim_app/pages/home_page.dart';
import 'package:milkdim_app/pages/ler_etiqueta_page.dart';
import 'package:milkdim_app/pages/pedido_edit_page.dart';
import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/regras_pedido.dart';
import 'package:milkdim_app/utils/entrega_qr.dart';
import 'package:milkdim_app/utils/pedido_da_tela.dart';

const _qr = '0b7e3c1a-5d2f-4c8e-9a41-6f3b2d7e8c90';
const _lido = 'milkdim:entrega:$_qr';

final Uint8List _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

Map<String, dynamic> _json({
  String status = 'pronto',
  bool proprio = false,
  bool reduzido = false,
}) =>
    reduzido
        ? {'numero': '70', 'status': status}
        : {
            'id': 42,
            'numero': '70',
            'status': status,
            'vendedor_codigo': '0002',
            'vendedor_nome': 'Outro Vendedor',
            'cliente_nome': 'Cliente Teste',
            'cliente_nome_fantasia': 'Padaria Teste',
            'cliente_cidade': 'Campinas',
            'itens': [
              {'nome': 'Leite ninho', 'quantidade': 3},
              {'nome': 'Pudim', 'quantidade': 2},
            ],
            'do_proprio_vendedor': proprio,
          };

Future<void> _abrir(WidgetTester tester, Widget pagina) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => pagina)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late List<String> buscas;
  late List<(String, String)> entregas;
  late Map<String, dynamic> Function() resposta;
  Object? falhaEntrega;

  setUp(() {
    buscas = [];
    entregas = [];
    resposta = () => _json();
    falhaEntrega = null;
    rpcPedidoPorQr = (c) async {
      buscas.add(c);
      return resposta();
    };
    rpcEntregarPorQr = (c, hex) async {
      entregas.add((c, hex));
      if (falhaEntrega != null) throw falhaEntrega!;
      return {'numero': '70'};
    };
  });

  Future<DestinoLeitura> servidor(String lido) async =>
      lido.contains(_qr) ? const AbrirEntregaServidor(_qr) : const QrInvalido();

  group('LerEtiquetaPage', () {
    testWidgets('três leituras iguais em sequência abrem uma tela só', (tester) async {
      final ctrl = StreamController<String>();
      addTearDown(ctrl.close);
      await _abrir(tester, LerEtiquetaPage(vendedorCodigo: '0003', leituras: ctrl.stream, decidir: servidor));

      ctrl.add(_lido);
      ctrl.add(_lido);
      ctrl.add(_lido);
      await tester.pumpAndSettle();

      expect(find.byType(EntregaQrPage), findsOneWidget);
      expect(buscas, [_qr]);

      // Fechada a tela de destino, a leitura volta.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(EntregaQrPage), findsNothing);
      ctrl.add(_lido);
      await tester.pumpAndSettle();
      expect(find.byType(EntregaQrPage), findsOneWidget);
      expect(buscas, [_qr, _qr]);
    });

    testWidgets('QR inválido mostra a mensagem e continua lendo', (tester) async {
      final ctrl = StreamController<String>();
      addTearDown(ctrl.close);
      await _abrir(tester, LerEtiquetaPage(vendedorCodigo: '0003', leituras: ctrl.stream, decidir: servidor));

      ctrl.add('https://exemplo.com');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Esta etiqueta não é de um pedido da MilkDim.'), findsOneWidget);
      expect(find.byType(LerEtiquetaPage), findsOneWidget);

      // Passado o intervalo, a próxima leitura é aceita.
      await tester.pump(const Duration(seconds: 3));
      ctrl.add(_lido);
      await tester.pumpAndSettle();
      expect(find.byType(EntregaQrPage), findsOneWidget);
    });

    testWidgets('sem internet mostra a mensagem e continua lendo', (tester) async {
      final ctrl = StreamController<String>();
      addTearDown(ctrl.close);
      await _abrir(
          tester,
          LerEtiquetaPage(
              vendedorCodigo: '0003',
              leituras: ctrl.stream, decidir: (_) async => const SemInternet()));
      ctrl.add(_lido);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.text('Sem internet. Para entregar pedido de outro vendedor, '
              'conecte e leia de novo.'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    for (final c in <(String, Map<String, dynamic>, String)>[
      (
        'pedido local entregue com assinatura',
        {'status': 'finalizado', 'numero': '70', 'assinatura': '0x89504e47', 'finalizado_manual': 0},
        'Este pedido já foi entregue.'
      ),
      (
        'pedido local cancelado',
        {'status': 'cancelado', 'numero': '70'},
        'Este pedido foi cancelado.'
      ),
      (
        'pedido local apagado no Controle',
        {'status': 'salvo', 'numero': '70', 'erro_envio': 'apagado'},
        kMsgApagadoNoControle
      ),
    ]) {
      testWidgets('${c.$1}: mostra a mensagem, não abre o editor e continua lendo',
          (tester) async {
        final ctrl = StreamController<String>();
        addTearDown(ctrl.close);
        await _abrir(
            tester,
            LerEtiquetaPage(
                vendedorCodigo: '0003',
                leituras: ctrl.stream, decidir: (_) async => AbrirPedidoLocal(c.$2)));
        ctrl.add(_lido);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(c.$3), findsOneWidget);
        expect(find.byType(PedidoPageEdit), findsNothing);
        expect(find.byType(LerEtiquetaPage), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('pedido local em aberto ainda abre o editor', (tester) async {
      final ctrl = StreamController<String>();
      addTearDown(ctrl.close);
      await _abrir(
          tester,
          LerEtiquetaPage(
              vendedorCodigo: '0003',
              leituras: ctrl.stream,
              editor: (p) => Scaffold(body: Text('editor ${p['numero']}')),
              decidir: (_) async => const AbrirPedidoLocal(
                  {'status': 'salvo', 'numero': '70', 'produtos': '[]'})));
      ctrl.add(_lido);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('editor 70'), findsOneWidget);
    });

    test('regra: entregue pelo Controle sem assinatura da entrega ainda abre', () {
      expect(
          podeAbrirPelaEtiqueta({'status': 'finalizado', 'finalizado_manual': 1}), isTrue);
      expect(podeAbrirPelaEtiqueta({'status': 'pronto'}), isTrue);
      expect(podeAbrirPelaEtiqueta({'status': 'cancelado'}), isFalse);
    });
  });

  group('EntregaQrPage', () {
    testWidgets(
        'EntregaQrPage de pedido pronto de outro vendedor mostra o aviso, itens e Registrar entrega',
        (tester) async {
      await _abrir(tester, const EntregaQrPage(codigoQr: _qr));
      expect(find.text('Pedido 70'), findsWidgets);
      expect(find.text('Pedido do vendedor 0002'), findsOneWidget);
      expect(find.text('Padaria Teste'), findsOneWidget);
      expect(find.text('Campinas'), findsOneWidget);
      expect(find.text('3×'), findsOneWidget);
      expect(find.text('Leite ninho'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      expect(find.text('Registrar entrega'), findsOneWidget);
    });

    testWidgets('pedido do próprio vendedor não mostra o aviso de outro vendedor',
        (tester) async {
      resposta = () => _json(proprio: true, status: 'salvo');
      await _abrir(tester, const EntregaQrPage(codigoQr: _qr));
      expect(find.textContaining('Pedido do vendedor'), findsNothing);
      expect(find.text('Registrar entrega'), findsOneWidget);
    });

    testWidgets(
        'Registrar entrega com assinatura chama entregarPorQr uma vez e mostra "Entrega registrada."',
        (tester) async {
      var pedidos = 0;
      await _abrir(
          tester,
          EntregaQrPage(
            codigoQr: _qr,
            pedirAssinatura: (tipo, {aviso}) async {
              pedidos++;
              expect(tipo, TipoAssinatura.entrega);
              return _png;
            },
          ));
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();

      expect(pedidos, 1);
      expect(entregas.length, 1);
      expect(entregas.single.$1, _qr);
      expect(entregas.single.$2, r'\x89504e47010203');
      expect(find.text('Entrega registrada.'), findsOneWidget);
      expect(find.byType(EntregaQrPage), findsNothing);
    });

    testWidgets('sem assinatura não chama o servidor', (tester) async {
      await _abrir(
          tester, EntregaQrPage(codigoQr: _qr, pedirAssinatura: (t, {aviso}) async => null));
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      expect(entregas, isEmpty);
      expect(find.byType(EntregaQrPage), findsOneWidget);
    });

    testWidgets(
        'pedido salvo de outro vendedor mostra "Este pedido ainda não está pronto para entrega." sem botão',
        (tester) async {
      resposta = () => _json(status: 'salvo');
      await _abrir(tester, const EntregaQrPage(codigoQr: _qr));
      expect(find.text('Este pedido ainda não está pronto para entrega.'), findsOneWidget);
      expect(find.text('Registrar entrega'), findsNothing);
    });

    testWidgets('pedido já entregue (forma reduzida) mostra o motivo sem botão',
        (tester) async {
      resposta = () => _json(status: 'finalizado', reduzido: true);
      await _abrir(tester, const EntregaQrPage(codigoQr: _qr));
      expect(find.text('Este pedido já foi entregue.'), findsOneWidget);
      expect(find.text('Registrar entrega'), findsNothing);
    });

    testWidgets('falha na entrega mostra a mensagem e mantém a tela', (tester) async {
      falhaEntrega = Exception('rede');
      await _abrir(
          tester, EntregaQrPage(codigoQr: _qr, pedirAssinatura: (t, {aviso}) async => _png));
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      expect(find.text('Não deu para confirmar a entrega. Leia a etiqueta de novo.'),
          findsOneWidget);
      expect(find.byType(EntregaQrPage), findsOneWidget);
      expect(find.text('Registrar entrega'), findsOneWidget);
    });

    testWidgets('falha ao ler o pedido mostra a mensagem', (tester) async {
      rpcPedidoPorQr = (_) async => throw Exception('rede');
      await _abrir(tester, const EntregaQrPage(codigoQr: _qr));
      expect(find.text('Não deu para ler o pedido. Leia a etiqueta de novo.'), findsOneWidget);
      expect(find.text('Registrar entrega'), findsNothing);
    });
  });

  testWidgets('Home e Meus pedidos têm o botão Ler etiqueta', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 1600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const HomePage(
          vendedor: {'codigo': '0003', 'nome': 'Vendedor Teste'}, pendentesParaCaptura: 0),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(find.text('Ler etiqueta'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: const PedidosPage(vendedorCodigo: '0003', pedidosParaCaptura: []),
    ));
    await tester.pump();
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    expect(find.byTooltip('Ler etiqueta'), findsOneWidget);
  });
}
