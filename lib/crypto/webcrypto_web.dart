import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Browser-native RSA-OAEP (SHA-256). Pure-Dart RSA compiled to JS is far
// slower: ~10s for key generation, ~1s+ per private-key operation.

web.SubtleCrypto get _subtle => web.window.crypto.subtle;

JSObject _oaepParams([int? bits]) {
  final p = JSObject()
    ..setProperty('name'.toJS, 'RSA-OAEP'.toJS)
    ..setProperty('hash'.toJS, 'SHA-256'.toJS);
  if (bits != null) {
    p
      ..setProperty('modulusLength'.toJS, bits.toJS)
      ..setProperty('publicExponent'.toJS, Uint8List.fromList([1, 0, 1]).toJS);
  }
  return p;
}

Uint8List _bytes(JSAny? buffer) => (buffer as JSArrayBuffer).toDart.asUint8List();

Future<Uint8List> webGenerateRsaPkcs8(int bits) async {
  final pair = await _subtle
      .generateKey(_oaepParams(bits), true, ['encrypt'.toJS, 'decrypt'.toJS].toJS)
      .toDart as JSObject;
  return _bytes(await _subtle.exportKey('pkcs8', pair.getProperty<web.CryptoKey>('privateKey'.toJS)).toDart);
}

Future<Uint8List> webRsaOaepEncrypt(Uint8List spki, Uint8List data) async {
  final key = await _subtle.importKey('spki', spki.toJS, _oaepParams(), false, ['encrypt'.toJS].toJS).toDart;
  return _bytes(await _subtle.encrypt(_oaepParams(), key, data.toJS).toDart);
}

Future<Uint8List> webRsaOaepDecrypt(Uint8List pkcs8, Uint8List data) async {
  final key = await _subtle.importKey('pkcs8', pkcs8.toJS, _oaepParams(), false, ['decrypt'.toJS].toJS).toDart;
  return _bytes(await _subtle.decrypt(_oaepParams(), key, data.toJS).toDart);
}
