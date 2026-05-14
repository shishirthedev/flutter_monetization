import 'package:equatable/equatable.dart';

import 'subscription_plan.dart';

/// The outcome returned after a purchase or restore attempt.
sealed class PurchaseResult extends Equatable {
  const PurchaseResult();
}

/// Purchase completed successfully and entitlement is now active.
final class PurchaseSuccess extends PurchaseResult {
  const PurchaseSuccess({
    required this.plan,
    required this.productId,
    this.transactionId,
  });

  final SubscriptionPlan plan;
  final String productId;
  final String? transactionId;

  @override
  List<Object?> get props => [plan, productId, transactionId];

  @override
  String toString() =>
      'PurchaseSuccess(plan: ${plan.name}, productId: $productId)';
}

/// Purchase was intentionally cancelled by the user.
final class PurchaseCancelled extends PurchaseResult {
  const PurchaseCancelled({this.plan});

  final SubscriptionPlan? plan;

  @override
  List<Object?> get props => [plan];

  @override
  String toString() => 'PurchaseCancelled(plan: ${plan?.name})';
}

/// Purchase failed with an error.
final class PurchaseFailure extends PurchaseResult {
  const PurchaseFailure({
    required this.message,
    this.plan,
    this.underlyingError,
  });

  final String message;
  final SubscriptionPlan? plan;
  final Object? underlyingError;

  @override
  List<Object?> get props => [message, plan, underlyingError];

  @override
  String toString() =>
      'PurchaseFailure(plan: ${plan?.name}, message: $message)';
}

/// Restore attempt completed (zero or more purchases found).
final class RestoreResult extends PurchaseResult {
  const RestoreResult({
    required this.restoredCount,
    this.error,
  });

  final int restoredCount;
  final String? error;

  bool get hasError => error != null;
  bool get restored => restoredCount > 0;

  @override
  List<Object?> get props => [restoredCount, error];

  @override
  String toString() =>
      'RestoreResult(restored: $restoredCount, error: $error)';
}

/// Product was already purchased (e.g., duplicate purchase attempt).
final class PurchasePending extends PurchaseResult {
  const PurchasePending({this.plan});

  final SubscriptionPlan? plan;

  @override
  List<Object?> get props => [plan];

  @override
  String toString() => 'PurchasePending(plan: ${plan?.name})';
}
