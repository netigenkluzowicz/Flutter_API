import 'package:shared_preferences/shared_preferences.dart';

/// The startup route selected for one application session.
enum StartupMonetizationAction { paywall, appOpen }

/// Selects whether a launch should use a startup paywall or an App Open ad.
///
/// The default schedule is empty, so all launches select [appOpen]. Entries
/// less than one are ignored. This keeps configuration assembled from remote
/// or user-provided values safe without changing a valid launch decision.
class StartupMonetizationPolicy {
  const StartupMonetizationPolicy({this.paywallLaunches = const <int>{}});

  /// Launch counts on which [StartupMonetizationAction.paywall] is selected.
  final Set<int> paywallLaunches;

  /// Returns the startup action for [launchCount].
  ///
  /// Non-positive launch counts select [StartupMonetizationAction.appOpen].
  StartupMonetizationAction actionForLaunch(int launchCount) {
    if (launchCount <= 0) return StartupMonetizationAction.appOpen;
    return paywallLaunches.contains(launchCount)
        ? StartupMonetizationAction.paywall
        : StartupMonetizationAction.appOpen;
  }
}

/// Storage used by [StartupLaunchCounter].
///
/// Applications can provide an implementation for migrations or tests. The
/// [storageKey] is supplied by the counter so a single store can host multiple
/// independent counters.
abstract interface class StartupLaunchStorage {
  Future<int?> readLaunchCount(String storageKey);
  Future<void> writeLaunchCount(String storageKey, int launchCount);
}

/// A [StartupLaunchStorage] backed by [SharedPreferencesAsync].
class SharedPreferencesStartupLaunchStorage implements StartupLaunchStorage {
  SharedPreferencesStartupLaunchStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<int?> readLaunchCount(String storageKey) =>
      _preferences.getInt(storageKey);

  @override
  Future<void> writeLaunchCount(String storageKey, int launchCount) =>
      _preferences.setInt(storageKey, launchCount);
}

/// Persists a launch count once for the lifetime of this counter instance.
///
/// Call [beginSession] once while constructing an application-level session or
/// startup controller. Repeated calls, including concurrent calls, return the
/// same result and do not increment storage again. A normal foreground/resume
/// event therefore does not create another launch.
///
/// When reading or writing storage fails, [beginSession] returns `1` for this
/// instance without writing a replacement value. This documented fail-safe
/// lets the application select its most conservative startup flow and avoids
/// reporting a storage write as successful when it was not.
class StartupLaunchCounter {
  StartupLaunchCounter({
    StartupLaunchStorage? storage,
    this.storageKey = defaultStorageKey,
  }) : _storage = storage ?? SharedPreferencesStartupLaunchStorage() {
    if (storageKey.trim().isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey', 'must not be empty');
    }
  }

  /// Default key shared by applications that do not require a namespace.
  static const String defaultStorageKey =
      'flutter_api.startup_monetization.launch_count';

  final StartupLaunchStorage _storage;

  /// Key used by this counter in its [StartupLaunchStorage].
  final String storageKey;

  Future<int>? _sessionStart;

  /// Begins this instance's session and returns its persistent launch count.
  Future<int> beginSession() => _sessionStart ??= _beginSessionOnce();

  Future<int> _beginSessionOnce() async {
    try {
      final storedCount = await _storage.readLaunchCount(storageKey);
      final launchCount = (storedCount == null || storedCount < 0)
          ? 1
          : storedCount + 1;
      await _storage.writeLaunchCount(storageKey, launchCount);
      return launchCount;
    } on Object {
      return 1;
    }
  }
}
