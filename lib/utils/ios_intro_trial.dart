part of '../utils.dart';

class IosIntroTrial {
  static const _ch = MethodChannel('intro_offer_bridge');

  static Future<bool> isEligibleIos(String productId) async {
    if (!Platform.isIOS) return false;
    try {
      return await _ch.invokeMethod<bool>('isEligible', productId) ?? false;
    } on PlatformException {
      return false;
    }
  }
}
