import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/rsa_keys.dart';
import '../crypto/secure_package.dart';
import '../services/directory_service.dart';
import '../services/file_io.dart';
import '../services/session.dart';
import '../widgets/common.dart';

enum _RecipientMode { user, key }

class EncryptScreen extends StatefulWidget {
  const EncryptScreen({super.key});

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  PayloadKind _kind = PayloadKind.text;
  final _message = TextEditingController();
  PickedFile? _file;

  _RecipientMode _mode = _RecipientMode.user;
  final _email = TextEditingController();
  final _pastedKey = TextEditingController();
  Recipient? _recipient;
  String? _recipientError;
  bool _searching = false;

  /// Fingerprint remembered from a previous send, if it differs now.
  String? _keyChangedFrom;

  bool _encrypting = false;
  _Result? _result;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    _pastedKey.dispose();
    super.dispose();
  }

  bool get _hasContent => _kind == PayloadKind.text ? _message.text.trim().isNotEmpty : _file != null;

  Future<void> _pickFile() async {
    try {
      final f = await pickFile();
      if (f == null) return;
      if (f.bytes.length > kMaxPayloadBytes) {
        if (mounted) showSnack(context, 'That file is larger than the 100 MB limit.');
        return;
      }
      setState(() => _file = f);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open file: ${describeError(e)}');
    }
  }

  Future<void> _findByEmail([String? email]) async {
    final query = (email ?? _email.text).trim();
    if (!query.contains('@')) {
      setState(() => _recipientError = 'Enter the recipient\'s email address.');
      return;
    }
    if (email != null) _email.text = email;
    setState(() {
      _searching = true;
      _recipientError = null;
      _recipient = null;
      _keyChangedFrom = null;
    });
    try {
      final found = await SessionScope.read(context).directory.findByEmail(query);
      if (!mounted) return;
      setState(() {
        _recipient = found;
        if (found == null) _recipientError = 'No Secure-Me user with that email. Ask them to sign up, or paste their public key.';
      });
    } catch (e) {
      if (mounted) setState(() => _recipientError = describeError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectContact(Contact c) async {
    await _findByEmail(c.email);
    if (_recipient != null && _recipient!.fingerprint != c.fingerprint) {
      setState(() => _keyChangedFrom = c.fingerprint);
    }
  }

  void _selectSelf() {
    final s = SessionScope.read(context);
    setState(() {
      _email.text = s.user!.email!;
      _recipientError = null;
      _keyChangedFrom = null;
      _recipient = Recipient(
        uid: s.user!.uid,
        displayName: '${s.displayName} (me)',
        email: s.user!.email!,
        publicDer: s.identity!.publicDer,
      );
    });
  }

  void _onKeyPasted(String text) {
    setState(() {
      _keyChangedFrom = null;
      if (text.trim().isEmpty) {
        _recipient = null;
        _recipientError = null;
        return;
      }
      try {
        _recipient = Recipient(publicDer: parsePublicKeyInput(text));
        _recipientError = null;
      } on FormatException catch (e) {
        _recipient = null;
        _recipientError = e.message;
      }
    });
  }

  Future<void> _encrypt() async {
    final session = SessionScope.read(context);
    final recipient = _recipient!;
    final content = _kind == PayloadKind.text
        ? Uint8List.fromList(utf8.encode(_message.text))
        : _file!.bytes;
    setState(() => _encrypting = true);
    // Give the progress indicator a frame before the (possibly inline) work.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final package = await compute(
        encryptPackage,
        EncryptRequest(
          kind: _kind,
          content: content,
          fileName: _kind == PayloadKind.text ? 'message.txt' : _file!.name,
          mimeType: _kind == PayloadKind.text ? 'text/plain' : _file!.mimeType,
          recipientPublicDer: recipient.publicDer,
          sender: SenderInfo(
            name: session.user?.displayName ?? '',
            email: session.user?.email ?? '',
            fingerprint: session.identity!.fingerprint,
          ),
        ),
      );
      if (recipient.uid != null && recipient.uid != session.user!.uid) {
        session.directory.rememberContact(session.user!.uid, recipient).ignore();
      }
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      setState(() => _result = _Result(
            package: package,
            // Deliberately generic: the real file name is inside the encryption.
            fileName: 'secure-$stamp.$kPackageExtension',
            recipient: recipient,
            isText: _kind == PayloadKind.text,
          ));
    } catch (e) {
      if (mounted) showSnack(context, 'Encryption failed: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _encrypting = false);
    }
  }

  void _startOver() {
    setState(() {
      _result = null;
      _message.clear();
      _file = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _ResultView(result: _result!, onDone: _startOver);
    final canEncrypt = _hasContent && _recipient != null && !_encrypting;
    final firstName = SessionScope.of(context).displayName.split(RegExp(r'[\s@]')).first;

    return PageBody(children: [
      GradientHeader(
        title: firstName.isEmpty ? 'Hi there' : 'Hi, $firstName',
        subtitle: 'What would you like to protect today?',
        trailing: const IllustrationCircle(
          size: 84,
          tint: Brand.coral,
          child: BrandAnimation(LottieAssets.send, size: 84),
        ),
      ),
      SectionCard(
        step: 1,
        title: 'What do you want to protect?',
        subtitle: 'Text messages, images, audio, video or documents (up to 100 MB).',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<PayloadKind>(
            segments: const [
              ButtonSegment(value: PayloadKind.text, label: Text('Message'), icon: Icon(Icons.chat_bubble_outline)),
              ButtonSegment(value: PayloadKind.file, label: Text('File'), icon: Icon(Icons.attach_file)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == PayloadKind.text)
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(hintText: 'Type your secret message…', alignLabelWithHint: true),
            )
          else if (_file == null)
            _DropZone(onTap: _pickFile)
          else
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              leading: Icon(iconForMime(_file!.mimeType), size: 32),
              title: Text(_file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatBytes(_file!.bytes.length)} · ${_file!.mimeType}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Change', icon: const Icon(Icons.swap_horiz), onPressed: _pickFile),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _file = null)),
              ]),
            ),
        ]),
      ),
      SectionCard(
        step: 2,
        title: 'Who should be able to open it?',
        subtitle: 'The file is locked with the recipient\'s public key. Only their private key can open it.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<_RecipientMode>(
            segments: const [
              ButtonSegment(value: _RecipientMode.user, label: Text('Find user'), icon: Icon(Icons.person_search_outlined)),
              ButtonSegment(value: _RecipientMode.key, label: Text('Paste key'), icon: Icon(Icons.key_outlined)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _recipient = null;
              _recipientError = null;
              _keyChangedFrom = null;
              if (_mode == _RecipientMode.key) _onKeyPasted(_pastedKey.text);
            }),
          ),
          const SizedBox(height: 16),
          if (_mode == _RecipientMode.user) ..._buildUserLookup() else ..._buildKeyPaste(),
          if (_recipientError != null) ...[
            const SizedBox(height: 12),
            Notice(icon: Icons.info_outline, text: _recipientError!, tone: NoticeTone.warning),
          ],
          if (_recipient != null) ...[
            const SizedBox(height: 12),
            _RecipientTile(recipient: _recipient!),
          ],
          if (_keyChangedFrom != null) ...[
            const SizedBox(height: 8),
            const Notice(
              icon: Icons.warning_amber_rounded,
              tone: NoticeTone.warning,
              text: 'This person\'s key has changed since you last sent them something. '
                  'Confirm the new fingerprint with them before sending sensitive data.',
            ),
          ],
        ]),
      ),
      FilledButton.icon(
        onPressed: canEncrypt ? _encrypt : null,
        icon: _encrypting
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.enhanced_encryption_outlined),
        label: Text(_encrypting ? 'Encrypting…' : 'Encrypt'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
      const SizedBox(height: 12),
      Text(
        'AES-256-GCM encrypts the content with a one-time key, and RSA-OAEP locks that key for the recipient.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ]);
  }

  List<Widget> _buildUserLookup() {
    final session = SessionScope.of(context);
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Recipient email',
          prefixIcon: const Icon(Icons.alternate_email),
          suffixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.search), onPressed: _findByEmail),
        ),
        onSubmitted: (_) => _findByEmail(),
      ),
      const SizedBox(height: 12),
      StreamBuilder<List<Contact>>(
        stream: session.directory.contacts(session.user!.uid),
        builder: (context, snap) {
          final contacts = snap.data ?? const [];
          return Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.person, size: 18), label: const Text('Myself'), onPressed: _selectSelf),
            for (final c in contacts)
              InputChip(
                avatar: CircleAvatar(child: Text(_initial(c.displayName.isNotEmpty ? c.displayName : c.email))),
                label: Text(c.displayName.isNotEmpty ? c.displayName : c.email),
                onPressed: () => _selectContact(c),
                onDeleted: () => session.directory.forgetContact(session.user!.uid, c.uid),
                deleteButtonTooltipMessage: 'Remove from recent',
              ),
          ]);
        },
      ),
    ];
  }

  List<Widget> _buildKeyPaste() => [
        TextField(
          controller: _pastedKey,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            hintText: '-----BEGIN PUBLIC KEY-----\n…\n-----END PUBLIC KEY-----',
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text == null) return;
                _pastedKey.text = data!.text!;
                _onKeyPasted(_pastedKey.text);
              },
            ),
          ),
          onChanged: _onKeyPasted,
        ),
      ];
}

String _initial(String s) => s.isEmpty ? '?' : s.characters.first.toUpperCase();

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Brand.coral.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: Brand.coral.withValues(alpha: 0.6), radius: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.coral.withValues(alpha: 0.14)),
                child: const Icon(Icons.cloud_upload_outlined, size: 28, color: Brand.coral),
              ),
              const SizedBox(height: 12),
              Text('Tap to choose a file', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('Images, audio, video or documents',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 12, children: [
                for (final i in [Icons.image_outlined, Icons.audiotrack_outlined, Icons.movie_outlined, Icons.description_outlined])
                  Icon(i, size: 18, color: scheme.onSurfaceVariant),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({required this.recipient});
  final Recipient recipient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          child: recipient.uid == null ? const Icon(Icons.key) : Text(_initial(recipient.label)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(recipient.label, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            if (recipient.email.isNotEmpty && recipient.email != recipient.label)
              Text(recipient.email, style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 2),
            FingerprintText(recipient.fingerprint, groups: 8,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
          ]),
        ),
        Icon(Icons.verified_user_outlined, color: scheme.onPrimaryContainer),
      ]),
    );
  }
}

class _Result {
  const _Result({required this.package, required this.fileName, required this.recipient, required this.isText});
  final Uint8List package;
  final String fileName;
  final Recipient recipient;
  final bool isText;
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onDone});
  final _Result result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Text armor is handy for chat apps, but only sensible for small packages.
    final canCopy = result.package.length < 256 * 1024;
    return PageBody(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const BrandAnimation(LottieAssets.success, size: 140, repeat: false),
            Text('Encrypted', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Only ${result.recipient.label} can open this package with their private key.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              leading: const Icon(Icons.lock, size: 32),
              title: Text(result.fileName),
              subtitle: Text('${formatBytes(result.package.length)} · $kAlgorithm'),
            ),
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Save file'),
                onPressed: () async {
                  try {
                    if (await saveBytes(result.package, result.fileName) && context.mounted) {
                      showSnack(context, 'Saved ${result.fileName}');
                    }
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Could not save: ${describeError(e)}');
                  }
                },
              ),
              Builder(
                builder: (btnContext) => FilledButton.tonalIcon(
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                  onPressed: () => shareBytes(btnContext, result.package, result.fileName, 'application/octet-stream')
                      .catchError((Object e) {
                    if (context.mounted) showSnack(context, 'Could not share: ${describeError(e)}');
                  }),
                ),
              ),
              if (result.isText && canCopy)
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy as text'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: armorPackage(result.package)));
                    if (context.mounted) showSnack(context, 'Encrypted message copied. Paste it into any chat.');
                  },
                ),
            ]),
          ]),
        ),
      ),
      const Notice(
        icon: Icons.info_outline,
        text: 'Send this file any way you like (WhatsApp, email, USB). It is never uploaded to our servers, '
            'and it is useless to anyone except the recipient.',
      ),
      const SizedBox(height: 16),
      TextButton.icon(onPressed: onDone, icon: const Icon(Icons.add), label: const Text('Encrypt something else')),
    ]);
  }
}
