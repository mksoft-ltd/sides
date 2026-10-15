import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/core/storage/settings_store.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';

import '../helpers/fakes.dart';

/// Records whether the entitlement was already persisted when the store was
/// told the transaction was finished.
class OrderRecordingStore extends FakeStoreGateway {
  OrderRecordingStore(this.settings);
  final InMemorySettingsStore settings;
  final List<bool?> ownedAtCompletion = <bool?>[];

  @override
  Future<void> completePurchase(PurchaseDetails details) async {
    ownedAtCompletion.add(settings.getBool(AdFreeController.ownedKey));
    await super.completePurchase(details);
  }
}

/// A Play purchase in the given billing-client [state].
GooglePlayPurchaseDetails playPurchase(
  PurchaseStateWrapper state,
  PurchaseStatus status,
) =>
    GooglePlayPurchaseDetails(
      purchaseID: 'GPA.1',
      productID: AppConfig.adFreeProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 'token',
        source: 'google_play',
      ),
      transactionDate: '1760480000000',
      status: status,
      billingClientPurchase: PurchaseWrapper(
        orderId: 'GPA.1',
        packageName: 'com.froggyeye.sides',
        purchaseTime: 1760480000000,
        purchaseToken: 'token',
        signature: 'sig',
        products: const <String>[AppConfig.adFreeProductId],
        isAutoRenewing: false,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: state,
      ),
    );

void main() {
  late FakeStoreGateway store;
  late InMemorySettingsStore settings;

  ProviderContainer make({bool reconcile = false}) {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        storeGatewayProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWithValue(settings),
        reconcileAtLaunchProvider.overrideWithValue(reconcile),
      ],
    );
    addTearDown(c.dispose);
    c.read(adFreeControllerProvider);
    return c;
  }

  PurchaseDetails p(PurchaseStatus s, {String? error}) =>
      FakeStoreGateway.purchase(AppConfig.adFreeProductId, s,
          errorMessage: error);

  setUp(() {
    store = FakeStoreGateway();
    settings = InMemorySettingsStore();
  });

  test('loads the store price; nothing owned by default', () async {
    final ProviderContainer c = make();
    await pumpEventQueue();
    final AdFreeState s = c.read(adFreeControllerProvider);
    expect(s.owned, isFalse);
    expect(s.storeAvailable, isTrue);
    expect(s.price, '£2.99');
  });

  test('purchase: persisted before completion, then owned + notice', () async {
    final ProviderContainer c = make();
    await pumpEventQueue();
    await c.read(adFreeControllerProvider.notifier).buy();
    expect(c.read(adFreeControllerProvider).busy, isTrue);

    store.emit(p(PurchaseStatus.purchased));
    await pumpEventQueue();

    final AdFreeState s = c.read(adFreeControllerProvider);
    expect(s.owned, isTrue);
    expect(s.busy, isFalse);
    expect(s.notice, AdFreeNotice.purchased);
    expect(settings.getBool(AdFreeController.ownedKey), isTrue);
    expect(store.completed, hasLength(1));
  });

  test('cancel arrives on the stream and clears busy', () async {
    final ProviderContainer c = make();
    await pumpEventQueue();
    await c.read(adFreeControllerProvider.notifier).buy();
    store.emit(p(PurchaseStatus.canceled));
    await pumpEventQueue();
    final AdFreeState s = c.read(adFreeControllerProvider);
    expect(s.busy, isFalse);
    expect(s.owned, isFalse);
    expect(s.notice, AdFreeNotice.cancelled);
  });

  test('pending clears busy and keeps Restore usable', () async {
    final ProviderContainer c = make();
    await pumpEventQueue();
    await c.read(adFreeControllerProvider.notifier).buy();
    store.emit(p(PurchaseStatus.pending, ));
    await pumpEventQueue();
    expect(c.read(adFreeControllerProvider).busy, isFalse);
    expect(c.read(adFreeControllerProvider).notice, AdFreeNotice.pending);
  });

  test('itemAlreadyOwned error triggers a restore instead of failing', () async {
    final ProviderContainer c = make();
    await pumpEventQueue();
    store.owned = <PurchaseDetails>[p(PurchaseStatus.purchased)];
    await c.read(adFreeControllerProvider.notifier).buy();
    store.emit(p(PurchaseStatus.error,
        error: 'BillingResponse.itemAlreadyOwned'));
    await pumpEventQueue();
    expect(store.restoreCalls, 1);
    expect(c.read(adFreeControllerProvider).owned, isTrue);
  });

  test('restore with nothing owned reports nothing to restore', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer c = make();
      async.flushMicrotasks();
      c.read(adFreeControllerProvider.notifier).restore();
      async.elapse(AdFreeController.restoreWindow);
      async.flushMicrotasks();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.busy, isFalse);
      expect(s.notice, AdFreeNotice.nothingToRestore);
    });
  });

  test('restore of an owned purchase grants it', () {
    fakeAsync((FakeAsync async) {
      store.owned = <PurchaseDetails>[p(PurchaseStatus.purchased)];
      final ProviderContainer c = make();
      async.flushMicrotasks();
      c.read(adFreeControllerProvider.notifier).restore();
      async.flushMicrotasks();
      async.elapse(AdFreeController.restoreWindow);
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.owned, isTrue);
      expect(s.notice, AdFreeNotice.restored);
    });
  });

  test('busy has a ceiling when no outcome ever arrives', () {
    fakeAsync((FakeAsync async) {
      final ProviderContainer c = make();
      async.flushMicrotasks();
      c.read(adFreeControllerProvider.notifier).buy();
      async.flushMicrotasks();
      expect(c.read(adFreeControllerProvider).busy, isTrue);
      async.elapse(AdFreeController.busyCeiling);
      expect(c.read(adFreeControllerProvider).busy, isFalse);
    });
  });

  test('Play: launch reconcile picks up a purchase made while closed', () async {
    store.owned = <PurchaseDetails>[p(PurchaseStatus.purchased)];
    final ProviderContainer c = make(reconcile: true);
    await pumpEventQueue();
    expect(store.restoreCalls, 1);
    expect(c.read(adFreeControllerProvider).owned, isTrue);
  });

  test('cached entitlement is read synchronously at launch', () {
    settings = InMemorySettingsStore(<String, Object>{
      AdFreeController.ownedKey: true,
    });
    final ProviderContainer c = make();
    expect(c.read(adFreeOwnedProvider), isTrue);
  });

  group('entitlement edge cases', () {
    test('the entitlement is persisted BEFORE the transaction is finished',
        () async {
      final OrderRecordingStore recording = OrderRecordingStore(settings);
      store = recording;
      final ProviderContainer c = make();
      await pumpEventQueue();
      await c.read(adFreeControllerProvider.notifier).buy();
      store.emit(p(PurchaseStatus.purchased));
      await pumpEventQueue();
      expect(recording.ownedAtCompletion, <bool?>[true],
          reason: 'finishing first and crashing before the write would lose '
              'a paid unlock');
    });

    test('Play: a restored purchase still awaiting payment is NOT granted',
        () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      store.emit(playPurchase(
          PurchaseStateWrapper.pending, PurchaseStatus.restored));
      await pumpEventQueue();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.owned, isFalse);
      expect(s.notice, AdFreeNotice.pending);
      expect(settings.getBool(AdFreeController.ownedKey), isNot(true));
      expect(store.completed, isEmpty,
          reason: 'acknowledging an unpaid Play order is an error');
    });

    test('Play: a purchased-state order is granted (positive control)',
        () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      store.emit(playPurchase(
          PurchaseStateWrapper.purchased, PurchaseStatus.purchased));
      await pumpEventQueue();
      expect(c.read(adFreeControllerProvider).owned, isTrue);
      expect(store.completed, hasLength(1));
    });

    test('a purchase of some other product never grants ad-free', () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      store.emit(FakeStoreGateway.purchase(
          'com.froggyeye.sides.tip', PurchaseStatus.purchased));
      await pumpEventQueue();
      expect(c.read(adFreeControllerProvider).owned, isFalse);
      expect(store.completed, hasLength(1), reason: 'but it is finished');
    });

    test('a store error fails the purchase, clears busy, grants nothing',
        () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      await c.read(adFreeControllerProvider.notifier).buy();
      store.emit(p(PurchaseStatus.error, error: 'BillingResponse.error'));
      await pumpEventQueue();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.owned, isFalse);
      expect(s.busy, isFalse);
      expect(s.notice, AdFreeNotice.failed);
      expect(store.restoreCalls, 0);
    });

    test('an error on the purchase stream itself clears busy', () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      await c.read(adFreeControllerProvider.notifier).buy();
      store.controller.addError(StateError('billing service died'));
      await pumpEventQueue();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.busy, isFalse);
      expect(s.notice, AdFreeNotice.failed);
    });

    test('buy with the store unavailable reports it and never spins',
        () async {
      store = FakeStoreGateway(available: false);
      final ProviderContainer c = make();
      await pumpEventQueue();
      await c.read(adFreeControllerProvider.notifier).buy();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.busy, isFalse);
      expect(s.notice, AdFreeNotice.storeUnavailable);
      expect(store.buyCalls, 0);
    });

    test('restore with the store unavailable reports it', () async {
      store = FakeStoreGateway(available: false);
      final ProviderContainer c = make();
      await pumpEventQueue();
      await c.read(adFreeControllerProvider.notifier).restore();
      final AdFreeState s = c.read(adFreeControllerProvider);
      expect(s.busy, isFalse);
      expect(s.notice, AdFreeNotice.storeUnavailable);
      expect(store.restoreCalls, 0);
    });

    test('a second buy while busy is ignored (double tap)', () async {
      final ProviderContainer c = make();
      await pumpEventQueue();
      final AdFreeController ctl = c.read(adFreeControllerProvider.notifier);
      await ctl.buy();
      await ctl.buy();
      expect(store.buyCalls, 1);
    });
  });
}
