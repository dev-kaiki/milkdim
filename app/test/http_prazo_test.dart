// test/http_prazo_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:milkdim_app/utils/http_prazo.dart';

void main() {
  test('requisição parada estoura o prazo', () async {
    final parado = MockClient((_) => Completer<http.Response>().future);
    final c = ClienteHttpComPrazo(interno: parado, prazo: const Duration(milliseconds: 50));
    await expectLater(
      c.get(Uri.parse('https://exemplo.invalid/rest/v1/pedidos')),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('resposta normal passa sem mudança', () async {
    final ok = MockClient((_) async => http.Response('[]', 200));
    final c = ClienteHttpComPrazo(interno: ok, prazo: const Duration(seconds: 1));
    final r = await c.get(Uri.parse('https://exemplo.invalid/rest/v1/pedidos'));
    expect(r.statusCode, 200);
    expect(r.body, '[]');
  });
}
