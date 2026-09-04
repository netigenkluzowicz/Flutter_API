## Unreleased (proposal 2026-09-04, Netigen Tools / Recorder)

- App Open on foreground follows AdMob guidance without per-app workarounds:
  - shown only for a `resumed` that follows `paused` (a genuine switch back to
    the app), not after a permission dialog, the UMP form, an iOS alert or
    any other overlay that only makes the app `inactive`;
  - suppressed by the package around interstitial and rewarded ads, the store
    purchase sheet (`buyNonConsumable`, also when cancelled), `requestConsent`
    and `showPrivacyOptionsForm`;
  - optional `minIntervalSinceFullscreenAd` (also
    `initAdsParameters(appOpenAdMinIntervalSinceFullscreenAd:)`) measured from
    the last impression of any fullscreen format; zero keeps old behaviour.
- New `runWithoutAppOpenAd` / `beginAppOpenSuppression` scopes for system UI
  opened by the application (share sheet, permission, settings).
- `suppressNextAppOpenOnForeground` is now bounded by a timeout (default
  5 min) so a launch that never emits `resumed` cannot swallow a later real
  return from background.
- `showInterstitialAd` ignores a concurrent call while a show is in flight;
  previously the second call replaced the first caller's callbacks and its
  future never completed. A `show()` exception now completes the callbacks.
- `AppOpenForegroundPolicy` and its tests cover the foreground rules.
- Banner ads follow UMP centrally: `setBannerAdsAllowed`, `enableBannerAd` and
  `disableBannerAd` mirror the other formats and are wired into `showConsent`,
  the startup ads platform and `PaymentService`, so a premium entitlement
  verified during a session hides a mounted banner immediately instead of only
  after the next start. `README.md` documents the split: the package enforces
  consent and the no-ads entitlement, `enabled` is the application's placement
  decision. A mounted `AdaptiveBannerAd` now disposes its
  ad as soon as consent is withdrawn, instead of trusting the application's
  `enabled` flag alone. The `AdaptiveBannerAd(enabled:)` signature is
  unchanged.
- Overlapping `showConsent` calls share one execution, so the UMP form is
  never presented twice; `MobileAds.instance.initialize()` runs once even when
  two callers race. A sequential call still runs again, so a retry after a
  network error works.
- `disposeAppOpenAd` no longer resets the shared foreground policy, which
  would have cleared suppression scopes owned by the interstitial, rewarded,
  payment or consent code.
- App Open callbacks keep the state they started with, so re-initialising the
  format while an ad is on screen no longer leaks a suppression scope.
- `PaymentService.dispose()` closes the suppression scope of a purchase that
  is still in flight.
- A failing `RewardedAd.show()` is caught, so it no longer leaves an unhandled
  asynchronous error and a suppression scope open until its timeout.
- Nested suppression scopes track the foreground events they swallowed
  separately, so a scope opened inside another one still gets its own grace
  window for the late `resumed` that belongs to it.

### Migration note

If an application wrapped `showInterstitialAd()` in `try/catch` to report a
failed show to an external crash reporter, that catch no longer runs: a
`show()` exception is now turned into the normal `onStartCallback` /
`onEndCallback` sequence and logged inside the package.

## 3.45.0+0

- Add `StartupAdsCoordinator`: a testable, app-agnostic premium → UMP →
  optional App Open stage that does not own paywall UI or wait for a cold ad
  load.
- Expose UMP privacy options and explicit App Open completion/suppression
  outcomes for startup flow control.
- Add `SubscriptionOfferDetails` and `PaymentService.subscriptionOfferById` for
  paywall-ready store metadata, including free-trial period and Play offer token.
- Preserve app-configured interstitial continuation/cooldown and disable cached
  App Open, interstitial, and rewarded ads after verified no-ads entitlement.

## 3.44.0+1

- Require Flutter 3.44 and Dart 3.12.
- Upgrade Google Mobile Ads to 9.1 and Google Play Billing integration to
  Billing Library 8 through `in_app_purchase_android 0.5.2`.
- Use the current UMP request-update and load/show-if-required flow.
- Add the official UMP privacy options entry point.
- Prevent interstitial and rewarded ad loading until UMP allows ad requests.
- Add a large anchored adaptive banner widget with correct disposal.
- Select Android subscription trials by base plan and offer tag and pass the
  selected offer token to the billing flow.
- Require application-provided purchase verification and remove the hard-coded
  App Store verification endpoint.
- Fix stale loading and pending purchase state.
- Add initial offer-selection tests and integration guidance.

## 3.32.8+2

- Previous shared implementation used by existing Netigen applications.
