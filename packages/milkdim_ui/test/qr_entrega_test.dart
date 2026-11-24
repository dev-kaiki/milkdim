import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

void main() {
  test('monta e lê o conteúdo do QR', () {
    const u = '3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b';
    expect(conteudoQrEntrega(u), 'MILKDIM:E:$u');
    expect(codigoDoQrEntrega('  MILKDIM:E:$u \n'), u);
    expect(codigoDoQrEntrega('MILKDIM:E:${u.toUpperCase()}'), u);
  });
  test('recusa conteúdo que não é da MilkDim', () {
    for (final s in [
      '',
      'https://milkdim.com',
      'MILKDIM:E:',
      'MILKDIM:E:123',
      'milkdim:e:3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b',
    ]) {
      expect(codigoDoQrEntrega(s), isNull, reason: s);
    }
  });
}
