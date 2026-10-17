import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:sides/core/launcher/link_launcher.dart';
import 'package:sides/features/digest/domain/digest.dart';
import 'package:sides/features/search/data/archive_repository.dart';
import 'package:sides/features/search/data/topic_repository.dart';
import 'package:sides/features/ads/data/ads_service.dart';
import 'package:sides/features/purchases/data/store_gateway.dart';

/// An archive of in-memory digests by date (newest first in [index]).
class FakeArchiveRepository implements ArchiveRepository {
  FakeArchiveRepository([Map<String, Digest>? days]) : days = days ?? <String, Digest>{};
  final Map<String, Digest> days;

  /// Dates already saved on the phone (served with `online: false`).
  final Set<String> onPhone = <String>{};

  /// True to behave as if the network could not be reached.
  bool offline = false;
  int indexCalls = 0;
  final List<String> downloaded = <String>[];

  List<ArchiveEntry> _entries(Iterable<String> dates) {
    final List<String> sorted = dates.toList()..sort((String a, String b) => b.compareTo(a));
    return <ArchiveEntry>[
      for (final String d in sorted)
        ArchiveEntry(date: d, stories: days[d]!.stories.length),
    ];
  }

  @override
  Future<List<ArchiveEntry>> index({bool online = true}) async {
    indexCalls++;
    if (!online) return _entries(onPhone.where(days.containsKey));
    if (offline) return const <ArchiveEntry>[];
    return _entries(days.keys);
  }

  @override
  Future<Digest?> digest(String date, {bool online = true}) async {
    if (onPhone.contains(date)) return days[date];
    if (!online || offline) return null;
    downloaded.add(date);
    return days[date];
  }
}

/// Answers every topic request with [outcome]; records the queries.
class FakeTopicRepository implements TopicRepository {
  FakeTopicRepository([this.outcome = const TopicNoMatch()]);
  TopicOutcome outcome;

  /// What the shared cache holds (null = a miss).
  TopicOutcome? peekOutcome;

  /// A comparison already on the phone.
  TopicReady? phone;

  final List<String> queries = <String>[];
  final List<String> peeks = <String>[];

  /// When set, the answer waits for it (to observe the working state).
  Completer<void>? gate;

  @override
  TopicReady? onPhone(String query) => phone;

  @override
  Future<TopicOutcome?> peek(String query) async {
    peeks.add(query);
    return peekOutcome;
  }

  @override
  Future<TopicOutcome> analyse(String query) async {
    queries.add(query);
    if (gate != null) await gate!.future;
    return outcome;
  }
}

class FakeLinkLauncher implements LinkLauncher {
  final List<Uri> opened = <Uri>[];
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }

  final List<Uri> composed = <Uri>[];

  @override
  Future<bool> compose(Uri mailto) async {
    composed.add(mailto);
    return result;
  }
}

/// Never touches the Mobile Ads SDK; renders a keyed placeholder.
class FakeAdsService implements AdsService {
  static const Key bannerKey = Key('fake-banner');
  int bannersBuilt = 0;

  /// Completed by a test to model UMP finishing its consent update.
  final Completer<bool> consent = Completer<bool>();

  /// What UMP reports once consent has been gathered.
  bool privacyRequired = false;

  @override
  Future<bool> initialize() async => true;
  @override
  Future<bool> get consentGathered => consent.future;
  @override
  Future<bool> privacyOptionsRequired() async =>
      consent.isCompleted && await consent.future && privacyRequired;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Widget banner() {
    bannersBuilt++;
    return const SizedBox(key: bannerKey, height: 50, width: 320);
  }
}

/// Emits real [PurchaseDetails] on its stream, exactly as the plugin does.
/// [buyNonConsumable] only reports that the sheet opened, like the real one.
class FakeStoreGateway implements StoreGateway {
  FakeStoreGateway({this.available = true, this.price = '£2.99'});

  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool available;
  String price;
  int buyCalls = 0;
  int restoreCalls = 0;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  /// Purchases [restorePurchases] re-delivers as `restored`.
  List<PurchaseDetails> owned = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: <ProductDetails>[
          for (final String id in ids)
            ProductDetails(
              id: id,
              title: 'Remove ads',
              description: 'Removes banner ads',
              price: price,
              rawPrice: 2.99,
              currencyCode: 'GBP',
            ),
        ],
        notFoundIDs: const <String>[],
      );

  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    buyCalls++;
    return true;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    if (owned.isNotEmpty) {
      controller.add(<PurchaseDetails>[
        for (final PurchaseDetails p in owned)
          purchase(p.productID, PurchaseStatus.restored),
      ]);
    }
  }

  @override
  Future<void> completePurchase(PurchaseDetails details) async {
    completed.add(details);
  }

  void emit(PurchaseDetails details) =>
      controller.add(<PurchaseDetails>[details]);

  static PurchaseDetails purchase(
    String productId,
    PurchaseStatus status, {
    bool pendingComplete = true,
    String? errorMessage,
  }) =>
      PurchaseDetails(
        purchaseID: 'txn-$productId',
        productID: productId,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'local',
          serverVerificationData: 'token',
          source: 'test',
        ),
        transactionDate: '1760480000000',
        status: status,
      )
        ..pendingCompletePurchase = pendingComplete
        ..error = errorMessage == null
            ? null
            : IAPError(source: 'test', code: 'e', message: errorMessage);
}
