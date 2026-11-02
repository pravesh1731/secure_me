import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'decrypt_screen.dart';
import 'encrypt_screen.dart';
import 'my_key_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.lock_outline, selected: Icons.lock, label: 'Encrypt'),
    (icon: Icons.lock_open_outlined, selected: Icons.lock_open, label: 'Decrypt'),
    (icon: Icons.key_outlined, selected: Icons.key, label: 'My key'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    // IndexedStack keeps each tab's in-progress state when switching.
    final body = IndexedStack(
      index: _index,
      children: const [EncryptScreen(), DecryptScreen(), MyKeyScreen()],
    );

    final session = SessionScope.of(context);
    final name = session.displayName;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          AppLogo(size: 34),
          SizedBox(width: 10),
          BrandWordmark(),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'My key',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _index = 2),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Brand.coral, Brand.coralDeep]),
                  ),
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: Text(d.label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
                ],
              ),
            ),
    );
  }
}
