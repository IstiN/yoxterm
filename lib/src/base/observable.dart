mixin Observable {
  // A List, not a Set: terminals notify on every written chunk, and the Set's
  // iterator allocation showed up per notify under output floods. Dedupe on
  // add (listeners are few) and notify with an indexed loop (no iterator).
  final listeners = <void Function()>[];

  void addListener(void Function() listener) {
    if (!listeners.contains(listener)) {
      listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) {
    listeners.remove(listener);
  }

  void notifyListeners() {
    // Indexed loop on purpose: no per-notify iterator allocation.
    for (var i = 0; i < listeners.length; i++) {
      listeners[i]();
    }
  }
}
