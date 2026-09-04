import 'dart:async';

/// Coalesces concurrent callers of an asynchronous operation into one run.
///
/// A call made while one is already running shares its result instead of
/// starting a second one. Nothing is cached beyond that: once the operation
/// completes, with a value or an error, the next call starts a fresh attempt,
/// so a user-triggered retry is never stuck replaying a stale failure.
///
/// This differs on purpose from a run-once memoization such as
/// `StartupAdsCoordinator.run`, which keeps its result for the lifetime of the
/// object.
class SingleFlight<T> {
  Future<T>? _inFlight;

  /// Runs [operation], or joins the one already in flight.
  Future<T> run(Future<T> Function() operation) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = operation();
    _inFlight = future;
    // The error of a failed operation belongs to the callers of [run]; this
    // bookkeeping listener must not report it a second time as an unhandled
    // asynchronous error.
    future
        .whenComplete(() {
          if (identical(_inFlight, future)) _inFlight = null;
        })
        .ignore();
    return future;
  }
}
