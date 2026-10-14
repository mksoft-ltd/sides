import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show PurchaseStateWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart'
    show GooglePlayPurchaseDetails;

import '../../../core/config/app_config.dart';
import '../../../core/storage/settings_store.dart';
import '../data/store_gateway.dart';

/// Overridden in `main()` with [NativeStoreGateway] and in tests with a fake.
final Provider<StoreGateway> storeGatewayProvider = Provider<StoreGateway>(
  (Ref ref) => throw UnimplementedError('storeGatewayProvider not overridden'),
);

/// Whether to ask the store for past purchases at launch and on resume.
///
/// True on Play only: Android never replays a purchase that completed while
/// the app was closed, and Play refunds an unacknowledged purchase after
/// three days. StoreKit redelivers unfinished transactions itself, and an
/// unprompted restore there can raise a sign-in sheet.
final Provider<bool> reconcileAtLaunchProvider = Provider<bool>(
  (Ref ref) => defaultTargetPlatform == TargetPlatform.android,
);

/// One-shot notices for the settings screen.
enum AdFreeNotice {
  purchased,
  restored,
  nothingToRestore,
  cancelled,
  failed,
  pending,
  storeUnavailable,
}

@immutable
class AdFreeState {
  const AdFreeState({
    required this.owned,
    this.busy = false,
    this.storeAvailable = false,
    this.price,
    this.notice,
    this.noticeSerial = 0,
  });

  /// The cached entitlement; ads are hidden the moment this is true.
  final bool owned;

  /// A purchase or restore is in progress.
  final bool busy;
  final bool storeAvailable;

  /// The store's own localised price string; never formatted locally.
  final String? price;

  final AdFreeNotice? notice;

  /// Increments with every notice so two identical notices both show.
  final int noticeSerial;

  AdFreeState copyWith({
    bool? owned,
    bool? busy,
    bool? storeAvailable,
    String? price,
    AdFreeNotice? notice,
  }) =>
      AdFreeState(
        owned: owned ?? this.owned,
        busy: busy ?? this.busy,
        storeAvailable: storeAvailable ?? this.storeAvailable,
        price: price ?? this.price,
        notice: notice ?? this.notice,
        noticeSerial: notice == null ? noticeSerial : noticeSerial + 1,
      );
}

/// The one-time ad-free unlock on the native `in_app_purchase` plugin.
///
/// The plugin reports outcomes only on its purchase stream; `buy` returns
/// as soon as the sheet is up. So cancel/error/pending all clear [busy]
/// from the stream handler, and [busy] has a ceiling in case nothing ever
/// arrives (a permanently spinning button reads as a broken app in review).
class AdFreeController extends Notifier<AdFreeState> {
  static const String ownedKey = 'ad_free_owned';
  static const Duration busyCeiling = Duration(seconds: 75);
  static const Duration restoreWindow = Duration(seconds: 4);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  Timer? _busyTimer;
  bool _restoring = false;
  bool _restoreFound = false;

  StoreGateway get _store => ref.read(storeGatewayProvider);

  @override
  AdFreeState build() {
    final bool owned =
        ref.read(settingsStoreProvider).getBool(ownedKey) ?? false;
    // Subscribe now, not on the first buy: a purchase that completed while
    // the app was closed is delivered in the first frames after launch.
    _sub = _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) => _finish(AdFreeNotice.failed),
    );
    ref.onDispose(() {
      _sub?.cancel();
      _busyTimer?.cancel();
    });
    Future<void>.microtask(_init);
    return AdFreeState(owned: owned);
  }

  Future<void> _init() async {
    if (!ref.mounted) return;
    await _loadProduct();
    if (!ref.mounted) return;
    if (ref.read(reconcileAtLaunchProvider)) await _silentReconcile();
  }

  Future<void> _loadProduct() async {
    try {
      final bool available = await _store.isAvailable();
      if (!ref.mounted) return;
      if (!available) {
        state = state.copyWith(storeAvailable: false);
        return;
      }
      final ProductDetailsResponse r =
          await _store.queryProductDetails(<String>{AppConfig.adFreeProductId});
      if (!ref.mounted) return;
      _product = r.productDetails
          .where((ProductDetails p) => p.id == AppConfig.adFreeProductId)
          .firstOrNull;
      state = state.copyWith(
        storeAvailable: _product != null,
        price: _product?.price,
      );
    } on Object catch (e) {
      debugPrint('Store query failed: $e');
      if (ref.mounted) state = state.copyWith(storeAvailable: false);
    }
  }

  /// Android: re-query owned purchases on launch/resume. Also the retry path
  /// for an acknowledgement Play rejected (completePurchase hides failures).
  Future<void> _silentReconcile() async {
    try {
      if (!await _store.isAvailable()) return;
      await _store.restorePurchases();
    } on Object catch (e) {
      debugPrint('Reconcile failed: $e');
    }
  }

  Future<void> onResumed() async {
    if (!ref.read(reconcileAtLaunchProvider)) return;
    if (_product == null) await _loadProduct();
    await _silentReconcile();
  }

  Future<void> buy() async {
    if (state.owned || state.busy) return;
    if (_product == null) await _loadProduct();
    final ProductDetails? product = _product;
    if (product == null) {
      _finish(AdFreeNotice.storeUnavailable);
      return;
    }
    _setBusy();
    try {
      final bool started = await _store.buyNonConsumable(product);
      if (!started) _finish(AdFreeNotice.failed);
    } on Object catch (e) {
      debugPrint('Purchase failed to start: $e');
      _finish(AdFreeNotice.failed);
    }
  }

  Future<void> restore() async {
    if (state.busy) return;
    _setBusy();
    _restoring = true;
    _restoreFound = false;
    try {
      if (!await _store.isAvailable()) {
        _restoring = false;
        _finish(AdFreeNotice.storeUnavailable);
        return;
      }
      await _store.restorePurchases();
      // No "that was everything" signal exists on either store: listen for
      // a short window, then report what turned up.
      await Future<void>.delayed(restoreWindow);
    } on Object catch (e) {
      debugPrint('Restore failed: $e');
    }
    if (!ref.mounted) return;
    final bool found = _restoreFound;
    _restoring = false;
    if (!found) _finish(AdFreeNotice.nothingToRestore);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final PurchaseDetails p in list) {
      if (p.productID != AppConfig.adFreeProductId) {
        if (p.pendingCompletePurchase) await _complete(p);
        continue;
      }
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (_isPlayPending(p)) {
            _finish(AdFreeNotice.pending);
            break;
          }
          final bool wasOwned = state.owned;
          // Persist the entitlement before finishing the transaction.
          await ref.read(settingsStoreProvider).setBool(ownedKey, true);
          if (p.pendingCompletePurchase) await _complete(p);
          if (!ref.mounted) return;
          if (_restoring) _restoreFound = true;
          state = state.copyWith(owned: true);
          if (!wasOwned || state.busy) {
            _finish(
              p.status == PurchaseStatus.purchased
                  ? AdFreeNotice.purchased
                  : AdFreeNotice.restored,
            );
          }
        case PurchaseStatus.pending:
          // Ask to Buy or a slow Play payment method: may outlast the
          // session. Clear busy so Restore stays usable.
          _finish(AdFreeNotice.pending);
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _complete(p);
          _finish(AdFreeNotice.cancelled);
        case PurchaseStatus.error:
          if (p.pendingCompletePurchase) await _complete(p);
          if ((p.error?.message ?? '').contains('itemAlreadyOwned')) {
            // An error carries no receipt; let restore deliver the grant.
            unawaited(_store.restorePurchases());
            break;
          }
          _finish(AdFreeNotice.failed);
      }
    }
  }

  /// Play reports a purchase still awaiting payment as `restored` after a
  /// restore; only the billing-client state tells the truth. A type guard,
  /// so it is simply false on iOS.
  bool _isPlayPending(PurchaseDetails p) =>
      p is GooglePlayPurchaseDetails &&
      p.billingClientPurchase.purchaseState == PurchaseStateWrapper.pending;

  Future<void> _complete(PurchaseDetails p) async {
    try {
      await _store.completePurchase(p);
    } on Object catch (e) {
      // Retried by the next reconcile, which re-delivers it unacknowledged.
      debugPrint('completePurchase failed: $e');
    }
  }

  void _setBusy() {
    _busyTimer?.cancel();
    _busyTimer = Timer(busyCeiling, () {
      if (ref.mounted && state.busy) state = state.copyWith(busy: false);
    });
    state = state.copyWith(busy: true);
  }

  void _finish(AdFreeNotice notice) {
    _busyTimer?.cancel();
    if (!ref.mounted) return;
    state = state.copyWith(busy: false, notice: notice);
  }
}

final NotifierProvider<AdFreeController, AdFreeState> adFreeControllerProvider =
    NotifierProvider<AdFreeController, AdFreeState>(AdFreeController.new);

/// Narrow read for the banner slots: rebuilds only when ownership flips.
final Provider<bool> adFreeOwnedProvider = Provider<bool>(
  (Ref ref) =>
      ref.watch(adFreeControllerProvider.select((AdFreeState s) => s.owned)),
);
