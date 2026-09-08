import 'dart:math';

/// مولّد معرّفات فريدة بسيط (بدون الاعتماد على حزم خارجية).
class IdGen {
  static final Random _random = Random();
  static int _counter = 0;

  static String next([String prefix = 'id']) {
    _counter = (_counter + 1) % 100000;
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = _random.nextInt(0xFFFFFF);
    return '${prefix}_${now.toRadixString(36)}_${rand.toRadixString(36)}_$_counter';
  }
}
