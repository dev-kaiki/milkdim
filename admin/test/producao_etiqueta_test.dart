import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/etiqueta/tamanho_etiqueta.dart';
import 'package:milkdim_admin/models/pedido.dart';
import 'package:milkdim_admin/tabs/producao_tab.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Pedido _pronto({
  int id = 7,
  String? codigoQr = '11111111-1111-1111-1111-111111111111',
  DateTime? impressaEm,
  DateTime? alteradoEm,
}) =>
    Pedido(
      id: id,
      numero: '$id',
      status: 'pronto',
      total: 10,
      vendedorCodigo: '0002',
      vendedorNome: 'Vendedor Teste',
      clienteNome: 'Cliente Teste',
      clienteCidade: 'Cidade Teste',
      enviadoEm: DateTime.now().subtract(const Duration(hours: 5)),
      prontoEm: DateTime.now().subtract(const Duration(hours: 1)),
      alteradoEm: alteradoEm,
      codigoQr: codigoQr,
      etiquetaImpressaEm: impressaEm,
      itens: const [PedidoItem(nome: 'Pudim tradicional', preco: 1, quantidade: 3)],
    );

Widget _app(Widget tab) => MaterialApp(theme: buildMilkdimTheme(), home: Scaffold(body: tab));

Future<void> _abrir(
  WidgetTester tester,
  List<Pedido> Function() lista, {
  required List<int> marcadas,
  required List<int> envios,
  bool envioOk = true,
  Future<void> Function(int, String?)? marcarPronto,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(ProducaoTab(
    carregar: () async => lista(),
    marcarPronto: marcarPronto,
    marcarEtiqueta: (id) async => marcadas.add(id),
    enviarParaImpressora: (Uint8List pdf, TamanhoEtiqueta t) async {
      envios.add(pdf.length);
      return envioOk;
    },
  )));
  await tester.pumpAndSettle();
}

/// Gerar o PDF usa assets e isolates reais: espera em tempo real até [ok].
Future<void> _esperar(WidgetTester tester, bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pronto sem etiqueta mostra "Sem etiqueta" e o botão Imprimir etiqueta',
      (tester) async {
    await _abrir(tester, () => [_pronto()], marcadas: [], envios: []);
    expect(find.text('Sem etiqueta'), findsOneWidget);
    expect(find.text('Imprimir etiqueta'), findsOneWidget);
  });

  testWidgets('Sim em "A etiqueta saiu certa?" marca a etiqueta uma vez', (tester) async {
    final marcadas = <int>[], envios = <int>[];
    await _abrir(tester, () => [_pronto()], marcadas: marcadas, envios: envios);
    await tester.tap(find.text('Imprimir etiqueta'));
    await _esperar(tester, () => envios.isNotEmpty);
    expect(find.text('A etiqueta saiu certa?'), findsOneWidget);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(envios.length, 1);
    expect(marcadas, [7]);
  });

  testWidgets('Imprimir de novo envia outra vez e só marca no Sim', (tester) async {
    final marcadas = <int>[], envios = <int>[];
    await _abrir(tester, () => [_pronto()], marcadas: marcadas, envios: envios);
    await tester.tap(find.text('Imprimir etiqueta'));
    await _esperar(tester, () => envios.isNotEmpty);
    await tester.tap(find.text('Imprimir de novo'));
    await _esperar(tester, () => envios.length >= 2);
    expect(envios.length, 2);
    expect(marcadas, isEmpty);
    expect(find.text('A etiqueta saiu certa?'), findsOneWidget);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(envios.length, 2);
    expect(marcadas, [7]);
  });

  testWidgets('Cancelar não marca', (tester) async {
    final marcadas = <int>[], envios = <int>[];
    await _abrir(tester, () => [_pronto()], marcadas: marcadas, envios: envios);
    await tester.tap(find.text('Imprimir etiqueta'));
    await _esperar(tester, () => envios.isNotEmpty);
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(envios.length, 1);
    expect(marcadas, isEmpty);
    expect(find.text('A etiqueta saiu certa?'), findsNothing);
  });

  testWidgets('diálogo do sistema cancelado (enviar devolve false) não pergunta nem marca',
      (tester) async {
    final marcadas = <int>[], envios = <int>[];
    await _abrir(tester, () => [_pronto()],
        marcadas: marcadas, envios: envios, envioOk: false);
    await tester.tap(find.text('Imprimir etiqueta'));
    await _esperar(tester, () => envios.isNotEmpty);
    expect(envios.length, 1);
    expect(find.text('A etiqueta saiu certa?'), findsNothing);
    expect(marcadas, isEmpty);
  });

  testWidgets('alterado depois da impressão mostra "Etiqueta desatualizada"', (tester) async {
    final impressa = DateTime.now().subtract(const Duration(hours: 2));
    await _abrir(
        tester,
        () => [
              _pronto(
                  impressaEm: impressa,
                  alteradoEm: impressa.add(const Duration(minutes: 30)))
            ],
        marcadas: [],
        envios: []);
    expect(find.text('Etiqueta desatualizada'), findsOneWidget);
    expect(find.textContaining('Etiqueta impressa às'), findsNothing);
  });

  testWidgets('impressa e sem alteração mostra "Etiqueta impressa às"', (tester) async {
    await _abrir(
        tester, () => [_pronto(impressaEm: DateTime.now().subtract(const Duration(hours: 2)))],
        marcadas: [], envios: []);
    expect(find.textContaining('Etiqueta impressa às'), findsOneWidget);
  });

  testWidgets('sem codigoQr o botão fica desabilitado', (tester) async {
    await _abrir(tester, () => [_pronto(codigoQr: null)], marcadas: [], envios: []);
    final btn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Imprimir etiqueta'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('depois de Produção concluída pergunta "Imprimir a etiqueta agora?"',
      (tester) async {
    final marcadas = <int>[], envios = <int>[];
    final aberto = Pedido(
      id: 3,
      numero: '3',
      status: 'salvo',
      total: 10,
      clienteNome: 'Cliente Teste',
      enviadoEm: DateTime.now().subtract(const Duration(hours: 2)),
      codigoQr: '22222222-2222-2222-2222-222222222222',
      itens: const [PedidoItem(nome: 'Pudim tradicional', preco: 1, quantidade: 3)],
    );
    var cargas = 0;
    await _abrir(
      tester,
      () {
        cargas++;
        return cargas == 1 ? [aberto] : [aberto.copyWith(status: 'pronto', prontoEm: DateTime.now())];
      },
      marcadas: marcadas,
      envios: envios,
      marcarPronto: (id, bruto) async {},
    );
    await tester.tap(find.text('Produção concluída'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Imprimir a etiqueta agora?'), findsOneWidget);
    await tester.tap(find.text('Agora'));
    await _esperar(tester, () => envios.isNotEmpty);
    expect(envios.length, 1);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(marcadas, [3]);
  });

  test('Pedido.fromMap lê codigo_qr e as colunas de etiqueta', () {
    final p = Pedido.fromMap({
      'id': 1,
      'status': 'pronto',
      'codigo_qr': 'abc',
      'etiqueta_impressa_em': '2026-11-24T14:05:00Z',
      'etiqueta_impressa_por': 'admin',
      'alterado_em': '2026-11-24T15:00:00Z',
    });
    expect(p.codigoQr, 'abc');
    expect(p.etiquetaImpressaEm, DateTime.utc(2026, 11, 24, 14, 5));
    expect(p.etiquetaImpressaPor, 'admin');
    expect(p.etiquetaDesatualizada, isTrue);
  });
}
