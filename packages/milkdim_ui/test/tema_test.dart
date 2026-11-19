import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

void main() {
  final tema = buildMilkdimTheme();

  test('cores do spec', () {
    expect(MdColors.primary, const Color(0xFFE38A1D));
    expect(MdColors.primaryStrong, const Color(0xFFA85C0C));
    expect(MdColors.accent, const Color(0xFFFFE066));
    expect(MdColors.background, const Color(0xFFF7F5F2));
    expect(MdColors.border, const Color(0xFFE7E2DA));
    expect(MdColors.text, const Color(0xFF1F1B16));
    expect(MdColors.textMuted, const Color(0xFF6B645B));
    expect(MdColors.danger, const Color(0xFFC9372C));
  });

  test('Material 3 com o esquema de cores dos tokens', () {
    expect(tema.useMaterial3, isTrue);
    final c = tema.colorScheme;
    expect(c.primary, MdColors.primary);
    expect(c.onPrimary, Colors.white);
    expect(c.surface, Colors.white);
    expect(c.error, MdColors.danger);
    expect(c.outline, MdColors.border);
    expect(c.outlineVariant, MdColors.border);
    expect(tema.scaffoldBackgroundColor, MdColors.background);
  });

  test('a fonte é a Noto Sans do pacote em todo o texto', () {
    expect(mdFontFamily, 'packages/milkdim_ui/NotoSans');
    // Mesmo nome que TextStyle(fontFamily: 'NotoSans', package: 'milkdim_ui') gera.
    expect(const TextStyle(fontFamily: 'NotoSans', package: 'milkdim_ui').fontFamily, mdFontFamily);
    final tt = tema.textTheme;
    for (final s in [tt.bodyMedium, tt.bodySmall, tt.titleLarge, tt.labelLarge, tt.displaySmall]) {
      expect(s!.fontFamily, mdFontFamily);
    }
    expect(tema.appBarTheme.titleTextStyle!.fontFamily, mdFontFamily);
    expect(tema.snackBarTheme.contentTextStyle!.fontFamily, mdFontFamily);
  });

  test('texto de leitura não fica abaixo de 13 px e títulos são w700', () {
    final tt = tema.textTheme;
    for (final s in [tt.bodyLarge, tt.bodyMedium, tt.bodySmall, tt.labelLarge, tt.labelMedium]) {
      expect(s!.fontSize, greaterThanOrEqualTo(13));
    }
    expect(tt.titleLarge!.fontWeight, FontWeight.w700);
    expect(tt.titleMedium!.fontWeight, FontWeight.w700);
    expect(tt.bodySmall!.color, MdColors.textMuted);
    expect(tt.bodyMedium!.color, MdColors.text);
  });

  test('cartão sem sombra, com borda e raio 16', () {
    final card = tema.cardTheme;
    expect(card.elevation, 0);
    expect(card.margin, EdgeInsets.zero);
    final forma = card.shape! as RoundedRectangleBorder;
    expect(forma.borderRadius, BorderRadius.circular(16));
    expect(forma.side.color, MdColors.border);
  });

  test('barra superior branca com borda embaixo', () {
    final a = tema.appBarTheme;
    expect(a.backgroundColor, Colors.white);
    expect(a.surfaceTintColor, Colors.transparent);
    expect(a.scrolledUnderElevation, 0);
    expect(a.iconTheme!.color, MdColors.primaryStrong);
    expect((a.shape! as Border).bottom.color, MdColors.border);
  });

  test('botões: altura mínima 48 e raio 12', () {
    for (final estilo in [
      tema.filledButtonTheme.style!,
      tema.elevatedButtonTheme.style!,
      tema.outlinedButtonTheme.style!,
    ]) {
      expect(estilo.minimumSize!.resolve({})!.height, 48);
      final forma = estilo.shape!.resolve({})! as RoundedRectangleBorder;
      expect(forma.borderRadius, BorderRadius.circular(12));
    }
    expect(tema.elevatedButtonTheme.style!.backgroundColor!.resolve({}), MdColors.primary);
    expect(tema.elevatedButtonTheme.style!.elevation!.resolve({}), 0);
    expect(tema.outlinedButtonTheme.style!.foregroundColor!.resolve({}), MdColors.primaryStrong);
  });

  test('campos: borda normal, foco 2 px laranja e erro vermelho', () {
    final i = tema.inputDecorationTheme;
    expect(i.filled, isTrue);
    expect(i.fillColor, Colors.white);
    expect((i.enabledBorder! as OutlineInputBorder).borderSide.color, MdColors.border);
    final foco = i.focusedBorder! as OutlineInputBorder;
    expect(foco.borderSide.color, MdColors.primary);
    expect(foco.borderSide.width, 2);
    expect((i.errorBorder! as OutlineInputBorder).borderSide.color, MdColors.danger);
  });

  test('diálogo raio 20, snackbar flutuante e escuro', () {
    final d = tema.dialogTheme.shape! as RoundedRectangleBorder;
    expect(d.borderRadius, BorderRadius.circular(20));
    expect(tema.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(tema.snackBarTheme.backgroundColor, MdColors.text);
  });

  testWidgets('tema monta telas com os principais componentes sem erro', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: tema,
      home: Scaffold(
        appBar: AppBar(title: const MdLogoTitle()),
        body: ListView(children: [
          FilledButton(onPressed: () {}, child: const Text('Filled')),
          ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
          OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
          const TextField(decoration: InputDecoration(labelText: 'Nome')),
          const Card(child: Text('Cartão')),
          const Chip(label: Text('Chip')),
          Switch(value: true, onChanged: (_) {}),
          Checkbox(value: true, onChanged: (_) {}),
        ]),
        bottomNavigationBar: NavigationBar(destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.list), label: 'Pedidos'),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(48));
  });
}
