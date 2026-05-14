import 'package:flutter_monetization/flutter_monetization.dart';
import 'package:flutter_monetization/src/subscription/subscription_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockEntitlementStorage extends Mock implements EntitlementStorage {}

MonetizationConfig _config() => const MonetizationConfig(
      android: AndroidProducts(
        monthly: 'android_monthly',
        yearly: 'android_yearly',
        lifetime: 'android_lifetime',
      ),
      ios: IOSProducts(
        monthly: 'ios_monthly',
        yearly: 'ios_yearly',
        lifetime: 'ios_lifetime',
      ),
      autoRestoreOnInit: false,
      logLevel: MonetizationLogLevel.none,
    );

void main() {
  late MockEntitlementStorage storage;
  late SubscriptionManager manager;

  setUp(() {
    storage = MockEntitlementStorage();
    when(() => storage.save(any())).thenAnswer((_) async {});
    when(() => storage.load()).thenAnswer((_) async => null);
    when(() => storage.clear()).thenAnswer((_) async {});

    manager = SubscriptionManager(
      config: _config(),
      storage: storage,
    );
  });

  tearDown(() async {
    await manager.dispose();
  });

  group('SubscriptionManager initial state', () {
    test('starts with unknown status', () {
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
      expect(manager.currentStatus.isPremium, isFalse);
    });

    test('statusStream emits unknown on first listen', () async {
      final status = await manager.statusStream.first;
      expect(status.entitlementStatus, EntitlementStatus.unknown);
    });
  });

  group('SubscriptionManager loadCachedStatus', () {
    test('does nothing when cache is null', () async {
      when(() => storage.load()).thenAnswer((_) async => null);
      await manager.loadCachedStatus();
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
    });

    test('emits cached status when fresh', () async {
      final cached = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 20)),
        lastVerifiedAt: DateTime.now(),
      );
      when(() => storage.load()).thenAnswer((_) async => cached);

      await manager.loadCachedStatus();

      expect(
        manager.currentStatus.entitlementStatus,
        EntitlementStatus.active,
      );
    });

    test('does not emit stale cache', () async {
      final stale = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.monthly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 10)),
        lastVerifiedAt:
            DateTime.now().subtract(const Duration(hours: 25)), // stale
      );
      when(() => storage.load()).thenAnswer((_) async => stale);

      await manager.loadCachedStatus();

      // Should remain unknown (stale cache not applied)
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);
    });
  });

  group('SubscriptionManager onRestoreFoundNoPurchases', () {
    test('emits notPurchased status', () async {
      manager.onRestoreFoundNoPurchases();

      final status = manager.currentStatus;
      expect(status.entitlementStatus, EntitlementStatus.notPurchased);
      expect(status.isPremium, isFalse);
    });
  });

  group('SubscriptionManager updateFromRemote', () {
    test('upgrades when remote is better', () {
      // Start with unknown
      expect(manager.currentStatus.entitlementStatus, EntitlementStatus.unknown);

      final remote = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.lifetime,
        platformSource: PlatformSource.appStore,
        lastVerifiedAt: DateTime.now(),
      );

      manager.updateFromRemote(remote);
      expect(manager.currentStatus.activePlan, SubscriptionPlan.lifetime);
      expect(manager.currentStatus.isPremium, isTrue);
    });

    test('does not downgrade active to notPurchased', () {
      // Manually set to active first via remote
      final active = SubscriptionStatus(
        entitlementStatus: EntitlementStatus.active,
        activePlan: SubscriptionPlan.yearly,
        platformSource: PlatformSource.googlePlay,
        expiryDate: DateTime.now().add(const Duration(days: 100)),
        lastVerifiedAt: DateTime.now(),
      );
      manager.updateFromRemote(active);
      expect(manager.currentStatus.isPremium, isTrue);

      // Now try to downgrade
      final notPurchased = SubscriptionStatus.notPurchased(
        platform: PlatformSource.googlePlay,
      );
      manager.updateFromRemote(notPurchased);

      // Should still be active
      expect(manager.currentStatus.isPremium, isTrue);
    });
  });
}
