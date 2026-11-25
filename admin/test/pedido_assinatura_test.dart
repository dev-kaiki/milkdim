import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_admin/models/pedido.dart';

void main() {
  final png = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0xab, 0xcd, 0xef]);
  String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  test('assinatura bytea como o PostgREST devolve (\\x + hex) vira os bytes', () {
    final p = Pedido.fromMap({
      'id': 1,
      'status': 'finalizado',
      'produtos': const [],
      'assinatura': '\\x${hex(png)}',
    });
    expect(p.assinaturaBytes, png);
    expect(p.temAssinatura, isTrue);
  });

  test('hex maiusculo tambem', () {
    final p = Pedido.fromMap(
        {'id': 1, 'status': 'finalizado', 'assinatura': '\\x${hex(png).toUpperCase()}'});
    expect(p.assinaturaBytes, png);
  });

  test('bytea antigo com o texto base64 dentro vira a imagem', () {
    final texto = base64Encode(png);
    final p = Pedido.fromMap(
        {'id': 1, 'status': 'finalizado', 'assinatura': '\\x${hex(texto.codeUnits)}'});
    expect(p.assinaturaBytes, png);
  });

  test('base64 continua aceito; sem assinatura fica null', () {
    expect(
        Pedido.fromMap({'id': 1, 'status': 'salvo', 'assinatura': base64Encode(png)})
            .assinaturaBytes,
        png);
    expect(Pedido.fromMap({'id': 1, 'status': 'salvo'}).assinaturaBytes, isNull);
    expect(Pedido.fromMap({'id': 1, 'status': 'salvo', 'assinatura': '\\xzz'}).assinaturaBytes,
        isNull);
  });
}
