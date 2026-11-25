import 'package:flutter_test/flutter_test.dart';
import 'package:milkdim_ui/milkdim_ui.dart';

void main() {
  const u = '3f2a1b4c-0d5e-4f60-8a7b-9c0d1e2f3a4b';
  const semTracos = '3f2a1b4c0d5e4f608a7b9c0d1e2f3a4b';

  test('o QR é um link: o código vai depois do # (não chega ao site)', () {
    expect(conteudoQrEntrega(u), 'https://dev-kaiki.github.io/m/#$semTracos');
    expect(conteudoQrEntrega(u.toUpperCase()), 'https://dev-kaiki.github.io/m/#$semTracos');
  });

  test('lê o link de volta no uuid com traços, em minúsculas', () {
    expect(codigoDoQrEntrega(conteudoQrEntrega(u)), u);
    expect(codigoDoQrEntrega('  https://dev-kaiki.github.io/m/#$semTracos \n'), u);
    expect(codigoDoQrEntrega('https://dev-kaiki.github.io/m/#${semTracos.toUpperCase()}'), u);
    expect(codigoDoQrEntrega('https://dev-kaiki.github.io/m/#$u'), u);
    expect(codigoDoQrEntrega('https://dev-kaiki.github.io/m#$semTracos'), u);
    expect(codigoDoQrEntrega('HTTPS://DEV-KAIKI.GITHUB.IO/m/#$semTracos'), u);
  });

  test('continua lendo as etiquetas no formato antigo', () {
    expect(codigoDoQrEntrega('  MILKDIM:E:$u \n'), u);
    expect(codigoDoQrEntrega('MILKDIM:E:${u.toUpperCase()}'), u);
  });

  test('recusa conteúdo que não é da MilkDim', () {
    for (final s in [
      '',
      'https://milkdim.com',
      'MILKDIM:E:',
      'MILKDIM:E:123',
      'milkdim:e:$u',
      'https://dev-kaiki.github.io/m/',
      'https://dev-kaiki.github.io/m/#123',
      'https://dev-kaiki.github.io/m/#${semTracos}00',
      'https://outro.github.io/m/#$semTracos',
      'http://dev-kaiki.github.io/m/#$semTracos',
      'https://dev-kaiki.github.io/x/#$semTracos',
      'https://dev-kaiki.github.io/m/?c=$semTracos',
      'https://dev-kaiki.github.io.exemplo.test/m/#$semTracos',
    ]) {
      expect(codigoDoQrEntrega(s), isNull, reason: s);
    }
  });
}
