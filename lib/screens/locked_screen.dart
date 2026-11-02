import 'package:flutter/material.dart';

import '../crypto/key_backup.dart';
import '../services/session.dart';
import '../widgets/common.dart';

/// Shown when signed in but the private key isn't on this device: restores
/// it from the encrypted backup, or lets the user start over with new keys.
class LockedScreen extends StatefulWidget {
  const LockedScreen({super.key});

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  final _password = TextEditingController();
  final _previous = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _previous.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(Session s) action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action(SessionScope.read(context));
    } on WrongPasswordException {
      if (mounted) {
        setState(() => _error = _previous.text.isEmpty
            ? 'Your key backup is locked with a different password. If you reset your password, enter the old one below.'
            : 'The previous password did not unlock the backup either.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _unlock() {
    if (_password.text.isEmpty) return setState(() => _error = 'Enter your account password.');
    _run((s) => s.unlock(
          password: _password.text,
          previousPassword: _previous.text.isEmpty ? null : _previous.text,
        ));
  }

  Future<void> _reset() async {
    if (_password.text.isEmpty) return setState(() => _error = 'Enter your account password first.');
    final ok = await confirmDialog(
      context,
      title: 'Create new keys?',
      message: 'A new key pair will replace your current one. Anything encrypted for your old '
          'key can never be decrypted again. Only do this if you cannot recover your old password.',
      confirmLabel: 'Create new keys',
      destructive: true,
    );
    if (ok) _run((s) => s.resetKeys(_password.text));
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final theme = Theme.of(context);
    final mismatch = session.backupPasswordMismatch;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: IllustrationCircle(size: 180, child: BrandAnimation(LottieAssets.unlock, size: 180)),
                  ),
                  const SizedBox(height: 24),
                  Text('Unlock your private key', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Signed in as ${session.user?.email ?? ''}. Enter your password to restore your '
                    'private key on this device.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Account password', prefixIcon: Icon(Icons.lock_outline)),
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (mismatch) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _previous,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Previous password',
                        helperText: 'The password you had before resetting it',
                        prefixIcon: Icon(Icons.history),
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Notice(icon: Icons.error_outline, text: _error!, tone: NoticeTone.error),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loading ? null : _unlock,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Unlock'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  ),
                  if (mismatch) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Forgot old password: create new keys'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => _run((s) => s.signOut()),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
