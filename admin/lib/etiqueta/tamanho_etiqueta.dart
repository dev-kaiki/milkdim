import 'package:shared_preferences/shared_preferences.dart';

/// Tamanhos de etiqueta suportados pelo Controle.
enum TamanhoEtiqueta {
  m100x100(100, 100),
  m100x150(100, 150),
  m60x40(60, 40);

  const TamanhoEtiqueta(this.larguraMm, this.alturaMm);

  final double larguraMm;
  final double alturaMm;

  String get rotulo => '${larguraMm.round()} × ${alturaMm.round()} mm';
}

const _chave = 'etiqueta_tamanho';

/// Tamanho guardado neste computador; o padrão é 100 × 100 mm.
Future<TamanhoEtiqueta> lerTamanhoEtiqueta() async {
  final prefs = await SharedPreferences.getInstance();
  final nome = prefs.getString(_chave);
  for (final t in TamanhoEtiqueta.values) {
    if (t.name == nome) return t;
  }
  return TamanhoEtiqueta.m100x100;
}

Future<void> gravarTamanhoEtiqueta(TamanhoEtiqueta t) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_chave, t.name);
}
