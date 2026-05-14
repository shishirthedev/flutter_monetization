/// Represents the type of subscription or purchase plan.
enum SubscriptionPlan {
  /// A monthly recurring subscription.
  monthly,

  /// A yearly recurring subscription.
  yearly,

  /// A one-time, non-consumable lifetime purchase. Never expires.
  lifetime,

  /// No active plan detected.
  none,
}

extension SubscriptionPlanX on SubscriptionPlan {
  bool get isSubscription =>
      this == SubscriptionPlan.monthly || this == SubscriptionPlan.yearly;

  bool get isLifetime => this == SubscriptionPlan.lifetime;

  bool get hasExpiry => isSubscription;

  String get displayName {
    switch (this) {
      case SubscriptionPlan.monthly:
        return 'Monthly';
      case SubscriptionPlan.yearly:
        return 'Yearly';
      case SubscriptionPlan.lifetime:
        return 'Lifetime';
      case SubscriptionPlan.none:
        return 'None';
    }
  }
}
