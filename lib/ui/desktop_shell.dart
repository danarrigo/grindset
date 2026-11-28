import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Persistent desktop navigation around the minimal timer and workspaces.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.destinations,
    required this.child,
    this.attention,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final List<({String label, IconData icon})> destinations;
  final Widget child;

  /// The destination that needs a look, marked with a dot.
  final int? attention;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < destinations.length; i++)
          LogicalKeySet(LogicalKeyboardKey.control, keys[i]): () =>
              onSelected(i),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                Container(
                  width: 208,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      right: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          primary: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'Grindset',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              const SizedBox(height: 28),
                              for (var i = 0; i < destinations.length; i++) ...[
                                Semantics(
                                  selected: selected == i,
                                  child: Tooltip(
                                    message:
                                        '${destinations[i].label}${attention == i ? ', needs attention' : ''} (Ctrl+${i + 1})',
                                    child: TextButton.icon(
                                      key: ValueKey('nav-$i'),
                                      onPressed: () => onSelected(i),
                                      icon: Icon(
                                        destinations[i].icon,
                                        size: 21,
                                      ),
                                      label: Row(
                                        children: [
                                          Expanded(
                                            child: Text(destinations[i].label),
                                          ),
                                          if (attention == i)
                                            Container(
                                              key: const ValueKey(
                                                'nav-attention',
                                              ),
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: colors.error,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      style: TextButton.styleFrom(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 14,
                                        ),
                                        foregroundColor: selected == i
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                        backgroundColor: selected == i
                                            ? colors.surfaceContainerHighest
                                            : Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Ctrl + 1-5 to navigate',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
