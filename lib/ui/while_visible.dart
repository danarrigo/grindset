import 'package:flutter/foundation.dart';

/// Passes on [source]'s changes only while [visible] is true, and one change
/// when it becomes true again if any were held back. A window hidden in the
/// tray then does no UI work, while everything else keeps listening to
/// [source] directly.
class WhileVisible extends ChangeNotifier {
  WhileVisible(this.source, this.visible) {
    source.addListener(_changed);
    visible.addListener(_shown);
  }

  final Listenable source;
  final ValueListenable<bool> visible;
  bool _missed = false;

  void _changed() {
    if (visible.value) {
      notifyListeners();
    } else {
      _missed = true;
    }
  }

  void _shown() {
    if (visible.value && _missed) {
      _missed = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    source.removeListener(_changed);
    visible.removeListener(_shown);
    super.dispose();
  }
}
