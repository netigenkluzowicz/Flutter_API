# Flutter API

Shared Flutter services used by Netigen tools. The package provides:

- Google UMP consent and an optional iOS ATT request,
- consent-gated interstitial, rewarded, and adaptive banner ads,
- in-app purchase and subscription orchestration,
- deterministic Google Play base-plan and introductory-offer selection,
- reusable Netigen web, intro, and survey screens.

## Requirements

- Flutter 3.44 or newer
- Dart 3.12 or newer
- Android projects compatible with Google Play Billing Library 8
- platform configuration for Google Mobile Ads and in-app purchases

Always depend on an immutable release tag. Do not depend on `main`.

```yaml
flutter_api:
  git:
    url: https://github.com/netigenkluzowicz/Flutter_API.git
    ref: <release-tag>
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

