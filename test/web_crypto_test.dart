@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_me/crypto/key_backup.dart';
import 'package:secure_me/crypto/keygen.dart';
import 'package:secure_me/crypto/secure_package.dart';

// Run with: flutter test --platform chrome test/web_crypto_test.dart
void main() {
  test('WebCrypto keygen + package round-trip in a real browser', () async {
    final sw = Stopwatch()..start();
    final id = await generateIdentityFast();
    final keygenMs = sw.elapsedMilliseconds;
    expect(id.publicKey.publicExponent, BigInt.from(65537));

    sw.reset();
    final content = Uint8List(5 * 1024 * 1024)..[42] = 7;
    final pkg = await encryptPackage(EncryptRequest(
      kind: PayloadKind.file,
      content: content,
      fileName: 'clip.mp4',
      mimeType: 'video/mp4',
      recipientPublicDer: id.publicDer,
      sender: const SenderInfo(name: 'A', email: 'a@x.com', fingerprint: ''),
    ));
    final encMs = sw.elapsedMilliseconds;
    sw.reset();
    final out = await decryptPackage(DecryptRequest(package: pkg, identity: id));
    final decMs = sw.elapsedMilliseconds;
    expect(out.content, content);

    sw.reset();
    final backup = await wrapPrivateKey(WrapRequest(id.privateDer, 'pw12345678'));
    expect(await unwrapPrivateKey(UnwrapRequest(backup, 'pw12345678')), id.privateDer);
    final kdfMs = sw.elapsedMilliseconds;

    // ignore: avoid_print
    print(jsonEncode({'keygenMs': keygenMs, 'encrypt5MBms': encMs, 'decrypt5MBms': decMs, 'pbkdf2x2ms': kdfMs}));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
