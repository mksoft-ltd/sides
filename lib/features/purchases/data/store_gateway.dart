import 'package:in_app_purchase/in_app_purchase.dart';

/// The slice of the native `in_app_purchase` plugin the app uses.
///
/// A seam because `InAppPurchase` is a concrete class with no interface and
/// touching `InAppPurchase.instance` registers the platform channel. The real
/// gateway is created only in `main()`; tests use a fake that emits real
/// [PurchaseDetails] objects on [purchaseStream], which is the only place the
/// plugin reports how a purchase ended.
abstract class StoreGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);

  /// Only reports that the payment sheet was presented. The outcome
  /// (purchased, cancelled, error, pending) arrives on [purchaseStream].
  Future<bool> buyNonConsumable(ProductDetails product);
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails details);
}

class NativeStoreGateway implements StoreGateway {
  NativeStoreGateway() : _iap = InAppPurchase.instance;
  final InAppPurchase _iap;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;
  @override
  Future<bool> isAvailable() => _iap.isAvailable();
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);
  @override
  Future<bool> buyNonConsumable(ProductDetails product) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  @override
  Future<void> restorePurchases() => _iap.restorePurchases();
  @override
  Future<void> completePurchase(PurchaseDetails details) =>
      _iap.completePurchase(details);
}
