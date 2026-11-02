import 'package:flutter/material.dart';

import '../services/session.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = SessionScope.read(context);
    try {
      if (_signUp) {
        await session.signUp(name: _name.text, email: _email.text, password: _password.text);
      } else {
        await session.signIn(email: _email.text, password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Reset password?',
      message: 'We will email a reset link to $email.\n\n'
          'Your private key backup is locked with your current password. After a reset you '
          'can still unlock it with the old password, or create new keys (old packages '
          'sent to you will then no longer open).',
      confirmLabel: 'Send link',
    );
    if (!ok || !mounted) return;
    try {
      await SessionScope.read(context).sendPasswordReset(email);
      if (mounted) showSnack(context, 'Password reset email sent.');
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          const _AuthHero(),
          Transform.translate(
            offset: const Offset(0, -40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Brand.navy.withValues(alpha: 0.12), blurRadius: 32, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(child: _buildForm(theme)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
          child: Column(
            key: ValueKey(_signUp),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_signUp ? 'Create your account' : 'Welcome back', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                _signUp ? 'Your encryption keys are generated on this device.' : 'Sign in to open and send secure files.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Sign in'), icon: Icon(Icons.login)),
            ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_alt)),
          ],
          selected: {_signUp},
          onSelectionChanged: _loading ? null : (s) => setState(() {
            _signUp = s.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 20),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _signUp
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
          validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Enter your password';
            if (_signUp && v!.length < 8) return 'Use at least 8 characters';
            return null;
          },
          onFieldSubmitted: _signUp ? null : (_) => _submit(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _signUp
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => v == _password.text ? null : 'Passwords do not match',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  const Notice(
                    icon: Icons.key_outlined,
                    text: 'A 2048-bit RSA key pair is generated on this device. Your private key is '
                        'backed up only in encrypted form, locked with your password; nobody else, '
                        'including the server, can read it.',
                  ),
                ])
              : const SizedBox(width: double.infinity),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Notice(icon: Icons.error_outline, text: _error!, tone: NoticeTone.error),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: _loading
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_signUp ? 'Create account' : 'Sign in'),
        ),
        const SizedBox(height: 4),
        if (!_signUp)
          TextButton(onPressed: _loading ? null : _forgotPassword, child: const Text('Forgot password?'))
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

/// Navy banner with the logo, full width with a rounded bottom edge.
class _AuthHero extends StatelessWidget {
  const _AuthHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Stack(children: [
        const Positioned.fill(child: HeroGlows()),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 72),
            child: Column(children: [
              const AppLogo(size: 88),
              const SizedBox(height: 16),
              BrandWordmark(onDark: true, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'End-to-end encrypted file sharing',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
