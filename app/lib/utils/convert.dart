// lib/utils/convert.dart
//
// Utilitários para converter assinatura entre formatos e, principalmente,
// obter bytes de IMAGEM (PNG/JPEG) prontos para o PDF.
//
// Funções principais:
//   - signatureToImageBytes(dynamic any) -> Uint8List?   (preferida no PDF)
//   - maybeValidImageBytes(dynamic any) -> Uint8List?    (alias da de cima)
//   - assinaturaToBytes(dynamic any) -> Uint8List?       (genérica; pode devolver não-imagem)
//   - bytesToHex0x(Uint8List bytes) -> String
//   - maybeAssinaturaField(dynamic any) -> String?       (hex "0x..." para BYTEA)
//   - bytesToBase64(Uint8List bytes) -> String
//   - maybeAssinaturaBase64(dynamic any) -> String?
//   - looksLikeImage(Uint8List bytes) -> bool
//   - imageTypeFromBytes(Uint8List bytes) -> 'png'|'jpeg'|null
//
// Coberturas extras:
//   - Aceita ByteData/ByteBuffer/List<int>/Uint8List/String(Map) e data-URI.
//   - Aceita objetos Map comuns: {assinatura|signature|..._base64|hex|bytes|data}.
//   - Trata "base64 de base64" (ex.: "aVZCT1J3..." -> "iVBORw0..." -> PNG).

import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart' as cvt;

/// Ative/desative logs desta unidade aqui:
const bool _kSigDebug = true;

/// ----------- Entrada genérica -> bytes (NÃO garante que seja imagem) -----------
Uint8List? assinaturaToBytes(dynamic assinatura) {
  if (_kSigDebug) {
    print('[SIG][convert] assinaturaToBytes() input=${assinatura?.runtimeType}');
  }
  if (assinatura == null) {
    if (_kSigDebug) print('[SIG][convert] -> null');
    return null;
  }

  // Bytes diretos
  if (assinatura is Uint8List) {
    if (_kSigDebug) print('[SIG][convert] -> Uint8List (${assinatura.length} bytes)');
    return assinatura.isEmpty ? null : assinatura;
  }
  if (assinatura is List<int>) {
    if (_kSigDebug) print('[SIG][convert] -> List<int> (${assinatura.length} bytes)');
    if (assinatura.isEmpty) return null;
    return Uint8List.fromList(assinatura);
  }
  if (assinatura is ByteData) {
    final b = assinatura.buffer.asUint8List();
    if (_kSigDebug) print('[SIG][convert] -> ByteData (${b.length} bytes)');
    return b;
  }
  if (assinatura is ByteBuffer) {
    final b = Uint8List.view(assinatura);
    if (_kSigDebug) print('[SIG][convert] -> ByteBuffer (${b.length} bytes)');
    return b;
  }

  // Map com várias chaves possíveis
  if (assinatura is Map) {
    final m = Map<String, dynamic>.from(assinatura as Map);
    for (final k in const [
      'assinatura',
      'signature',
      'bytes',
      'data',
      'base64',
      'assinatura_base64',
      'signature_base64',
      'hex',
      'value',
      'path', // caso alguém tenha salvo caminho
    ]) {
      if (m.containsKey(k) && m[k] != null) {
        if (_kSigDebug) print('[SIG][convert] -> Map encontrou chave "$k"');
        final v = m[k];
        final tried = assinaturaToBytes(v);
        if (tried != null) return tried;
      }
    }
    if (_kSigDebug) print('[SIG][convert] -> Map sem valor útil');
    return null;
  }

  // String: data-URI, HEX (0x/\\x) ou base64 (inclusive duplicado)
  if (assinatura is! String) {
    if (_kSigDebug) print('[SIG][convert] -> tipo não suportado (${assinatura.runtimeType})');
    return null;
  }
  var s = assinatura.trim();
  if (s.isEmpty) {
    if (_kSigDebug) print('[SIG][convert] -> String vazia');
    return null;
  }

  // 1) Data URI -> extrai payload base64
  final dataUri = _extractBase64FromDataUriIfAny(s);
  if (dataUri != null) {
    if (_kSigDebug) print('[SIG][convert] -> data:URI detectado (base64 len ~${dataUri.length})');
    final b = _decodeBase64Resiliente(dataUri);
    if (b != null) return b;
  }

  // 2) HEX com prefixo 0x ou \x (Postgres BYTEA)
  final cleanedHex = _stripHexPrefix(s);
  if (_looksLikeHex(cleanedHex)) {
    try {
      final b = Uint8List.fromList(cvt.hex.decode(cleanedHex));
      if (_kSigDebug) print('[SIG][convert] -> HEX (${b.length} bytes)');
      return b;
    } catch (_) {
      if (_kSigDebug) print('[SIG][convert] -> HEX inválido, tentar base64...');
      // cai para base64
    }
  }

  // 3) Base64 (inclui caso "base64 de base64")
  final b64 = _decodeBase64Resiliente(s);
  if (b64 != null) return b64;

  if (_kSigDebug) print('[SIG][convert] -> Falha ao decodificar String');
  return null;
}

/// Decodifica base64; se o resultado for TEXTO que também parece base64 (e típico de PNG/JPEG),
/// decodifica novamente. Limita-se a 2 camadas para evitar loop.
Uint8List? _decodeBase64Resiliente(String s) {
  try {
    final first = Uint8List.fromList(base64Decode(s.replaceAll(RegExp(r'\s'), '')));
    if (_kSigDebug) print('[SIG][convert] base64 1ª camada ok (${first.length} bytes)');

    // Se já virou imagem, ótimo
    if (looksLikeImage(first)) {
      if (_kSigDebug) print('[SIG][convert] 1ª camada já é IMAGEM (${imageTypeFromBytes(first)})');
      return first;
    }

    // Se virou TEXTO ASCII que parece base64 (e começa como PNG/JPEG), decodifica de novo
    if (_isAscii(first)) {
      final inner = utf8.decode(first, allowMalformed: true).trim();
      if (_looksLikeBase64(inner) && _looksLikeCommonImageB64Prefix(inner)) {
        if (_kSigDebug) print('[SIG][convert] 2ª camada base64 detectada (provável imagem)');
        final second = Uint8List.fromList(base64Decode(inner));
        if (_kSigDebug) print('[SIG][convert] base64 2ª camada ok (${second.length} bytes)');
        return second;
      }
    }
    // Retorna mesmo assim (assinaturaToBytes é genérica); quem exige imagem valida depois
    return first;
  } catch (e) {
    if (_kSigDebug) print('[SIG][convert] Falha base64: $e');
    return null;
  }
}

bool _isAscii(Uint8List b) {
  for (final v in b) {
    if (!(v == 9 || v == 10 || v == 13 || (v >= 32 && v <= 126))) return false;
  }
  return true;
}

bool _looksLikeBase64(String s) {
  if (s.isEmpty || s.length % 4 != 0) return false;
  final re = RegExp(r'^[A-Za-z0-9+/=]+$');
  return re.hasMatch(s);
}

/// Heurística: prefixos comuns de base64 de imagens
bool _looksLikeCommonImageB64Prefix(String s) {
  final t = s.substring(0, s.length < 8 ? s.length : 8);
  return t.startsWith('iVBORw0') || t.startsWith('/9j/');
}

/// ----------- Bytes -> persistência/strings auxiliares -----------
String bytesToHex0x(Uint8List bytes) => '0x${cvt.hex.encode(bytes)}';

String? maybeAssinaturaField(dynamic assinatura) {
  final bytes = assinaturaToBytes(assinatura);
  if (bytes == null) return null;
  return bytesToHex0x(bytes);
}

String bytesToBase64(Uint8List bytes) => base64Encode(bytes);

String? maybeAssinaturaBase64(dynamic assinatura) {
  final bytes = assinaturaToBytes(assinatura);
  if (bytes == null) return null;
  return bytesToBase64(bytes);
}

/// ----------- Checagem de imagem (para PDF) -----------
bool _looksLikePng(Uint8List b) {
  if (b.length < 8) return false;
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    if (b[i] != sig[i]) return false;
  }
  return true;
}

bool _looksLikeJpeg(Uint8List b) {
  if (b.length < 2) return false;
  return b[0] == 0xFF && b[1] == 0xD8;
}

String? imageTypeFromBytes(Uint8List b) {
  if (_looksLikePng(b)) return 'png';
  if (_looksLikeJpeg(b)) return 'jpeg';
  return null;
}

bool looksLikeImage(Uint8List b) => imageTypeFromBytes(b) != null;

/// ----------- O QUE O PDF QUER: bytes de imagem (PNG/JPEG) -----------
Uint8List? signatureToImageBytes(dynamic any) {
  final bytes = assinaturaToBytes(any);

  if (bytes == null || bytes.isEmpty) {
    if (_kSigDebug) print('[SIG][convert] signatureToImageBytes -> null/empty');
    return null;
  }

  final tipo = imageTypeFromBytes(bytes);
  if (tipo == null) {
    if (_kSigDebug) {
      print('[SIG][convert] signatureToImageBytes -> NÃO É IMAGEM válida (${bytes.length} bytes)');
    }
    return null;
  }

  if (_kSigDebug) {
    print('[SIG][convert] signatureToImageBytes -> IMAGEM DETECTADA '
        '(${bytes.length} bytes, tipo=$tipo)');
  }
  return bytes;
}

/// Alias antigo para compatibilidade
Uint8List? maybeValidImageBytes(dynamic any) => signatureToImageBytes(any);

/// ----------- Helpers privados -----------
String _stripHexPrefix(String s) {
  if (s.startsWith('0x') || s.startsWith('0X')) return s.substring(2);
  if (s.startsWith(r'\x') || s.startsWith(r'\X')) return s.substring(2);
  return s;
}

bool _looksLikeHex(String s) {
  if (s.length % 2 != 0) return false;
  final hexRe = RegExp(r'^[0-9a-fA-F]+$');
  return hexRe.hasMatch(s);
}

/// Extrai payload base64 de data-URI; senão retorna null.
/// Ex.: "data:image/png;base64,iVBORw0..." -> "iVBORw0..."
String? _extractBase64FromDataUriIfAny(String s) {
  final m = RegExp(
    r'^data:(?:image/[^;]+);base64,(\s*[A-Za-z0-9+/=\s]+)$',
    caseSensitive: false,
  ).firstMatch(s);
  return m?.group(1)?.replaceAll(RegExp(r'\s'), '');
}
