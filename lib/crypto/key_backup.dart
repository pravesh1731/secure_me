import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'rsa_keys.dart';

/// Password-wrapped private key, safe to store in Firestore: the server only
/// ever sees PBKDF2 salt + AES-GCM ciphertext.
const int kPbkdf2Iterations = 100000;
const String _backupAlgorithm = 'PBKDF2-HMAC-SHA256 + AES-256-GCM';

final _aesGcm = AesGcm.with256bits();

class WrapRequest {
  const WrapRequest(this.privateDer, this.password);
  final Uint8List privateDer;
  final String password;
}

class UnwrapRequest {
  const UnwrapRequest(this.backup, this.password);
  final Map<String, dynamic> backup;
  final String password;
}

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'The password does not unlock this key backup.';
}

/// Encrypts the private key with a key derived from [req.password].
/// Run via `compute`; PBKDF2 is deliberately slow.
Future<Map<String, dynamic>> wrapPrivateKey(WrapRequest req) async {
  final salt = randomBytes(16);
  final nonce = randomBytes(12);
  final kek = await _deriveKey(req.password, salt, kPbkdf2Iterations);
  final box = await _aesGcm.encrypt(req.privateDer, secretKey: kek, nonce: nonce);
  return {
    'alg': _backupAlgorithm,
    'iterations': kPbkdf2Iterations,
    'salt': base64.encode(salt),
    'iv': base64.encode(nonce),
    'ct': base64.encode(box.concatenation(nonce: false)),
  };
}

/// Returns the private key DER, or throws [WrongPasswordException].
Future<Uint8List> unwrapPrivateKey(UnwrapRequest req) async {
  final b = req.backup;
  final kek = await _deriveKey(
    req.password,
    base64.decode(b['salt'] as String),
    (b['iterations'] as num).toInt(),
  );
  final box = SecretBox.fromConcatenation(
    [...base64.decode(b['iv'] as String), ...base64.decode(b['ct'] as String)],
    nonceLength: 12,
    macLength: 16,
  );
  try {
    return Uint8List.fromList(await _aesGcm.decrypt(box, secretKey: kek));
  } on SecretBoxAuthenticationError {
    throw const WrongPasswordException();
  }
}

Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) =>
    Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
