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
