/// Thrown when the [Monetization] facade is used before [Monetization.init]
/// has completed successfully.
class MonetizationNotInitializedException implements Exception {
  const MonetizationNotInitializedException()
      : message = 'Monetization.init() must be called and awaited before use.';

  final String message;

  @override
  String toString() => 'MonetizationNotInitializedException: $message';
}

/// Thrown when a product ID cannot be resolved for the requested plan.
class ProductNotFoundException implements Exception {
  const ProductNotFoundException(this.plan, this.platform)
      : message =
            'No product ID configured for plan "$plan" on platform "$platform".';

  final String plan;
  final String platform;
  final String message;

  @override
  String toString() => 'ProductNotFoundException: $message';
}

/// Thrown when IAP is not available on the current device.
class IAPUnavailableException implements Exception {
  const IAPUnavailableException()
      : message =
            'In-App Purchases are not available on this device or connection.';

  final String message;

  @override
  String toString() => 'IAPUnavailableException: $message';
}
