# Flutter API

Shared Flutter services used by Netigen tools. The package provides:

- Google UMP consent and an optional iOS ATT request,
- consent-gated interstitial, rewarded, and adaptive banner ads,
- in-app purchase and subscription orchestration,
- deterministic Google Play base-plan and introductory-offer selection,
- a non-blocking startup ads coordinator (premium → UMP → optional App Open),
- reusable Netigen web, intro, and survey screens.

## Requirements

- Flutter 3.44 or newer
- Dart 3.12 or newer
- Android projects compatible with Google Play Billing Library 8
- platform configuration for Google Mobile Ads and in-app purchases

Use the release tag as the human-readable version identifier and pin production
dependencies to the full immutable release commit SHA. Do not depend on `main`.

```yaml
flutter_api:
  git:
    url: https://github.com/netigenkluzowicz/Flutter_API.git
    ref: <full-release-commit-sha> # release tag: v3.45.0+0
```

## Privacy and ads

Call `initAdsParameters` to configure ad unit IDs. It does not initialize the
Mobile Ads SDK or load an ad. Then call `showConsent` after the splash screen.
The SDK starts and the first interstitial can load only if a fresh UMP update
returns `canRequestAds == true`.

Applications must:

- show a visible Privacy choices setting when
  `privacyOptionsRequired == true`,
- call `AdConsent.showPrivacyOptionsForm()` from that setting,
- pass `adsCanRequest && !premiumUser` to `AdaptiveBannerAd.enabled`,
- use interstitials only at natural transitions,
- provide their own privacy policy, Google Play Data Safety answers, and Apple
  App Privacy disclosures.

UMP is consent infrastructure; it does not by itself make an application legally
compliant.

`AdaptiveBannerAd` has no global cache: when a verified premium state causes
the application to rebuild it with `enabled: false`, the widget immediately
disposes any loaded `BannerAd` and renders nothing.

## Startup ads, paywalls, and navigation

Use `StartupAdsCoordinator` for the advertising stage only. It never shows a
paywall, so applications remain free to decide paywall-versus-content after
startup ads have finished. See the complete Vibration Meter-oriented example in
[`examples/startup_ads_coordinator.md`](examples/startup_ads_coordinator.md).

Its result contains the final `AdConsentResult`, `privacyOptionsRequired`, and
an explicit completion reason. It waits for an App Open only when a preloaded
ad is actually shown; unavailable ads continue immediately.

- Vibration Meter: premium check → UMP → ready App Open → application paywall
  → content; its interstitial cooldown can be configured as 120 seconds.
- Decibel Meter: premium check → UMP → app-specific `allowAppOpen` → its own
  paywall/content decision.
- Equalizer: use an app-specific value-first `allowAppOpen` policy, then route
  to content after this coordinator finishes.

## Purchases and subscriptions

`PaymentService.initParameters` requires a verification callback. Production
applications must validate purchase tokens or signed transactions with a
trusted backend. The package no longer contains a hard-coded verification
endpoint and does not approve purchases by default.

Google Play trials are selected by base plan and, optionally, an offer tag:

```dart
final trial = PaymentService.instance.trialProductById(
  'premium_yearly',
  basePlanId: 'annual',
  offerTag: 'free-trial',
);
```

For paywall rendering, use `subscriptionOfferById`. It exposes the store
product reference, Play base plan/offer/tag/token, recurring formatted price
and period, plus free-trial metadata. `matchesFreeTrial(Duration(days: 3))`
checks a product-specific three-day trial without making three days a library
default.

The 3-day trial is configured in Google Play / App Store. Flutter_API reads and
validates real store-offer metadata; it never hardcodes a trial duration or
price.

When buying a `GooglePlayProductDetails`, the corresponding `offerToken` is
passed through `GooglePlayPurchaseParam`. Trial duration and renewal price are
configured in Play Console or App Store Connect and must be displayed clearly
by the application's paywall.

Local StoreKit 2 expiration parsing remains available only as an explicit
compatibility option. Remote verification is the default.

## Testing

Use Google's test ad unit IDs in debug builds and Play/App Store sandbox
accounts for purchases. At minimum, applications should cover:

- consent required, not required, unavailable, and privacy-options flows,
- premium users never loading ads,
- trial and regular offer selection,
- purchase pending, canceled, invalid, restored, expired, and refunded states.
