import 'package:equatable/equatable.dart';

import 'entitlement_status.dart';
import 'platform_source.dart';
import 'subscription_plan.dart';

/// The full entitlement snapshot exposed to consumers of the package.
///
/// Immutable value object. All fields are safe to read from any isolate.
class SubscriptionStatus extends Equatable {
  const SubscriptionStatus({
    required this.entitlementStatus,
    required this.activePlan,
    required this.platformSource,
    this.expiryDate,
    this.originalTransactionId,
    this.productId,
    this.isTrial = false,
    this.isInGracePeriod = false,
    this.lastVerifiedAt,
  });

  // ---------------------------------------------------------------------------
  // Factory constructors — kept before non-constructor members per lint rules
  // ---------------------------------------------------------------------------

  /// Initial state before any restore or purchase has completed.
  factory SubscriptionStatus.unknown() => const SubscriptionStatus(
        entitlementStatus: EntitlementStatus.unknown,
        activePlan: SubscriptionPlan.none,
        platformSource: PlatformSource.unknown,
      );

  /// Explicit "no purchase found" state after a successful restore check.
  factory SubscriptionStatus.notPurchased({
    required PlatformSource platform,
  }) =>
      SubscriptionStatus(
        entitlementStatus: EntitlementStatus.notPurchased,
        activePlan: SubscriptionPlan.none,
        platformSource: platform,
        lastVerifiedAt: DateTime.now(),
      );

  /// Deserialises from a JSON map produced by [toJson].
  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      entitlementStatus: EntitlementStatus.values.firstWhere(
        (e) => e.name == json['entitlementStatus'],
        orElse: () => EntitlementStatus.unknown,
      ),
      activePlan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == json['activePlan'],
        orElse: () => SubscriptionPlan.none,
      ),
      platformSource: PlatformSource.values.firstWhere(
        (e) => e.name == json['platformSource'],
        orElse: () => PlatformSource.unknown,
      ),
      expiryDate: json['expiryDate'] != null
          ? DateTime.tryParse(json['expiryDate'] as String)
          : null,
      originalTransactionId: json['originalTransactionId'] as String?,
      productId: json['productId'] as String?,
      isTrial: json['isTrial'] as bool? ?? false,
      isInGracePeriod: json['isInGracePeriod'] as bool? ?? false,
      lastVerifiedAt: json['lastVerifiedAt'] != null
          ? DateTime.tryParse(json['lastVerifiedAt'] as String)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Fields
  // ---------------------------------------------------------------------------

  /// The computed entitlement state.
  final EntitlementStatus entitlementStatus;

  /// The plan that is (or was) active.
  final SubscriptionPlan activePlan;

  /// Platform that fulfilled the purchase.
  final PlatformSource platformSource;

  /// For subscriptions: the date access expires or expired.
  /// Null for lifetime purchases and [EntitlementStatus.notPurchased].
  final DateTime? expiryDate;

  /// Original transaction identifier from the store.
  final String? originalTransactionId;

  /// The store product ID that was purchased.
  final String? productId;

  /// Whether the purchase is a free trial.
  final bool isTrial;

  /// Whether the subscription is in a payment grace period.
  final bool isInGracePeriod;

  /// When this status was last synced from the store.
  final DateTime? lastVerifiedAt;

  // ---------------------------------------------------------------------------
  // Derived helpers
  // ---------------------------------------------------------------------------

  /// True when premium access should be granted.
  bool get isPremium => entitlementStatus.grantsPremium;

  /// True when entitlement state is still being determined.
  bool get isLoading => entitlementStatus.isLoading;

  /// True when a subscription exists and has not yet expired.
  bool get isActiveSubscription =>
      activePlan.isSubscription &&
      entitlementStatus == EntitlementStatus.active &&
      (expiryDate == null || expiryDate!.isAfter(DateTime.now()));

  /// True when a lifetime purchase is confirmed.
  bool get isLifetime => activePlan.isLifetime && isPremium;

  /// Remaining duration until expiry. Null for lifetime or if no expiry set.
  Duration? get remainingDuration {
    if (expiryDate == null) return null;
    final remaining = expiryDate!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ---------------------------------------------------------------------------
  // CopyWith
  // ---------------------------------------------------------------------------

  SubscriptionStatus copyWith({
    EntitlementStatus? entitlementStatus,
    SubscriptionPlan? activePlan,
    PlatformSource? platformSource,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? originalTransactionId,
    String? productId,
    bool? isTrial,
    bool? isInGracePeriod,
    DateTime? lastVerifiedAt,
  }) {
    return SubscriptionStatus(
      entitlementStatus: entitlementStatus ?? this.entitlementStatus,
      activePlan: activePlan ?? this.activePlan,
      platformSource: platformSource ?? this.platformSource,
      expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
      originalTransactionId:
          originalTransactionId ?? this.originalTransactionId,
      productId: productId ?? this.productId,
      isTrial: isTrial ?? this.isTrial,
      isInGracePeriod: isInGracePeriod ?? this.isInGracePeriod,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization (for local cache)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'entitlementStatus': entitlementStatus.name,
        'activePlan': activePlan.name,
        'platformSource': platformSource.name,
        'expiryDate': expiryDate?.toIso8601String(),
        'originalTransactionId': originalTransactionId,
        'productId': productId,
        'isTrial': isTrial,
        'isInGracePeriod': isInGracePeriod,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      };

  @override
  List<Object?> get props => [
        entitlementStatus,
        activePlan,
        platformSource,
        expiryDate,
        originalTransactionId,
        productId,
        isTrial,
        isInGracePeriod,
        lastVerifiedAt,
      ];

  @override
  String toString() =>
      'SubscriptionStatus(${entitlementStatus.name}, plan: ${activePlan.name}, '
      'platform: ${platformSource.name}, expiry: $expiryDate)';
}
