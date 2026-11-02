# Secure-Me

Secure-Me is an end-to-end encrypted file-sharing app built with Flutter and Firebase. It runs on Android, iOS, web and macOS.

You can encrypt a text message, image, audio file, video or document for one specific person. The app produces a portable `.sme` package that you can send any way you like: WhatsApp, email or USB. Only the recipient's private key can open it. **Files are never uploaded.** All encryption and decryption happen on the device.

## Features

- Email/password accounts (Firebase Auth).
- A 2048-bit RSA key pair is generated on the device when you sign up.
- A public-key directory in Firestore, so you can find recipients by email or paste any PEM public key.
- Hybrid encryption: AES-256-GCM protects the content and RSA-OAEP (SHA-256) wraps the AES key.
- Integrity verification. The GCM tag covers the whole package, including its header, and a SHA-256 hash of the original is checked as well.
- Text messages can also be copied as an armored text block, so you can paste them into a chat.
- Key fingerprints let users confirm a key out-of-band, and the app warns you when a contact's key has changed.
- The private key is backed up encrypted with your password (PBKDF2 + AES-GCM), so the same key works on every device you sign in on.
- Change password (the backup is re-encrypted), forgotten-password recovery, and key rotation.

## Workflow

```
Choose file → Choose recipient → AES-256-GCM encrypt (random key)
           → RSA-OAEP wraps the AES key with the recipient's public key
           → .sme package → share it any way you like
Recipient  → RSA-OAEP unwrap with private key → AES-GCM decrypt + verify → original file
```

## The `.sme` package format

| Bytes | Content |
|---|---|
| 8 | Magic `SECUREME` |
| 1 | Version (`1`) |
| 4 | Header length (big-endian) |
| n | Header JSON: `alg`, recipient key fingerprint `rfp`, RSA-wrapped AES key `ek`, GCM nonce `iv` |
| rest | AES-256-GCM ciphertext and 16-byte tag. The AAD is every byte above. |

The encrypted plaintext is `metaLength | meta JSON | content`. The metadata holds the file name, MIME type, size, SHA-256, creation time and sender. As a result, even the original file name is hidden; packages are always named `secure-<timestamp>.sme`.

The format uses standard primitives only. A test in `test/` confirms that OpenSSL-generated keys work, and a package was decrypted independently with Node/OpenSSL (RSA-OAEP-SHA256 with MGF1-SHA256, then AES-256-GCM).

## Project structure

```
lib/
  crypto/
    rsa_keys.dart        RSA key generation, DER/PEM, fingerprints
    keygen*.dart         WebCrypto key generation on web, background isolate elsewhere
    secure_package.dart  .sme encrypt/decrypt, text armor
    key_backup.dart      password-wrapped private key (PBKDF2 + AES-GCM)
  services/
    session.dart         auth + key lifecycle (sign-up, unlock, reset, change password)
    directory_service.dart  Firestore: public keys, key vault, recent contacts
    local_key_store.dart secure on-device key storage
    file_io.dart         pick / save / share files
  screens/               auth, unlock, encrypt, decrypt, my key
firestore.rules          security rules
```

## Firestore data

| Path | Contents | Who can read it |
|---|---|---|
| `users/{uid}` | name, email, public key, fingerprint | any signed-in user (one at a time) |
| `users/{uid}/contacts/*` | recent recipients | owner only |
| `vaults/{uid}` | private key encrypted with the user's password | owner only |

The security rules stop anyone from publishing a profile under an email address that isn't their own verified sign-in email.

## Running it

Firebase project: `secure-me-06k3q`. It is already configured in `lib/firebase_options.dart`.

1. **One-time step:** in the [Firebase console → Authentication](https://console.firebase.google.com/project/secure-me-06k3q/authentication/providers), click **Get started** and enable **Email/Password**.
2. Run the app:
   ```bash
   flutter pub get
   flutter run -d chrome     # or: -d macos, an Android device/emulator, an iOS simulator
   flutter test              # crypto tests (native)
   flutter test --platform chrome test/web_crypto_test.dart   # WebCrypto path in a real browser
   ```
3. To redeploy the security rules: `firebase deploy --only firestore`
4. Optional web hosting: `flutter build web && firebase deploy --only hosting`

### Version notes

- `firebase_auth` is held below 6.6 and `firebase_core` below 4.14. Newer versions need Flutter 3.38 or later on iOS. After you upgrade Flutter, you can move to `firebase_core ^5`, `firebase_auth ^7` and `cloud_firestore ^7`.
- Minimum OS versions: Android 6.0 (API 23), iOS 15 and macOS 12.

## Security notes and limits

- Files are processed in memory, so the maximum size is 100 MB.
- The sender's name inside a package is what the sender claims. It is not signed, and the app labels it that way. Digital signatures are listed as future scope in the synopsis.
- If you forget your password and reset it, you can still unlock your key backup with the old password. Otherwise you have to generate new keys, and packages sent to your old key can no longer be opened. This is deliberate: the server can never recover your key.
