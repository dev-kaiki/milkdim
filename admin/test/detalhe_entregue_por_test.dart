import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/widgets/detalhe_pedido.dart';

Pedido _p({
  String status = 'finalizado',
  String? por,
  String? dono = '0001',
  bool manual = false,
  String? codigoQr = 'qr-1',
  DateTime? impressaEm,
  String? impressaPor,
}) =>
    Pedido(
      id: 7,
      numero: '42',
      total: 10,
      status: status,
      vendedorCodigo: dono,
      finalizadoPor: por,
      finalizadoManual: manual,
      codigoQr: codigoQr,
      etiquetaImpressaEm: impressaEm,
      etiquetaImpressaPor: impressaPor,
      clienteNome: 'Cliente Teste',
      itens: const [PedidoItem(nome: 'Pudim', preco: 10, quantidade: 1)],
    );

void main() {
  group('textoEntreguePor', () {
    const nomes = {'0003': 'Vendedor Teste'};

    test('o dono', () {
      expect(textoEntreguePor(_p(por: '0001'), {'0001': 'Vendedor Teste'}),
          'Entregue por 0001 (Vendedor Teste)');
    });
    test('outro vendedor com nome conhecido', () {
      expect(textoEntreguePor(_p(por: '0003'), nomes),
          'Entregue por 0003 (Vendedor Teste) (outro vendedor)');
    });
    test('outro vendedor sem nome', () {
      expect(textoEntreguePor(_p(por: '0009'), nomes), 'Entregue por 0009 (outro vendedor)');
    });
    test('manual', () {
      expect(textoEntreguePor(_p(por: 'admin@exemplo.test', manual: true), const {}),
          'Entregue por admin@exemplo.test (manual)');
    });
    test('nao finalizado ou sem quem', () {
      expect(textoEntreguePor(_p(status: 'pronto', por: '0001'), nomes), isNull);
      expect(textoEntreguePor(_p(por: null), nomes), isNull);
    });
  });

  group('detalhe', () {
    Future<void> abrir(WidgetTester t, Pedido p, {Map<String, String> nomes = const {}}) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => abrirDetalhesPedido(
                ctx,
                p,
                buscar: (id) async => (raw: <String, dynamic>{'id': id}, parsed: p),
                nomesPorCodigo: nomes,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    testWidgets('pronto mostra Imprimir etiqueta e Sem etiqueta', (t) async {
      await abrir(t, _p(status: 'pronto'));
      expect(find.text('Imprimir etiqueta'), findsOneWidget);
      expect(find.text('Sem etiqueta'), findsOneWidget);
    });

    testWidgets('etiqueta impressa mostra hora e quem', (t) async {
      await abrir(
          t, _p(status: 'pronto', impressaEm: DateTime(2026, 11, 24, 9, 5), impressaPor: '0001'));
      expect(find.textContaining('Etiqueta impressa às'), findsOneWidget);
      expect(find.textContaining('por 0001'), findsOneWidget);
    });

    testWidgets('sem codigo_qr o botao fica desabilitado', (t) async {
      await abrir(t, _p(status: 'pronto', codigoQr: null));
      final b = t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Imprimir etiqueta'));
      expect(b.onPressed, isNull);
    });

    testWidgets('em aberto nao mostra o botao; entregue mostra quem entregou', (t) async {
      await abrir(t, _p(status: 'salvo'));
      expect(find.text('Imprimir etiqueta'), findsNothing);
    });

    testWidgets('entregue mostra Entregue por', (t) async {
      await abrir(t, _p(por: '0003'), nomes: const {'0003': 'Vendedor Teste'});
      expect(find.text('Entregue por 0003 (Vendedor Teste) (outro vendedor)'), findsOneWidget);
    });
  });
}
