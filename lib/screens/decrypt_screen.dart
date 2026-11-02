import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/secure_package.dart';
import '../services/file_io.dart';
import '../services/session.dart';
import '../widgets/common.dart';

class DecryptScreen extends StatefulWidget {
  const DecryptScreen({super.key});

  @override
  State<DecryptScreen> createState() => _DecryptScreenState();
}

class _DecryptScreenState extends State<DecryptScreen> {
  final _armored = TextEditingController();
  bool _showPaste = false;
  bool _working = false;
  String? _sourceName;
  DecryptedPayload? _payload;
  Object? _error;

  @override
  void dispose() {
    _armored.dispose();
    super.dispose();
  }

  Future<void> _openFile() async {
    try {
      final f = await pickFile();
      if (f == null) return;
      await _decrypt(f.bytes, f.name);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open file: ${describeError(e)}');
    }
  }

  Future<void> _decryptPasted() async {
    var text = _armored.text;
    if (text.trim().isEmpty) {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      _armored.text = text;
    }
    try {
      await _decrypt(dearmorPackage(text), 'Pasted message');
    } on PackageException catch (e) {
      setState(() {
        _error = e;
        _payload = null;
      });
    }
  }

  Future<void> _decrypt(Uint8List bytes, String source) async {
    final identity = SessionScope.read(context).identity!;
    setState(() {
      _working = true;
      _error = null;
      _payload = null;
      _sourceName = source;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final payload = await compute(decryptPackage, DecryptRequest(package: bytes, identity: identity));
      if (mounted) setState(() => _payload = payload);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _clear() => setState(() {
        _payload = null;
        _error = null;
        _sourceName = null;
        _armored.clear();
      });

  @override
  Widget build(BuildContext context) {
    return PageBody(children: [
      const GradientHeader(
        title: 'Open something sent to you',
        subtitle: 'Decrypted on this device with your private key, and checked for tampering.',
        trailing: IllustrationCircle(size: 84, child: BrandAnimation(LottieAssets.unlock, size: 84)),
      ),
      SectionCard(
        title: 'Open an encrypted package',
        subtitle: 'Choose a .sme file someone sent you, or paste an encrypted text message. '
            'It is decrypted on this device with your private key.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: _working ? null : _openFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose .sme file'),
            ),
            OutlinedButton.icon(
              onPressed: _working ? null : () => setState(() => _showPaste = !_showPaste),
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste encrypted text'),
            ),
          ]),
          if (_showPaste) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _armored,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '-----BEGIN SECURE-ME MESSAGE-----\n…\n-----END SECURE-ME MESSAGE-----',
                helperText: 'Leave empty to use the clipboard',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _working ? null : _decryptPasted,
                icon: const Icon(Icons.lock_open),
                label: const Text('Decrypt text'),
              ),
            ),
          ],
        ]),
      ),
      if (_working)
        const Card(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 16, 32, 28),
            child: Column(children: [
              BrandAnimation(LottieAssets.unlock, size: 140),
              Text('Decrypting and verifying integrity…'),
              SizedBox(height: 16),
              LinearProgressIndicator(),
            ]),
          ),
        ),
      if (_error != null) _ErrorView(error: _error!, sourceName: _sourceName, onDismiss: _clear),
      if (_payload != null) _PayloadView(payload: _payload!, onClose: _clear),
    ]);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.sourceName, required this.onDismiss});
  final Object error;
  final String? sourceName;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final message = e is PackageException ? e.message : describeError(e);
    return Notice(
      icon: e is NotForYouException ? Icons.no_encryption_gmailerrorred_outlined : Icons.gpp_bad_outlined,
      tone: NoticeTone.error,
      text: sourceName == null ? message : '$sourceName: $message',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (e is NotForYouException) ...[
          const Text('Only the holder of this key can open it:'),
          FingerprintText(e.recipientFingerprint, groups: 8),
        ],
        TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
      ]),
    );
  }
}

class _PayloadView extends StatelessWidget {
  const _PayloadView({required this.payload, required this.onClose});
  final DecryptedPayload payload;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = payload;
    final isText = p.kind == PayloadKind.text;
    final isImage = p.mimeType.startsWith('image/');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Notice(
        icon: Icons.verified,
        tone: NoticeTone.success,
        text: 'Decrypted and verified',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Check('Encrypted for your key (fingerprint matches)'),
          const _Check('RSA-OAEP: file key unlocked with your private key'),
          const _Check('AES-256-GCM authentication tag valid (not tampered)'),
          _Check('SHA-256 matches: ${p.sha256.substring(0, 16)}…'),
        ]),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(iconForMime(p.mimeType)),
              const SizedBox(width: 8),
              Expanded(child: Text(isText ? 'Secret message' : p.fileName, style: theme.textTheme.titleMedium)),
              IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close)),
            ]),
            Text(
              '${formatBytes(p.content.length)} · ${p.mimeType} · encrypted ${_formatDate(p.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (isText)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(p.text, style: theme.textTheme.bodyLarge),
              )
            else if (isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: Image.memory(
                    p.content,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('Preview not available for this image type.'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              if (isText)
                FilledButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.text));
                    if (context.mounted) showSnack(context, 'Message copied');
                  },
                ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.download),
                label: Text(isText ? 'Save as .txt' : 'Save file'),
                onPressed: () async {
                  try {
                    if (await saveBytes(p.content, p.fileName) && context.mounted) {
                      showSnack(context, 'Saved ${p.fileName}');
                    }
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Could not save: ${describeError(e)}');
                  }
                },
              ),
              Builder(
                builder: (btnContext) => OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open / Share'),
                  onPressed: () => shareBytes(btnContext, p.content, p.fileName, p.mimeType).catchError((Object e) {
                    if (context.mounted) showSnack(context, 'Could not share: ${describeError(e)}');
                  }),
                ),
              ),
            ]),
          ]),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(p.sender.name.isNotEmpty ? p.sender.name : p.sender.email),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.sender.name.isNotEmpty) Text(p.sender.email),
            const SizedBox(height: 4),
            Text(
              'Sender as stated inside the package. Anyone with your public key can create a package, '
              'so confirm unexpected files with the sender.',
              style: theme.textTheme.bodySmall,
            ),
          ]),
          isThreeLine: true,
        ),
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  const _Check(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(Icons.check_circle, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color))),
      ]),
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
