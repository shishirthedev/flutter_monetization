/// Represents the lifecycle state of a user's entitlement.
///
/// - [unknown]       → Fresh install / restore not yet completed. Do NOT
///                     assume premium OR non-premium. Show loading.
/// - [active]        → Entitlement is valid and premium access is granted.
/// - [expired]       → Subscription existed but has passed its expiry date
///                     and did not renew.
/// - [cancelled]     → User voluntarily cancelled. Access may still be valid
///                     until [SubscriptionStatus.expiryDate].
/// - [notPurchased]  → No purchase record found on this platform.
/// - [gracePeriod]   → Payment failed; platform is retrying. Grant access.
enum EntitlementStatus {
  unknown,
  active,
  expired,
  cancelled,
  notPurchased,
  gracePeriod,
}

extension EntitlementStatusX on EntitlementStatus {
  /// Returns true if premium access should be granted.
  bool get grantsPremium =>
      this == EntitlementStatus.active ||
      this == EntitlementStatus.cancelled || // until expiry
      this == EntitlementStatus.gracePeriod;

  /// Returns true if we are still determining entitlement.
  bool get isLoading => this == EntitlementStatus.unknown;

  String get displayName {
    switch (this) {
      case EntitlementStatus.unknown:
        return 'Unknown';
      case EntitlementStatus.active:
        return 'Active';
      case EntitlementStatus.expired:
        return 'Expired';
      case EntitlementStatus.cancelled:
        return 'Cancelled';
      case EntitlementStatus.notPurchased:
        return 'Not Purchased';
      case EntitlementStatus.gracePeriod:
        return 'Grace Period';
    }
  }
}
