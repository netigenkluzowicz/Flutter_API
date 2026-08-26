# Startup ads integration (Vibration Meter)

Flutter_API owns only consent and the optional startup App Open stage. The app
owns splash navigation and its paywall.

```dart
// Safe before UMP: this only configures App Open; it does not load an ad.
initAppOpenAd(adUnitId: appOpenUnitId);
await initInterstitialAd(
  adUnitId: interstitialUnitId,
  minIntervalBetweenAdsInSecs: 120,
);

final startup = StartupAdsCoordinator.mobileAds(
  premiumCheck: () async => PaymentService.instance.premiumUser,
);
final result = await startup.run(allowAppOpen: appPolicyAllowsAppOpen);

if (result.premiumUser) {
  showVibrationMeter();
  return;
}

// This is application UI/policy, not Flutter_API policy.
if (shouldShowPaywallForThisLaunch) {
  showPaywall();
} else {
  showVibrationMeter();
}
```

`run` completes immediately if a preloaded App Open ad is unavailable; it does
not wait for its network load. If it is shown, it completes after dismissal or
failure. The implementation consumes foreground suppression so closing that
fullscreen ad cannot trigger another App Open immediately.

At a natural user transition, navigation is always safe after the returned
future completes:

```dart
await showInterstitialAd(onEndCallback: openHistory);
```

The 120-second interval belongs to this app's `initInterstitialAd` call; it is
not a Flutter_API global default.

Show a visible Settings entry only when `result.privacyOptionsRequired` is
true, and invoke `await AdConsent().showPrivacyOptionsForm()` from it.

For a three-day Play trial, select and verify store metadata rather than
hard-coding product behaviour:

```dart
final offer = PaymentService.instance.subscriptionOfferById(
  'premium_yearly',
  basePlanId: 'annual',
  offerTag: 'free-trial',
  requiresFreeTrial: true,
);
if (offer == null || !offer.matchesFreeTrial(const Duration(days: 3))) {
  throw StateError('The configured Play offer is not the expected trial.');
}
await PaymentService.instance.buyNonConsumable(offer.productDetails);
```
