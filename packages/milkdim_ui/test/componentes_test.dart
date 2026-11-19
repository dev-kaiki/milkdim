import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

Widget _app(Widget filho) => MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(body: SingleChildScrollView(child: filho)),
    );

void main() {
  testWidgets('MdLogoTitle mostra o nome e o logo do pacote', (tester) async {
    await tester.pumpWidget(_app(const MdLogoTitle()));
    expect(find.text('MilkDim'), findsOneWidget);
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, MdLogoTitle.logoPadrao);
    expect((img.image as AssetImage).keyName, 'packages/milkdim_ui/assets/logo.jpg');
    expect(img.width, 32);
  });

  testWidgets('MdCard renderiza o filho e chama onTap', (tester) async {
    var toques = 0;
    await tester.pumpWidget(_app(MdCard(onTap: () => toques++, child: const Text('Cliente'))));
    await tester.tap(find.text('Cliente'));
    expect(toques, 1);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('MdCard sem onTap não tem InkWell', (tester) async {
    await tester.pumpWidget(_app(const MdCard(child: Text('Fixo'))));
    expect(find.text('Fixo'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('MdStatusChip mostra texto e ícone com a cor do tipo', (tester) async {
    await tester.pumpWidget(_app(const MdStatusChip(
      tipo: MdTipo.sucesso,
      texto: 'Enviado',
      icone: Icons.check,
    )));
    expect(find.text('Enviado'), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.check)).color, MdColors.success);
    expect(tester.widget<Text>(find.text('Enviado')).style!.color, MdTipo.sucesso.corTexto);
  });

  testWidgets('MdBanner mostra texto, ícone padrão do tipo e ação', (tester) async {
    var enviou = false;
    await tester.pumpWidget(_app(MdBanner(
      tipo: MdTipo.atencao,
      texto: '2 pedidos aguardando envio',
      acao: TextButton(onPressed: () => enviou = true, child: const Text('Enviar agora')),
    )));
    expect(find.text('2 pedidos aguardando envio'), findsOneWidget);
    expect(find.byIcon(MdTipo.atencao.icone), findsOneWidget);
    await tester.tap(find.text('Enviar agora'));
    expect(enviou, isTrue);
  });

  testWidgets('MdEmptyState mostra ícone, título, texto e ação', (tester) async {
    await tester.pumpWidget(_app(MdEmptyState(
      icone: Icons.inbox_outlined,
      titulo: 'Nenhum pedido',
      texto: 'Os pedidos aparecem aqui.',
      acao: FilledButton(onPressed: () {}, child: const Text('Novo pedido')),
    )));
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('Nenhum pedido'), findsOneWidget);
    expect(find.text('Os pedidos aparecem aqui.'), findsOneWidget);
    expect(find.text('Novo pedido'), findsOneWidget);
  });

  testWidgets('MdSectionHeader mostra título e trailing', (tester) async {
    await tester
        .pumpWidget(_app(const MdSectionHeader(titulo: 'Clientes', trailing: Text('Ver todos'))));
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Ver todos'), findsOneWidget);
  });

  testWidgets('MdActionTile chama onTap e tem ao menos 88 de altura', (tester) async {
    var toques = 0;
    await tester.pumpWidget(_app(MdActionTile(
      icone: Icons.add_shopping_cart,
      titulo: 'Novo pedido',
      subtitulo: 'Começar um pedido',
      destaque: true,
      onTap: () => toques++,
    )));
    await tester.tap(find.text('Novo pedido'));
    expect(toques, 1);
    expect(tester.getSize(find.byType(MdActionTile)).height, greaterThanOrEqualTo(88));
    expect(tester.widget<Text>(find.text('Novo pedido')).style!.color, Colors.white);
  });

  testWidgets('MdActionTile desabilitado fica esmaecido', (tester) async {
    await tester.pumpWidget(_app(const MdActionTile(
      icone: Icons.list_alt,
      titulo: 'Meus pedidos',
      onTap: null,
    )));
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Text>(find.text('Meus pedidos')).style!.color, MdColors.text);
  });

  testWidgets('showMdSnack mostra o texto com a cor do tipo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildMilkdimTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMdSnack(context, 'Pedido salvo.', tipo: MdTipo.sucesso),
            child: const Text('Salvar'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Pedido salvo.'), findsOneWidget);
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, MdColors.success);
    expect(snack.behavior, SnackBarBehavior.floating);
  });

  testWidgets('MdSearchField mostra o botão de limpar só com texto', (tester) async {
    final buscas = <String>[];
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(
        _app(MdSearchField(controller: ctrl, hint: 'Buscar cliente', onChanged: buscas.add)));
    expect(find.text('Buscar cliente'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), 'padaria');
    await tester.pump();
    expect(buscas.last, 'padaria');
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(ctrl.text, isEmpty);
    expect(buscas.last, '');
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('MdSearchField funciona sem controller', (tester) async {
    await tester.pumpWidget(_app(const MdSearchField()));
    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('MdContentWidth limita a largura em telas largas', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home:
          MdContentWidth(child: Container(key: const Key('c'), height: 10, color: MdColors.border)),
    ));
    expect(tester.getSize(find.byKey(const Key('c'))).width, 1100);
  });
}
