// lib/utils/http_prazo.dart
//
// Cliente HTTP com prazo para o Supabase. Sem isso uma requisição parada (rede
// fraca, Wi-Fi com portal) nunca termina e segura a trava de pedidos para sempre.

import 'dart:async';

import 'package:http/http.dart' as http;

class ClienteHttpComPrazo extends http.BaseClient {
  ClienteHttpComPrazo({
    http.Client? interno,
    this.prazo = const Duration(seconds: 20),
  }) : _interno = interno ?? http.Client();

  final http.Client _interno;

  /// Prazo para chegar a resposta e, depois, entre um pedaço e outro do corpo.
  final Duration prazo;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final resp = await _interno.send(request).timeout(prazo);
    return http.StreamedResponse(
      resp.stream.timeout(prazo),
      resp.statusCode,
      contentLength: resp.contentLength,
      request: resp.request,
      headers: resp.headers,
      isRedirect: resp.isRedirect,
      persistentConnection: resp.persistentConnection,
      reasonPhrase: resp.reasonPhrase,
    );
  }

  @override
  void close() => _interno.close();
}
