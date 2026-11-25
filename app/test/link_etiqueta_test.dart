// test/link_etiqueta_test.dart
//
// Link da etiqueta aberto pela câmera do celular, fora do app: o app guarda o
// link e a tela inicial do vendedor abre o pedido. Dados falsos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

import 'package:milkdim_app/utils/link_etiqueta.dart';
import 'package:milkdim_app/widgets/ouvir_etiqueta_pendente.dart';

const _uuid = '3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b';
final _link = conteudoQrEntrega(_uuid);

Future<void> _abrir(WidgetTester tester,
    Future<String?> Function(BuildContext, String) abrir,
    {String vendedor = '0003'}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildMilkdimTheme(),
    home: Scaffold(
      body: OuvirEtiquetaPendente(
        vendedorCodigo: vendedor,
        abrir: abrir,
        child: const Text('inicio'),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => etiquetaPendente.value = null);

  test('guarda só link de etiqueta da MilkDim', () {
    receberLinkDeEtiqueta('https://exemplo.test/login#access_token=x');
    expect(etiquetaPendente.value, isNull);
    receberLinkDeEtiqueta(_link);
    expect(etiquetaPendente.value, _link);
  });

  testWidgets('link que chegou antes da tela (antes do login) abre ao entrar', (tester) async {
    etiquetaPendente.value = _link;
    final abertos = <String>[];
    await _abrir(tester, (_, lido) async {
      abertos.add(lido);
      return null;
    });
    expect(abertos, [_link]);
    expect(etiquetaPendente.value, isNull);
  });

  testWidgets('link que chega com a tela aberta abre na hora', (tester) async {
    final abertos = <String>[];
    await _abrir(tester, (_, lido) async {
      abertos.add(lido);
      return null;
    });
    expect(abertos, isEmpty);

    receberLinkDeEtiqueta(_link);
    await tester.pump();
    expect(abertos, [_link]);
  });

  testWidgets('quando não abre, mostra o motivo', (tester) async {
    etiquetaPendente.value = _link;
    await _abrir(tester, (_, __) async => 'Este pedido já foi entregue.');
    await tester.pump();
    expect(find.text('Este pedido já foi entregue.'), findsOneWidget);
  });

  testWidgets('sem vendedor logado, o link fica guardado', (tester) async {
    etiquetaPendente.value = _link;
    var chamou = false;
    await _abrir(tester, (_, __) async {
      chamou = true;
      return null;
    }, vendedor: '');
    expect(chamou, isFalse);
    expect(etiquetaPendente.value, _link);
  });
}
