import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pointycastle/export.dart' hide Mac;

import 'rsa_keys.dart';
import 'webcrypto_stub.dart' if (dart.library.js_interop) 'webcrypto_web.dart';

/// Secure-Me package (.sme) layout:
///
/// ```
/// "SECUREME"            8 bytes magic
/// version               1 byte  (= 1)
/// headerLength          4 bytes big-endian
/// header                UTF-8 JSON (public: algorithm, recipient
///                       fingerprint, RSA-OAEP wrapped AES key, GCM nonce)
/// ciphertext + tag      AES-256-GCM, AAD = every byte above
/// ```
///
/// The plaintext sealed by AES-GCM is `metaLength (4 bytes) | meta JSON |
/// content`, so the file name, type and sender are hidden too. Because the
/// header is the AAD, tampering with any byte of the package (header or
/// body) makes decryption fail.
const List<int> _magic = [0x53, 0x45, 0x43, 0x55, 0x52, 0x45, 0x4D, 0x45];
const int _version = 1;
const String kAlgorithm = 'RSA-OAEP-SHA256 + AES-256-GCM';
const String kPackageExtension = 'sme';

const String _armorBegin = '-----BEGIN SECURE-ME MESSAGE-----';
const String _armorEnd = '-----END SECURE-ME MESSAGE-----';

/// Largest input we accept; everything is processed in memory.
const int kMaxPayloadBytes = 100 * 1024 * 1024;

enum PayloadKind { text, file }

class PackageException implements Exception {
  const PackageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the package was sealed for a different public key.
class NotForYouException extends PackageException {
  const NotForYouException(this.recipientFingerprint)
      : super('This package was encrypted for a different recipient.');
  final String recipientFingerprint;
}

class SenderInfo {
  const SenderInfo({required this.name, required this.email, required this.fingerprint});
  final String name;
  final String email;
  final String fingerprint;

  Map<String, dynamic> toJson() => {'name': name, 'email': email, 'fp': fingerprint};
  factory SenderInfo.fromJson(Map<String, dynamic> j) => SenderInfo(
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        fingerprint: j['fp'] as String? ?? '',
      );
}

class EncryptRequest {
  const EncryptRequest({
    required this.kind,
    required this.content,
    required this.fileName,
    required this.mimeType,
    required this.recipientPublicDer,
    required this.sender,
  });
  final PayloadKind kind;
  final Uint8List content;
  final String fileName;
  final String mimeType;
  final Uint8List recipientPublicDer;
  final SenderInfo sender;
}

class DecryptRequest {
  const DecryptRequest({required this.package, required this.identity});
  final Uint8List package;
  final RsaIdentity identity;
}

class DecryptedPayload {
  const DecryptedPayload({
    required this.kind,
    required this.content,
    required this.fileName,
    required this.mimeType,
    required this.sha256,
    required this.createdAt,
    required this.sender,
  });
  final PayloadKind kind;
  final Uint8List content;
  final String fileName;
  final String mimeType;
  final String sha256;
  final DateTime createdAt;
  final SenderInfo sender;

  String get text => utf8.decode(content);
}

/// AES-GCM from `package:cryptography`: WebCrypto in browsers, optimised
/// Dart elsewhere (pointycastle's GCM is ~10x slower).
final _aesGcm = AesGcm.with256bits();

/// Hybrid-encrypts [req.content] for the recipient. Run via `compute`.
Future<Uint8List> encryptPackage(EncryptRequest req) async {
  if (req.content.length > kMaxPayloadBytes) {
    throw const PackageException('File is larger than the 100 MB limit.');
  }

  // 1. Fresh random AES-256 key and 96-bit GCM nonce for this package only.
  final aesKey = randomBytes(32);
  final nonce = randomBytes(12);

  // 2. Wrap the AES key with the recipient's RSA public key (OAEP, SHA-256).
  final wrappedKey = kIsWeb
      ? await webRsaOaepEncrypt(req.recipientPublicDer, aesKey)
      : (OAEPEncoding.withSHA256(RSAEngine())
            ..init(true, PublicKeyParameter<RSAPublicKey>(decodePublicKey(req.recipientPublicDer))))
          .process(aesKey);

  final header = utf8.encode(jsonEncode({
    'alg': kAlgorithm,
    'rfp': keyFingerprint(req.recipientPublicDer),
    'ek': base64.encode(wrappedKey),
    'iv': base64.encode(nonce),
  }));
  final prefix = BytesBuilder(copy: false)
    ..add(_magic)
    ..addByte(_version)
    ..add(_uint32(header.length))
    ..add(header);
  final aad = prefix.toBytes();

  // 3. Inner plaintext: metadata (incl. SHA-256 of the original) + content.
  final meta = utf8.encode(jsonEncode({
    'kind': req.kind.name,
    'name': req.fileName,
    'mime': req.mimeType,
    'size': req.content.length,
    'sha256': await _sha256Hex(req.content),
    'created': DateTime.now().toUtc().toIso8601String(),
    'sender': req.sender.toJson(),
  }));
  final plain = (BytesBuilder(copy: false)
        ..add(_uint32(meta.length))
        ..add(meta)
        ..add(req.content))
      .toBytes();

  // 4. AES-256-GCM, authenticating the public header as AAD.
  final box = await _aesGcm.encrypt(plain, secretKey: SecretKey(aesKey), nonce: nonce, aad: aad);

  return (BytesBuilder(copy: false)
        ..add(aad)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .toBytes();
}

/// Reverses [encryptPackage] with the recipient's private key. Run via
/// `compute`. Throws [PackageException] with a user-facing message.
Future<DecryptedPayload> decryptPackage(DecryptRequest req) async {
  final data = req.package;
  if (data.length < 13 || !_startsWithMagic(data)) {
    throw const PackageException('Not a Secure-Me package.');
  }
  if (data[8] != _version) {
    throw PackageException('Unsupported package version ${data[8]}.');
  }
  final headerLength = ByteData.sublistView(data, 9, 13).getUint32(0);
  final headerEnd = 13 + headerLength;
  if (headerEnd > data.length) {
    throw const PackageException('Package is truncated or corrupted.');
  }

  final Map<String, dynamic> header;
  try {
    header = jsonDecode(utf8.decode(data.sublist(13, headerEnd))) as Map<String, dynamic>;
  } catch (_) {
    throw const PackageException('Package header is corrupted.');
  }
  final recipientFp = header['rfp'] as String? ?? '';
  if (recipientFp != req.identity.fingerprint) {
    throw NotForYouException(recipientFp);
  }

  // 1. Recover the AES key with our RSA private key.
  final Uint8List aesKey;
  try {
    final wrapped = base64.decode(header['ek'] as String);
    aesKey = kIsWeb
        ? await webRsaOaepDecrypt(req.identity.privateDer, wrapped)
        : (OAEPEncoding.withSHA256(RSAEngine())
              ..init(false, PrivateKeyParameter<RSAPrivateKey>(req.identity.privateKey)))
            .process(wrapped);
  } catch (_) {
    throw const PackageException('Could not unlock the file key with your private key.');
  }

  // 2. AES-GCM decrypt; the tag check covers header + body integrity.
  if (data.length < headerEnd + 16) {
    throw const PackageException('Package is truncated or corrupted.');
  }
  final Uint8List plain;
  try {
    final box = SecretBox(
      Uint8List.sublistView(data, headerEnd, data.length - 16),
      nonce: base64.decode(header['iv'] as String),
      mac: Mac(Uint8List.sublistView(data, data.length - 16)),
    );
    plain = Uint8List.fromList(await _aesGcm.decrypt(
      box,
      secretKey: SecretKey(aesKey),
      aad: Uint8List.sublistView(data, 0, headerEnd),
    ));
  } on SecretBoxAuthenticationError {
    throw const PackageException(
        'Integrity check failed: the package was modified or corrupted.');
  }

  final metaLength = ByteData.sublistView(plain, 0, 4).getUint32(0);
  final meta = jsonDecode(utf8.decode(plain.sublist(4, 4 + metaLength))) as Map<String, dynamic>;
  final content = Uint8List.fromList(plain.sublist(4 + metaLength));

  // 3. Independent SHA-256 check of the recovered original.
  final digest = await _sha256Hex(content);
  if (digest != meta['sha256']) {
    throw const PackageException('Integrity check failed: SHA-256 mismatch.');
  }

  return DecryptedPayload(
    kind: PayloadKind.values.byName(meta['kind'] as String),
    content: content,
    fileName: meta['name'] as String,
    mimeType: meta['mime'] as String,
    sha256: digest,
    createdAt: DateTime.parse(meta['created'] as String).toLocal(),
    sender: SenderInfo.fromJson(meta['sender'] as Map<String, dynamic>),
  );
}

/// Recipient fingerprint from a package header, without decrypting.
String? peekRecipientFingerprint(Uint8List data) {
  try {
    if (!_startsWithMagic(data)) return null;
    final headerLength = ByteData.sublistView(data, 9, 13).getUint32(0);
    final header = jsonDecode(utf8.decode(data.sublist(13, 13 + headerLength)));
    return header['rfp'] as String?;
  } catch (_) {
    return null;
  }
}

/// Text form of a package, for pasting into chat apps or email.
String armorPackage(Uint8List package) {
  final b64 = base64.encode(package);
  final lines = <String>[];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  return '$_armorBegin\n${lines.join('\n')}\n$_armorEnd';
}

/// Parses text produced by [armorPackage]. Bare base64 is accepted too.
Uint8List dearmorPackage(String text) {
  final body = text
      .replaceAll(_armorBegin, '')
      .replaceAll(_armorEnd, '')
      .replaceAll(RegExp(r'\s'), '');
  try {
    final bytes = base64.decode(body);
    if (!_startsWithMagic(bytes)) throw const FormatException();
    return bytes;
  } on FormatException {
    throw const PackageException('That text is not a Secure-Me encrypted message.');
  }
}

bool isArmored(String text) => text.contains(_armorBegin);

bool _startsWithMagic(Uint8List data) {
  if (data.length < _magic.length) return false;
  for (var i = 0; i < _magic.length; i++) {
    if (data[i] != _magic[i]) return false;
  }
  return true;
}

/// SHA-256 via `package:cryptography` (WebCrypto in browsers).
Future<String> _sha256Hex(List<int> data) async {
  final digest = await Sha256().hash(data);
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _uint32(int value) => (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
