/// Invalidates in-flight ad loads when consent or the no-ads state changes.
///
/// Google Mobile Ads does not expose cancellation for all load operations.
/// Callers capture [generation] before starting a load and must dispose a
/// loaded ad when [isCurrent] is false.
class AdLoadGate {
  bool _requestAllowed = false;
  bool _disabled = false;
  int _generation = 0;

  int get generation => _generation;
  bool get canUseAds => _requestAllowed && !_disabled;

  void setRequestAllowed(bool value) {
    if (_requestAllowed == value) return;
    _requestAllowed = value;
    if (!value) _generation++;
  }

  void setDisabled(bool value) {
    if (_disabled == value) return;
    _disabled = value;
    if (value) _generation++;
  }

  bool isCurrent(int loadGeneration) =>
      canUseAds && loadGeneration == _generation;
}

/// Returns whether another attempt remains after [failedAttempts] failures.
bool shouldRetryAdLoad({
  required int failedAttempts,
  required int maxFailedLoadAttempts,
}) => failedAttempts < maxFailedLoadAttempts;
