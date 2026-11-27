// test/comprovante_test.dart
//
// Função única do comprovante (texto, PDF e compartilhar) e o rótulo do botão
// em Meus pedidos: "Comprovante" nos entregues, "PDF" nos cancelados.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/pages/pedidos_page.dart';
import 'package:milkdim_app/utils/comprovante.dart';

Map<String, dynamic> _pedido(int id, String status, {Object? numero}) => {
      'id': id,
      'numero': numero ?? '$id',
      'status': status,
      'vendedor_codigo': '0003',
      'vendedor_nome': 'Vendedor Teste',
      'datahora': '2026-11-20T15:00:00+00:00',
      'total': 20.0,
      'cliente_id': 7,
      'cliente_nome': 'Padaria Central',
      'produtos':
          '[{"nome":"Leite ninho","subtotal":20.0,"preco":10.0,"quantidade":2,"unidade":"un"}]',
    };

Future<void> _abrirLista(WidgetTester tester, List<Map<String, dynamic>> pedidos,
    {int aba = 0}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(412, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: PedidosPage(
      vendedorCodigo: '0003',
      pedidosParaCaptura: pedidos,
      abaInicialParaCaptura: aba,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('textoComprovante', () {
    test('com número', () {
      expect(textoComprovante('70'),
          'Comprovante do pedido nº 70 – MilkDim. Obrigado pela preferência!');
      expect(textoComprovante(70), contains('nº 70 '));
    });

    test('sem número usa s/n', () {
      const esperado = 'Comprovante do pedido nº s/n – MilkDim. Obrigado pela preferência!';
      expect(textoComprovante(null), esperado);
      expect(textoComprovante(''), esperado);
      expect(textoComprovante('  '), esperado);
    });
  });

  test('pdfDoComprovante de pedido sem a assinatura do pedido gera PDF', () async {
    final bytes = await pdfDoComprovante(_pedido(1, 'finalizado'));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  group('botão em Meus pedidos', () {
    testWidgets('entregue mostra Comprovante e não PDF', (tester) async {
      await _abrirLista(tester, [_pedido(1, 'finalizado')], aba: 1);
      expect(find.text('Comprovante'), findsOneWidget);
      expect(find.text('PDF'), findsNothing);
    });

    testWidgets('cancelado continua com PDF', (tester) async {
      await _abrirLista(tester, [_pedido(2, 'cancelado')], aba: 2);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Comprovante'), findsNothing);
    });
  });
}
