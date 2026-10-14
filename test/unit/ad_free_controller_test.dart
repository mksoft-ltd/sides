import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sides/core/config/app_config.dart';
import 'package:sides/core/storage/settings_store.dart';
import 'package:sides/features/purchases/presentation/ad_free_controller.dart';

import '../helpers/fakes.dart';

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
}
