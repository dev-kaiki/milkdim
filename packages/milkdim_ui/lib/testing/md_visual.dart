/// Captura visual para testes (não exportado por `milkdim_ui.dart`).
///
/// Uso num teste de app ou do pacote:
///
/// ```dart
/// import 'package:milkdim_ui/testing/md_visual.dart';
///
/// void main() {
///   setUpAll(carregarFontesReais);
///   testWidgets('login', (tester) async {
///     await capturar(tester, const LoginPage(), 'login');
///   });
/// }
/// ```
///
/// O PNG sai em `<raiz do pacote ou app>/build/visual/<nome>.png`. Sem comparação
/// com golden: serve só para revisão humana.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../milkdim_ui.dart';

bool _fontesCarregadas = false;

/// Carrega a Noto Sans do pacote (como `packages/milkdim_ui/NotoSans`) e a fonte dos
/// ícones do Material (do SDK do Flutter). Chame em `setUpAll`. Se algum arquivo não
/// for achado, só avisa no console: o teste continua (os glifos saem como caixas).
Future<void> carregarFontesReais() async {
  if (_fontesCarregadas) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  final noto = FontLoader(mdFontFamily);
  var achou = 0;
  for (final arq in const ['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf']) {
    final bytes = await _lerFontePacote(arq);
    if (bytes == null) {
      debugPrint('md_visual: fonte $arq do milkdim_ui não encontrada.');
      continue;
    }
    noto.addFont(Future.value(ByteData.sublistView(bytes)));
    achou++;
  }
  if (achou > 0) await noto.load();

  final icones = await _lerMaterialIcons();
  if (icones == null) {
    debugPrint('md_visual: MaterialIcons-Regular.otf não encontrada (defina FLUTTER_ROOT).');
  } else {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icones)))).load();
  }
  _fontesCarregadas = true;
}

/// Monta [tela] num MaterialApp com [buildMilkdimTheme] no tamanho lógico [tamanho]
/// (devicePixelRatio 2) e grava `build/visual/<nome>.png`. Diálogos e snackbars entram
/// na imagem. Animações infinitas não travam: só alguns quadros são bombeados.
Future<void> capturar(
  WidgetTester tester,
  Widget tela,
  String nome, {
  Size tamanho = const Size(412, 892),
}) async {
  const dpr = 2.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = tamanho * dpr;
  addTearDown(tester.view.reset);

  // O flutter_test troca sombras por um contorno preto; na captura queremos a sombra real.
  final sombrasAntes = debugDisableShadows;
  debugDisableShadows = false;
  try {
    final chave = GlobalKey();
    Widget app() => MaterialApp(
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: buildMilkdimTheme(),
          builder: (context, child) => RepaintBoundary(key: chave, child: child),
          home: tela,
        );
    await tester.pumpWidget(app());
    await tester.pump();

    // Imagens só decodificam em tempo real. As que a primeira montagem pediu ficaram
    // presas no relógio falso do teste: limpa o cache, carrega de verdade e remonta.
    final imagens = find.byType(Image).evaluate().toList();
    if (imagens.isNotEmpty) {
      imageCache
        ..clear()
        ..clearLiveImages();
      await tester.runAsync(() async {
        for (final el in imagens) {
          final img = el.widget as Image;
          await precacheImage(img.image, el, onError: (_, __) {})
              .timeout(const Duration(seconds: 10), onTimeout: () {});
        }
      });
      await tester.pumpWidget(app());
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(chave));
    final arquivo = File('build/visual/$nome.png');
    await tester.runAsync(() async {
      final ui.Image imagem = await boundary.toImage(pixelRatio: dpr);
      final dados = await imagem.toByteData(format: ui.ImageByteFormat.png);
      imagem.dispose();
      await arquivo.parent.create(recursive: true);
      await arquivo.writeAsBytes(dados!.buffer.asUint8List());
    });
    debugPrint('md_visual: ${arquivo.absolute.path}');
  } finally {
    debugDisableShadows = sombrasAntes;
  }
}

/// Lê um .ttf do pacote: primeiro do bundle de teste (app ou o próprio pacote), depois
/// do disco via `.dart_tool/package_config.json`.
Future<Uint8List?> _lerFontePacote(String arq) async {
  for (final chave in ['packages/milkdim_ui/fonts/$arq', 'fonts/$arq']) {
    try {
      final dados = await rootBundle.load(chave);
      return dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes);
    } catch (_) {}
  }
  final raiz = _raizDoPacote();
  if (raiz == null) return null;
  final f = File('${raiz.path}/fonts/$arq');
  return f.existsSync() ? f.readAsBytesSync() : null;
}

Directory? _raizDoPacote() {
  try {
    final cfg = File('.dart_tool/package_config.json');
    if (!cfg.existsSync()) return null;
    final json = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
    for (final p in (json['packages'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      if (p['name'] != 'milkdim_ui') continue;
      final base = Uri.directory('${Directory.current.path}/.dart_tool/');
      return Directory.fromUri(base.resolve(p['rootUri'] as String));
    }
  } catch (_) {}
  return null;
}

/// Acha a fonte dos ícones em `<flutter>/bin/cache/artifacts/material_fonts/`.
Future<Uint8List?> _lerMaterialIcons() async {
  final raiz = _raizDoFlutter();
  if (raiz != null) {
    final dir = Directory('$raiz/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        final n = f.uri.pathSegments.last.toLowerCase();
        if (n == 'materialicons-regular.otf') return f.readAsBytesSync();
      }
    }
  }
  // Plano B: o bundle de teste também leva a fonte quando uses-material-design é true.
  try {
    final dados = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    return dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes);
  } catch (_) {
    return null;
  }
}

String? _raizDoFlutter() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty && Directory(env).existsSync()) return env;
  final path = Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
  final sep = Platform.isWindows ? ';' : ':';
  final nomes = Platform.isWindows ? const ['flutter.bat', 'flutter'] : const ['flutter'];
  for (final dir in path.split(sep)) {
    if (dir.isEmpty) continue;
    for (final nome in nomes) {
      final f = File('$dir/$nome');
      if (!f.existsSync()) continue;
      final real = File(f.resolveSymbolicLinksSync());
      final bin = real.parent;
      if (bin.uri.pathSegments.where((s) => s.isNotEmpty).last == 'bin') {
        return bin.parent.path;
      }
    }
  }
  return null;
}
