import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' show CryptoUtils;
import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// RSA modulus size used for every Secure-Me identity key.
const int kRsaKeyBits = 2048;

/// A user's RSA identity, stored as DER bytes so it can cross isolates and
/// be written to secure storage / Firestore without re-encoding.
class RsaIdentity {
  RsaIdentity({required this.publicDer, required this.privateDer});

  /// SubjectPublicKeyInfo (X.509) DER.
  final Uint8List publicDer;

  /// PKCS#8 DER.
  final Uint8List privateDer;

  late final RSAPublicKey publicKey = decodePublicKey(publicDer);
  late final RSAPrivateKey privateKey =
      CryptoUtils.rsaPrivateKeyFromDERBytes(privateDer);
  late final String fingerprint = keyFingerprint(publicDer);
}

/// Cryptographically secure PRNG seeded from the OS entropy source.
SecureRandom secureRandom() {
  final seed = Uint8List(32);
  final os = Random.secure();
  for (var i = 0; i < seed.length; i++) {
    seed[i] = os.nextInt(256);
  }
  return FortunaRandom()..seed(KeyParameter(seed));
}

/// Bytes straight from the OS CSPRNG (used for AES keys, nonces, salts).
Uint8List randomBytes(int length) {
  final os = Random.secure();
  return Uint8List.fromList(List<int>.generate(length, (_) => os.nextInt(256)));
}

/// Generates a fresh RSA key pair. Slow (pure Dart), so call it via
/// `compute(generateIdentity, kRsaKeyBits)`.
RsaIdentity generateIdentity(int bits) {
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
      secureRandom(),
    ));
  final pair = generator.generateKeyPair();
  final public = pair.publicKey;
  final private = pair.privateKey;
  return RsaIdentity(
    publicDer: CryptoUtils.encodeRSAPublicKeyToDERBytes(public),
    privateDer: CryptoUtils.encodeRSAPrivateKeyToDERBytes(private),
  );
}

RSAPublicKey decodePublicKey(Uint8List der) =>
    CryptoUtils.rsaPublicKeyFromDERBytes(der);

/// Rebuilds the identity from its private key alone (the public half is
/// derivable), e.g. after restoring a key backup.
RsaIdentity identityFromPrivate(Uint8List privateDer) {
  // Read n and e straight from PKCS#8 → PKCS#1 RSAPrivateKey. Recomputing e
  // from d (as pointycastle does) gives a valid but non-standard exponent
  // for keys whose d was derived mod λ(n), e.g. from WebCrypto or OpenSSL.
  final pkcs8 = ASN1Parser(privateDer).nextObject() as ASN1Sequence;
  final rsa = ASN1Parser(pkcs8.elements![2].valueBytes).nextObject() as ASN1Sequence;
  final public = RSAPublicKey(
    (rsa.elements![1] as ASN1Integer).integer!,
    (rsa.elements![2] as ASN1Integer).integer!,
  );
  return RsaIdentity(
    publicDer: CryptoUtils.encodeRSAPublicKeyToDERBytes(public),
    privateDer: privateDer,
  );
}

/// SHA-256 of the public key DER, upper-case hex. This is the value users
/// compare out-of-band to confirm they have the right key.
String keyFingerprint(Uint8List publicDer) =>
    hash.sha256.convert(publicDer).toString().toUpperCase();

/// `AB12 CD34 ...` grouping for display. [groups] limits the length.
String formatFingerprint(String fingerprint, {int? groups}) {
  final parts = <String>[];
  for (var i = 0; i + 4 <= fingerprint.length; i += 4) {
    parts.add(fingerprint.substring(i, i + 4));
  }
  return (groups == null ? parts : parts.take(groups)).join(' ');
}

/// Public key as a standard PEM block, which is what users copy and share.
String publicKeyToPem(Uint8List publicDer) {
  final b64 = base64.encode(publicDer);
  final lines = <String>[];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, min(i + 64, b64.length)));
  }
  return '-----BEGIN PUBLIC KEY-----\n${lines.join('\n')}\n-----END PUBLIC KEY-----';
}

/// Parses a public key pasted by a user: either a PEM block or the bare
/// base64 of the DER. Throws [FormatException] if it isn't a usable RSA key.
Uint8List parsePublicKeyInput(String input) {
  final body = input
      .replaceAll(RegExp(r'-----(BEGIN|END)[^-]*-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) throw const FormatException('Paste a public key.');
  final Uint8List der;
  try {
    der = base64.decode(body);
  } on FormatException {
    throw const FormatException('Not a valid public key (bad base64).');
  }
  final RSAPublicKey key;
  try {
    key = decodePublicKey(der);
  } catch (_) {
    throw const FormatException('Not a valid RSA public key.');
  }
  if (key.modulus!.bitLength < kRsaKeyBits) {
    throw const FormatException('Key is too short; 2048-bit RSA or more is required.');
  }
  return der;
}
