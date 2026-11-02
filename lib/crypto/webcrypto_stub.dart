import 'dart:typed_data';

// Non-web builds never call these; see webcrypto_web.dart.
Future<Uint8List> webGenerateRsaPkcs8(int bits) => throw UnsupportedError('web only');
Future<Uint8List> webRsaOaepEncrypt(Uint8List spki, Uint8List data) => throw UnsupportedError('web only');
Future<Uint8List> webRsaOaepDecrypt(Uint8List pkcs8, Uint8List data) => throw UnsupportedError('web only');
