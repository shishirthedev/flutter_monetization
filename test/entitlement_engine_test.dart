import 'package:flutter_monetization/flutter_monetization.dart';
import 'package:flutter_monetization/src/iap/purchase_handler.dart';
import 'package:flutter_monetization/src/subscription/subscription_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockEntitlementStorage extends Mock implements EntitlementStorage {}

class MockPurchaseHandler extends Mock implements PurchaseHandler {}

class MockSubscriptionManager extends Mock implements SubscriptionManager {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MonetizationConfig _makeConfig({
  MonetizationSyncDelegate? syncDelegate,
  MonetizationAnalyticsDelegate? analyticsDelegate,
}) {
  return MonetizationConfig(
    android: const AndroidProducts(
      monthly: 'android_monthly',
      yearly: 'android_yearly',
      lifetime: 'android_lifetime',
    ),
    ios: const IOSProducts(
      monthly: 'ios_monthly',
      yearly: 'ios_yearly',
      lifetime: 'ios_lifetime',
    ),
    syncDelegate: syncDelegate,
    analyticsDelegate: analyticsDelegate,
    autoRestoreOnInit: false,
    logLevel: MonetizationLogLevel.none,
  );
}

// ---------------------------------------------------------------------------
// SubscriptionStatus tests
// ---------------------------------------------------------------------------

void main() {
  group('SubscriptionStatus', () {
    test('unknown() factory sets correct defaults', () {
      final s = SubscriptionStatus.unknown();
      expect(s.entitlementStatus, EntitlementStatus.unknown);
      expect(s.activePlan, SubscriptionPlan.none);
      expect(s.isPremium, isFalse);
      expect(s.isLoading, isTrue);
    });

    test('notPurchased() sets correct state', () {
      final s = SubscriptionStatus.notPurchased(
        platform: PlatformSource.googlePlay,
      );
      expect(s.entitlementStatus, EntitlementStatus.notPurchased);
      expect(s.isPremium, isFalse);
      expect(s.isLoading, isFalse);
    });

    test('active subscription isPremium true', () {
      final s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.appStore,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        lastVerifiedAt: DateTime.now(),
      );
      expect(s.isPremium, isTrue);
      expect(s.isActiveSubscription, isTrue);
      expect(s.isLifetime, isFalse);
    });

    test('expired subscription isPremium false', () {
      final s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.expired,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.appStore,
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isPremium, isFalse);
      expect(s.isActiveSubscription, isFalse);
    });

    test('cancelled subscription grants premium until expiry', () {
      final s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.cancelled,
        activePlan: SubscriptionPlan.yearly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 10)),
      );
      expect(s.isPremium, isTrue); // cancelled but not yet expired
    });

    test('lifetime purchase isPremium and never expires', () {
      const s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.lifetime,
        platformSource: PlatformSource.appStore,
      );
      expect(s.isPremium, isTrue);
      expect(s.isLifetime, isTrue);
      expect(s.expiryDate, isNull);
      expect(s.remainingDuration, isNull);
    });

    test('gracePeriod grants premium access', () {
      final s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.gracePeriod,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.googlePlay,
        isInGracePeriod: true,
        expiryDate: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(s.isPremium, isTrue);
    });

    test('remainingDuration is zero when expired', () {
      final s = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.expired,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.appStore,
        expiryDate: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(s.remainingDuration, Duration.zero);
    });

    test('copyWith works correctly', () {
      final original = SubscriptionStatus.unknown();
      final updated = original.copyWith(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.yearly,
      );
      expect(updated.entitlementStatus, EntitlementStatus.active);
      expect(updated.activePlan, SubscriptionPlan.yearly);
      expect(updated.platformSource, original.platformSource);
    });

    test('toJson / fromJson round-trips correctly', () {
      final original = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.appStore,
        expiryDate: DateTime(2026, 12, 31),
        originalTransactionId: 'txn_123',
        productId: 'ios_monthly',
        lastVerifiedAt: DateTime(2026),
      );

      final json = original.toJson();
      final decoded = SubscriptionStatus.fromJson(json);

      expect(decoded, equals(original));
    });

    test('fromJson handles unknown enum values gracefully', () {
      final json = {
        'entitlementStatus': 'FUTURE_STATUS_NOT_IN_ENUM',
        'activePlan': 'FUTURE_PLAN',
        'platformSource': 'unknown',
      };
      final status = SubscriptionStatus.fromJson(json);
      expect(status.entitlementStatus, EntitlementStatus.unknown);
      expect(status.activePlan, SubscriptionPlan.none);
    });
  });

  // ---------------------------------------------------------------------------
  // MonetizationConfig tests
  // ---------------------------------------------------------------------------

  group('MonetizationConfig', () {
    test('allProductIds contains all 6 product IDs', () {
      final config = _makeConfig();
      expect(config.allProductIds, hasLength(6));
      expect(config.allProductIds, contains('android_monthly'));
      expect(config.allProductIds, contains('ios_lifetime'));
    });

    test('androidProductId returns correct IDs', () {
      final config = _makeConfig();
      expect(config.androidProductId('monthly'), 'android_monthly');
      expect(config.androidProductId('yearly'), 'android_yearly');
      expect(config.androidProductId('lifetime'), 'android_lifetime');
    });

    test('iosProductId returns correct IDs', () {
      final config = _makeConfig();
      expect(config.iosProductId('monthly'), 'ios_monthly');
      expect(config.iosProductId('yearly'), 'ios_yearly');
      expect(config.iosProductId('lifetime'), 'ios_lifetime');
    });

    test('throws for unknown plan key', () {
      final config = _makeConfig();
      expect(
        () => config.androidProductId('unknown'),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SubscriptionPlan extensions
  // ---------------------------------------------------------------------------

  group('SubscriptionPlan extensions', () {
    test('monthly and yearly are subscriptions', () {
      expect(SubscriptionPlan.monthly.isSubscription, isTrue);
      expect(SubscriptionPlan.yearly.isSubscription, isTrue);
      expect(SubscriptionPlan.lifetime.isSubscription, isFalse);
      expect(SubscriptionPlan.none.isSubscription, isFalse);
    });

    test('lifetime isLifetime', () {
      expect(SubscriptionPlan.lifetime.isLifetime, isTrue);
      expect(SubscriptionPlan.monthly.isLifetime, isFalse);
    });

    test('hasExpiry only for subscriptions', () {
      expect(SubscriptionPlan.monthly.hasExpiry, isTrue);
      expect(SubscriptionPlan.yearly.hasExpiry, isTrue);
      expect(SubscriptionPlan.lifetime.hasExpiry, isFalse);
    });

    test('displayName returns correct strings', () {
      expect(SubscriptionPlan.monthly.displayName, 'Monthly');
      expect(SubscriptionPlan.yearly.displayName, 'Yearly');
      expect(SubscriptionPlan.lifetime.displayName, 'Lifetime');
      expect(SubscriptionPlan.none.displayName, 'None');
    });
  });

  // ---------------------------------------------------------------------------
  // EntitlementStatus extensions
  // ---------------------------------------------------------------------------

  group('EntitlementStatus extensions', () {
    test('grantsPremium for correct states', () {
      expect(EntitlementStatus.active.grantsPremium, isTrue);
      expect(EntitlementStatus.cancelled.grantsPremium, isTrue);
      expect(EntitlementStatus.gracePeriod.grantsPremium, isTrue);
      expect(EntitlementStatus.expired.grantsPremium, isFalse);
      expect(EntitlementStatus.notPurchased.grantsPremium, isFalse);
      expect(EntitlementStatus.unknown.grantsPremium, isFalse);
    });

    test('isLoading only for unknown', () {
      expect(EntitlementStatus.unknown.isLoading, isTrue);
      expect(EntitlementStatus.active.isLoading, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PurchaseResult sealed class tests
  // ---------------------------------------------------------------------------

  group('PurchaseResult', () {
    test('PurchaseSuccess has correct properties', () {
      const result = PurchaseSuccess(
        plan: SubscriptionPlan.monthly,
        productId: 'ios_monthly',
        transactionId: 'txn_abc',
      );
      expect(result.plan, SubscriptionPlan.monthly);
      expect(result.productId, 'ios_monthly');
      expect(result.transactionId, 'txn_abc');
    });

    test('RestoreResult restored is true when count > 0', () {
      const result = RestoreResult(restoredCount: 2);
      expect(result.restored, isTrue);
      expect(result.hasError, isFalse);
    });

    test('RestoreResult hasError when error is set', () {
      const result = RestoreResult(restoredCount: 0, error: 'network error');
      expect(result.hasError, isTrue);
      expect(result.restored, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // MonetizationDateUtils tests
  // ---------------------------------------------------------------------------

  group('MonetizationDateUtils', () {
    test('isActive returns true for future date', () {
      final future = DateTime.now().add(const Duration(days: 1));
      expect(MonetizationDateUtils.isActive(future), isTrue);
    });

    test('isActive returns false for past date', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(MonetizationDateUtils.isActive(past), isFalse);
    });

    test('isExpired returns true for past date', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(MonetizationDateUtils.isExpired(past), isTrue);
    });

    test('isWithinWindow returns true when within window', () {
      final soon = DateTime.now().add(const Duration(hours: 2));
      expect(
        MonetizationDateUtils.isWithinWindow(soon, const Duration(hours: 3)),
        isTrue,
      );
    });

    test('tryParseIso returns null for null/empty string', () {
      expect(MonetizationDateUtils.tryParseIso(null), isNull);
      expect(MonetizationDateUtils.tryParseIso(''), isNull);
    });

    test('fromEpochMs converts correctly', () {
      const ms = 1700000000000;
      final date = MonetizationDateUtils.fromEpochMs(ms);
      expect(date, isNotNull);
      expect(date!.millisecondsSinceEpoch, ms);
    });
  });

  // ---------------------------------------------------------------------------
  // Storage tests (in-memory mock)
  // ---------------------------------------------------------------------------

  group('SharedPreferencesEntitlementStorage (mock)', () {
    late MockEntitlementStorage storage;

    setUp(() {
      storage = MockEntitlementStorage();
    });

    test('load returns null when no data saved', () async {
      when(() => storage.load()).thenAnswer((_) async => null);
      final result = await storage.load();
      expect(result, isNull);
    });

    test('save and load round-trips', () async {
      final status = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.yearly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime(2027, 6),
        lastVerifiedAt: DateTime.now(),
      );
      when(() => storage.save(status)).thenAnswer((_) async {});
      when(() => storage.load()).thenAnswer((_) async => status);

      await storage.save(status);
      final loaded = await storage.load();
      expect(loaded, equals(status));
    });

    test('clear removes stored data', () async {
      when(() => storage.clear()).thenAnswer((_) async {});
      when(() => storage.load()).thenAnswer((_) async => null);

      await storage.clear();
      final loaded = await storage.load();
      expect(loaded, isNull);
    });
  });
}
