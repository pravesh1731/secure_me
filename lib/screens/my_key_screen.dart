import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../crypto/key_backup.dart';
import '../crypto/rsa_keys.dart';
import '../crypto/secure_package.dart';
import '../services/session.dart';
import '../widgets/common.dart';

class MyKeyScreen extends StatelessWidget {
  const MyKeyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final identity = session.identity;
    if (identity == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final pem = publicKeyToPem(identity.publicDer);

    return PageBody(children: [
      _ProfileHeader(session: session, onEdit: () => _editName(context, session)),
      SectionCard(
        title: 'Your public key',
        subtitle: 'Share this with anyone who wants to send you files. It can only lock files, never open them.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.coral.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.fingerprint, color: Brand.coral, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fingerprint', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  FingerprintText(identity.fingerprint, style: theme.textTheme.bodyMedium),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(
            'Compare this with the sender in person or on a call to make sure nobody swapped your key.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Show public key (PEM)'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(pem, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy key'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pem));
                if (context.mounted) showSnack(context, 'Public key copied');
              },
            ),
            Builder(
              builder: (btnContext) => FilledButton.tonalIcon(
                icon: const Icon(Icons.share),
                label: const Text('Share key'),
                onPressed: () {
                  final box = btnContext.findRenderObject() as RenderBox?;
                  SharePlus.instance.share(ShareParams(
                    text: 'My Secure-Me public key (${session.user?.email}):\n\n$pem',
                    subject: 'My Secure-Me public key',
                    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                  ));
                },
              ),
            ),
          ]),
        ]),
      ),
      SectionCard(
        title: 'Security',
        child: Column(children: [
          const _InfoRow(Icons.enhanced_encryption_outlined, 'Encryption', kAlgorithm),
          const _InfoRow(Icons.key_outlined, 'Key pair', 'RSA-$kRsaKeyBits, generated on your device'),
          const _InfoRow(Icons.phonelink_lock_outlined, 'Private key',
              'Stored in this device\'s secure storage. Cloud backup is encrypted with your password '
                  '(PBKDF2-SHA256, $kPbkdf2Iterations iterations + AES-256-GCM).'),
          const _InfoRow(Icons.cloud_off_outlined, 'Your files', 'Never uploaded. Encryption and decryption happen only on your device.'),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password),
            title: const Text('Change password'),
            subtitle: const Text('Also re-encrypts your key backup'),
            onTap: () => _changePassword(context, session),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
            title: Text('Generate new keys', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Use if you think your private key was exposed'),
            onTap: () => _resetKeys(context, session),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('Removes your private key from this device'),
            onTap: () => session.signOut(),
          ),
        ]),
      ),
      const _HowItWorks(),
    ]);
  }

  Future<void> _editName(BuildContext context, Session session) async {
    final controller = TextEditingController(text: session.user?.displayName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await session.updateDisplayName(name);
    } catch (e) {
      if (context.mounted) showSnack(context, describeError(e));
    }
  }

  Future<void> _changePassword(BuildContext context, Session session) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(session: session),
    );
    if (changed == true && context.mounted) showSnack(context, 'Password changed');
  }

  Future<void> _resetKeys(BuildContext context, Session session) async {
    final password = await _askPassword(
      context,
      title: 'Generate new keys?',
      message: 'Files and messages already encrypted for your current key will no longer open. '
          'Contacts will see that your key changed. Enter your password to continue.',
      confirmLabel: 'Generate new keys',
    );
    if (password == null) return;
    try {
      await session.resetKeys(password);
      if (context.mounted) showSnack(context, 'New key pair generated');
    } catch (e) {
      if (context.mounted) showSnack(context, describeError(e));
    }
  }
}

Future<String?> _askPassword(BuildContext context,
    {required String title, required String message, required String confirmLabel}) {
  final controller = TextEditingController();
  final scheme = Theme.of(context).colorScheme;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message),
        const SizedBox(height: 16),
        TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: () => Navigator.pop(ctx, controller.text.isEmpty ? null : controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.session});
  final Session session;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.length < 8) return setState(() => _error = 'Use at least 8 characters.');
    if (_next.text != _confirm.text) return setState(() => _error = 'New passwords do not match.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(current: _current.text, next: _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        const SizedBox(height: 12),
        TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
        const SizedBox(height: 12),
        TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ]),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Change')),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.session, required this.onEdit});
  final Session session;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = session.displayName;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Stack(children: [
        const Positioned.fill(child: HeroGlows()),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Brand.coral, Brand.coralDeep]),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 3),
              ),
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: text.headlineSmall?.copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: text.titleLarge?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(session.user?.email ?? '',
                    style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_user, size: 14, color: Brand.coral),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Keys active on this device',
                        style: text.labelSmall?.copyWith(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Edit name',
              color: Colors.white,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelLarge),
            Text(value, style: theme.textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (Icons.upload_file, 'Choose a message or file'),
    (Icons.person_search, 'Pick the recipient (their public key)'),
    (Icons.enhanced_encryption, 'AES-256-GCM encrypts it with a random one-time key'),
    (Icons.key, 'RSA-OAEP locks that key with the recipient\'s public key'),
    (Icons.inventory_2, 'Both are sealed into one .sme package'),
    (Icons.send, 'Share it any way you like'),
    (Icons.vpn_key, 'Recipient\'s private key unlocks the AES key'),
    (Icons.lock_open, 'AES-GCM decrypts and verifies the original'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('How Secure-Me works'),
        shape: const Border(),
        children: [
          for (final (i, step) in _steps.indexed)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
              title: Text(step.$2),
              trailing: Icon(step.$1, size: 20),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
