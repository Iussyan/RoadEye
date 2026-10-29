import 'dart:async';

import '../models/recognition.dart';

/// Single-flight inference: frames arriving while busy are dropped, not queued.
/// Epochs prevent old-camera or pre-pause results appearing after a transition.
class LiveDetectionController {
  LiveDetectionController({
    required this.onResult,
    required this.onError,
    this.maxBoxAge = const Duration(milliseconds: 1500),
  });

  final void Function(List<Recognition>, Duration) onResult;
  final void Function(Object) onError;
  final Duration maxBoxAge;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;
  Timer? _expiry;
  Completer<void>? _idle;

  bool get isBusy => _busy;
  Future<void> get idle => _idle?.future ?? Future<void>.value();

  Future<void> submit(Future<List<Recognition>> Function() infer) async {
    if (_busy || _disposed) return;
    _busy = true;
    _idle = Completer<void>();
    final epoch = _epoch;
    final watch = Stopwatch()..start();
    try {
      final result = await infer();
      if (_disposed || epoch != _epoch) return;
      final elapsed = watch.elapsed;
      _expiry?.cancel();
      if (elapsed >= maxBoxAge) {
        onResult(const [], elapsed);
      } else {
        onResult(result, elapsed);
        _expiry = Timer(maxBoxAge - elapsed, () {
          if (!_disposed && epoch == _epoch) onResult(const [], elapsed);
        });
      }
    } catch (error) {
      if (!_disposed && epoch == _epoch) onError(error);
    } finally {
      _busy = false;
      _idle?.complete();
      _idle = null;
    }
  }

  void invalidate() {
    _epoch++;
    _expiry?.cancel();
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
