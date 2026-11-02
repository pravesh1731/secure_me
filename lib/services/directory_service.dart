import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../crypto/rsa_keys.dart';

/// A user whose public key we can encrypt for.
class Recipient {
  const Recipient({
    required this.publicDer,
    this.uid,
    this.displayName = '',
    this.email = '',
  });

  /// Null when the key was pasted rather than looked up.
  final String? uid;
  final String displayName;
  final String email;
  final Uint8List publicDer;

  String get fingerprint => keyFingerprint(publicDer);
  String get label => displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : 'Pasted public key');
}

/// A recipient the user has encrypted for before, with the fingerprint seen
/// at that time so we can warn when their key changes.
class Contact {
  const Contact({required this.uid, required this.displayName, required this.email, required this.fingerprint});
  final String uid;
  final String displayName;
  final String email;
  final String fingerprint;
}

/// Firestore layout:
///   users/{uid}            public profile + public key (readable by signed-in users)
///   users/{uid}/contacts/* recent recipients (owner only)
///   vaults/{uid}           password-wrapped private key (owner only)
///
/// Files are never uploaded; packages are shared by the user directly.
class DirectoryService {
  DirectoryService([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> _vault(String uid) => _db.collection('vaults').doc(uid);

  Future<Map<String, dynamic>?> fetchVault(String uid) async =>
      (await _vault(uid).get()).data()?['backup'] as Map<String, dynamic>?;

  Future<Uint8List?> fetchPublicKey(String uid) async {
    final key = (await _user(uid).get()).data()?['publicKey'] as String?;
    return key == null ? null : base64.decode(key);
  }

  /// Publishes a new identity: public key to the directory, wrapped private
  /// key to the owner-only vault. Written atomically.
  Future<void> publishIdentity({
    required String uid,
    required String email,
    required String displayName,
    required RsaIdentity identity,
    required Map<String, dynamic> backup,
  }) async {
    final batch = _db.batch()
      ..set(_user(uid), {
        'displayName': displayName,
        'email': email,
        'emailLower': email.toLowerCase(),
        'publicKey': base64.encode(identity.publicDer),
        'fingerprint': identity.fingerprint,
        'keyUpdatedAt': FieldValue.serverTimestamp(),
      })
      ..set(_vault(uid), {
        'backup': backup,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
  }

  Future<void> updateVault(String uid, Map<String, dynamic> backup) =>
      _vault(uid).set({'backup': backup, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> updateDisplayName(String uid, String name) =>
      _user(uid).update({'displayName': name});

  Future<Recipient?> findByEmail(String email) async {
    final snap = await _db
        .collection('users')
        .where('emailLower', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _recipientFrom(snap.docs.first);
  }

  Future<Recipient?> findByUid(String uid) async {
    final doc = await _user(uid).get();
    return doc.exists ? _recipientFrom(doc) : null;
  }

  Recipient _recipientFrom(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Recipient(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? '',
      email: d['email'] as String? ?? '',
      publicDer: base64.decode(d['publicKey'] as String),
    );
  }

  Stream<List<Contact>> contacts(String ownerUid) => _user(ownerUid)
      .collection('contacts')
      .orderBy('lastUsed', descending: true)
      .limit(12)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Contact(
                uid: d.id,
                displayName: d['displayName'] as String? ?? '',
                email: d['email'] as String? ?? '',
                fingerprint: d['fingerprint'] as String? ?? '',
              ))
          .toList());

  Future<void> rememberContact(String ownerUid, Recipient r) =>
      _user(ownerUid).collection('contacts').doc(r.uid).set({
        'displayName': r.displayName,
        'email': r.email,
        'fingerprint': r.fingerprint,
        'lastUsed': FieldValue.serverTimestamp(),
      });

  Future<void> forgetContact(String ownerUid, String contactUid) =>
      _user(ownerUid).collection('contacts').doc(contactUid).delete();
}
