import Flutter
import StoreKit

public class IntroOfferBridge: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "intro_offer_bridge",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(IntroOfferBridge(), channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "isEligible",
          let productId = call.arguments as? String
    else { result(FlutterMethodNotImplemented); return }

    // iOS 15 +
    guard #available(iOS 15.0, *) else { result(false); return }

    Task { @MainActor in
      do {
        guard
          let product = try await Product.products(for: [productId]).first,
          let groupID = product.subscription?.subscriptionGroupID
        else { result(false); return }

        let ok = try await Product.SubscriptionInfo
                      .isEligibleForIntroOffer(for: groupID)

        result(ok)
      } catch {
        result(FlutterError(code: "NATIVE_ERROR",
                            message: error.localizedDescription,
                            details: nil))
      }
    }
  }
}
