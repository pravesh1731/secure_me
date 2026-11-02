import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_me/crypto/key_backup.dart';
import 'package:secure_me/crypto/rsa_keys.dart';
import 'package:secure_me/crypto/secure_package.dart';

void main() {
  late RsaIdentity alice;
  late RsaIdentity bob;
  const sender = SenderInfo(name: 'Alice', email: 'alice@example.com', fingerprint: 'X');

  setUpAll(() {
    alice = generateIdentity(kRsaKeyBits);
    bob = generateIdentity(kRsaKeyBits);
  });

  EncryptRequest requestFor(RsaIdentity to, Uint8List content) => EncryptRequest(
        kind: PayloadKind.file,
        content: content,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        recipientPublicDer: to.publicDer,
        sender: sender,
      );

  test('round-trips a file for the intended recipient', () async {
    final content = randomBytes(300000);
    final pkg = await encryptPackage(requestFor(bob, content));
    final out = await decryptPackage(DecryptRequest(package: pkg, identity: bob));
    expect(out.content, content);
    expect(out.fileName, 'photo.jpg');
    expect(out.mimeType, 'image/jpeg');
    expect(out.sender.email, 'alice@example.com');
    expect(peekRecipientFingerprint(pkg), bob.fingerprint);
  });

  test('another user cannot decrypt', () async {
    final pkg = await encryptPackage(requestFor(bob, Uint8List.fromList([1, 2, 3])));
    await expectLater(decryptPackage(DecryptRequest(package: pkg, identity: alice)),
        throwsA(isA<NotForYouException>()));
  });

  test('tampering with body or header is detected', () async {
    final pkg = await encryptPackage(requestFor(bob, Uint8List.fromList(utf8.encode('secret'))));
    final body = Uint8List.fromList(pkg)..[pkg.length - 20] ^= 1;
    await expectLater(decryptPackage(DecryptRequest(package: body, identity: bob)),
        throwsA(isA<PackageException>()));

    // Flip a byte inside the base64 nonce in the header ('iv' value).
    final text = latin1.decode(pkg.sublist(0, 600));
    final ivAt = text.indexOf('"iv":"') + 7;
    final header = Uint8List.fromList(pkg)..[ivAt] = pkg[ivAt] == 0x41 ? 0x42 : 0x41;
    await expectLater(decryptPackage(DecryptRequest(package: header, identity: bob)),
        throwsA(isA<PackageException>()));
  });

  test('text armor round-trips', () async {
    final pkg = await encryptPackage(requestFor(bob, Uint8List.fromList(utf8.encode('hi'))));
    final armored = armorPackage(pkg);
    expect(isArmored(armored), isTrue);
    expect(dearmorPackage(armored), pkg);
    expect(() => dearmorPackage('hello'), throwsA(isA<PackageException>()));
  });

  test('public key PEM parses back and rejects junk', () {
    final pem = publicKeyToPem(bob.publicDer);
    expect(parsePublicKeyInput(pem), bob.publicDer);
    expect(parsePublicKeyInput(base64.encode(bob.publicDer)), bob.publicDer);
    expect(() => parsePublicKeyInput('nope'), throwsFormatException);
  });

  test('private key backup unwraps only with the right password', () async {
    final backup = await wrapPrivateKey(WrapRequest(alice.privateDer, 'correct horse'));
    expect(await unwrapPrivateKey(UnwrapRequest(backup, 'correct horse')), alice.privateDer);
    await expectLater(unwrapPrivateKey(UnwrapRequest(backup, 'wrong')),
        throwsA(isA<WrongPasswordException>()));
    // Restored DER must rebuild the same identity and still decrypt.
    final restored = identityFromPrivate(await unwrapPrivateKey(UnwrapRequest(backup, 'correct horse')));
    expect(restored.publicDer, alice.publicDer);
    final pkg = await encryptPackage(requestFor(alice, Uint8List.fromList([9])));
    expect((await decryptPackage(DecryptRequest(package: pkg, identity: restored))).content, [9]);
  });

  test('PKCS#8 keys from OpenSSL/WebCrypto load with the standard public key', () async {
    // Throwaway test key generated with `openssl genpkey | openssl pkcs8 -topk8`.
    final id = identityFromPrivate(File('test/fixtures/openssl_test_key.p8.der').readAsBytesSync());
    expect(id.publicDer, File('test/fixtures/openssl_test_key.spki.der').readAsBytesSync());
    expect(id.publicKey.publicExponent, BigInt.from(65537));
    final pkg = await encryptPackage(requestFor(id, Uint8List.fromList([4, 2])));
    expect((await decryptPackage(DecryptRequest(package: pkg, identity: id))).content, [4, 2]);
  });
}
