import 'package:flutter/foundation.dart';

import 'rsa_keys.dart';
import 'webcrypto_stub.dart' if (dart.library.js_interop) 'webcrypto_web.dart';

/// Generates the user's RSA identity as fast as the platform allows:
/// WebCrypto in browsers, a background isolate everywhere else.
Future<RsaIdentity> generateIdentityFast() async => kIsWeb
    // Derive the public DER the same way restores do, so fingerprints match.
    ? identityFromPrivate(await webGenerateRsaPkcs8(kRsaKeyBits))
    : compute(generateIdentity, kRsaKeyBits);
