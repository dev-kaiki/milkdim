// lib/utils/id_aparelho.dart
import 'dart:math';

final Random _rng = Random.secure();

/// UUID v4 (minúsculas, 8-4-4-4-12) gerado no aparelho, sem pacote externo.
/// Identifica o pedido de forma estável mesmo antes de ele chegar ao servidor.
String novoIdAparelho() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versão 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  String h(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}
