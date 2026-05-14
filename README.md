# flutter_monetization

A production-grade Flutter SDK for In-App Purchases and entitlement management.  
Plug it into any app in minutes — Android and iOS with one unified API.

---

## Table of Contents

1. [Features](#features)
2. [Platform Setup](#platform-setup)
3. [Installation](#installation)
4. [Step 1 — Initialize](#step-1--initialize)
5. [Step 2 — Check Premium Status](#step-2--check-premium-status)
6. [Step 3 — Show a Paywall](#step-3--show-a-paywall)
7. [Step 4 — Purchase a Plan](#step-4--purchase-a-plan)
8. [Step 5 — Restore Purchases](#step-5--restore-purchases)
9. [Entitlement States](#entitlement-states)
10. [Reactive UI with StreamBuilder](#reactive-ui-with-streambuilder)
11. [Gating Features](#gating-features)
12. [AdMob Integration](#admob-integration)
13. [Firestore Sync](#firestore-sync-optional)
14. [Analytics](#analytics-optional)
15. [Custom Storage](#custom-storage-optional)
16. [Configuration Reference](#configuration-reference)
17. [Troubleshooting](#troubleshooting)
18. [Running Tests](#running-tests)

---

## Features

| | |
|---|---|
| ✅ | Monthly, yearly, and lifetime purchases |
| ✅ | Android (Google Play Billing) + iOS (StoreKit) |
| ✅ | Automatic restore on startup |
| ✅ | Reactive status stream — UI rebuilds automatically |
| ✅ | Local cache for instant cold-start |
| ✅ | Grace period support |
| ✅ | Optional Firestore / backend sync |
| ✅ | Optional analytics hooks |
| ✅ | AdMob gating via `isPremium` |
| ✅ | Zero hardcoded product IDs |
| ✅ | No Firebase dependency required |

---

## Platform Setup

Before writing any Dart code you need to register your products in the stores and add the required permissions to your native project files.

### Android

In `android/app/build.gradle`, make sure your `minSdkVersion` is at least **21**:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

In `android/app/src/main/AndroidManifest.xml`, add the billing permission:

```xml
<uses-permission android:name="com.android.vending.BILLING" />
```

Create your subscription products in the [Google Play Console](https://play.google.com/console) under **Monetise → Products → Subscriptions**.

### iOS

In Xcode, enable the **In-App Purchase** capability:

`Xcode → Your Target → Signing & Capabilities → + Capability → In-App Purchase`

Create your products in [App Store Connect](https://appstoreconnect.apple.com) under **Features → In-App Purchases**.

> Both stores require at least one release build uploaded before products become testable. Use sandbox accounts for testing.

---

## Installation

Add to your app's `pubspec.yaml`:

```yaml
dependencies:
  flutter_monetization:
    path: ../flutter_monetization   # or your pub.dev reference
```

```bash
flutter pub get
```

Import in your Dart files:

```dart
import 'package:flutter_monetization/flutter_monetization.dart';
```

---

## Step 1 — Initialize

Call `Monetization.init()` **once**, at the very top of `main()`, before `runApp()`.  
Pass your product IDs exactly as registered in each store.

```dart
// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_monetization/flutter_monetization.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Monetization.init(
    MonetizationConfig(
      android: AndroidProducts(
        monthly:  'com.yourapp.premium_monthly',
        yearly:   'com.yourapp.premium_yearly',
        lifetime: 'com.yourapp.premium_lifetime',
      ),
      ios: IOSProducts(
        monthly:  'com.yourapp.premium_monthly',
        yearly:   'com.yourapp.premium_yearly',
        lifetime: 'com.yourapp.premium_lifetime',
      ),
    ),
  );

  runApp(const MyApp());
}
```

`init()` does the following in order:
1. Loads any locally cached entitlement for a fast startup hint
2. Starts the IAP stream listener
3. Fetches a remote hint from your `syncDelegate` (if configured)
4. Automatically restores previous purchases from the store

> **Do not call `Monetization.instance` before `init()` completes.** It will throw
> `MonetizationNotInitializedException`.

---

## Step 2 — Check Premium Status

After `init()`, reading status is synchronous and always safe:

```dart
// Synchronous — safe to call anywhere after init()
final bool isPremium = Monetization.instance.isPremium;
final SubscriptionStatus status = Monetization.instance.status;

print(status.isPremium);          // true / false
print(status.activePlan);         // SubscriptionPlan.monthly / .yearly / .lifetime / .none
print(status.entitlementStatus);  // active / expired / cancelled / unknown / ...
print(status.expiryDate);         // DateTime? — null for lifetime purchases
print(status.remainingDuration);  // Duration? — how long left on a subscription
print(status.isLifetime);         // true when a lifetime purchase is active
print(status.isLoading);          // true while the initial restore is still running
```

### ⚠️ The `unknown` rule

On a **fresh install**, or while the automatic restore is still running, the status is
`EntitlementStatus.unknown`. This means:

- **Do NOT assume the user is free** — you might hide premium content they paid for
- **Do NOT assume the user is premium** — you would bypass your paywall

Always show a loading indicator while `status.isLoading` is `true` and wait for the
stream to emit a definitive state.

---

## Step 3 — Show a Paywall

Use `StreamBuilder` to reactively display your paywall or premium content:

```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SubscriptionStatus>(
      stream: Monetization.instance.statusStream,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SubscriptionStatus.unknown();

        // Still waiting for store to confirm — show spinner
        if (status.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Premium user — show your premium UI
        if (status.isPremium) {
          return const PremiumHomeScreen();
        }

        // Free user — show paywall
        return const PaywallScreen();
      },
    );
  }
}
```

### Paywall screen example

```dart
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium'),
        actions: [
          TextButton(
            onPressed: () => _restore(context),
            child: const Text('Restore'),
          ),
        ],
      ),
      body: Column(
        children: [
          _PlanTile(
            label: 'Monthly',
            description: 'Billed every month. Cancel anytime.',
            plan: SubscriptionPlan.monthly,
          ),
          _PlanTile(
            label: 'Yearly',
            description: 'Best value. Billed once a year.',
            plan: SubscriptionPlan.yearly,
          ),
          _PlanTile(
            label: 'Lifetime',
            description: 'One-time purchase. Never expires.',
            plan: SubscriptionPlan.lifetime,
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final result = await Monetization.instance.restorePurchases();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.restored
          ? 'Purchases restored!'
          : 'No previous purchases found.'),
    ));
  }
}
```

### Display real prices from the store

Use `productDetails` to show localised prices instead of hardcoded strings:

```dart
final details = Monetization.instance.productDetails;

// Keyed by product ID. Available after init() resolves.
// {
//   'id':           'com.yourapp.premium_monthly',
//   'title':        'Premium Monthly',
//   'description':  'Unlock all features',
//   'price':        '$4.99',          ← localised, ready to display
//   'currencyCode': 'USD',
//   'rawPrice':     4.99,
// }

final monthlyPrice = details['com.yourapp.premium_monthly']?['price'] ?? '--';
final yearlyPrice  = details['com.yourapp.premium_yearly']?['price']  ?? '--';
```

---

## Step 4 — Purchase a Plan

```dart
Future<void> _onPlanTapped(BuildContext context, SubscriptionPlan plan) async {
  final result = await Monetization.instance.purchase(plan: plan);

  switch (result) {
    // Store UI appeared — the real confirmation comes via the stream.
    // Listen for it below.
    case PurchasePending():
      _listenForFinalResult(context);

    // Immediate success (uncommon — prefer stream)
    case PurchaseSuccess(:final plan):
      _showSuccess(context, plan);

    case PurchaseFailure(:final message):
      _showError(context, message);

    case PurchaseCancelled():
      // User tapped the back button — do nothing
      break;

    default:
      break;
  }
}

void _listenForFinalResult(BuildContext context) {
  Monetization.instance.purchaseResultStream.first.then((result) {
    if (!context.mounted) return;
    switch (result) {
      case PurchaseSuccess(:final plan):
        _showSuccess(context, plan);
      case PurchaseFailure(:final message):
        _showError(context, message);
      default:
        break;
    }
  });
}

void _showSuccess(BuildContext context, SubscriptionPlan plan) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Welcome to ${plan.displayName}! 🎉')),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Purchase failed: $message')),
  );
}
```

### Purchase result types

| Type | When it fires | What to do |
|---|---|---|
| `PurchasePending` | Store sheet has appeared | Show a spinner; listen to `purchaseResultStream` |
| `PurchaseSuccess` | Purchase confirmed immediately | Unlock premium UI |
| `PurchaseFailure` | Store or network error | Show error message; check `.message` |
| `PurchaseCancelled` | User dismissed the sheet | Do nothing |
| `RestoreResult` | Returned by `restorePurchases()` only | Check `.restored` and `.restoredCount` |

---

## Step 5 — Restore Purchases

Required by **App Store Review Guidelines** on iOS — you must provide a visible button.  
On Android, purchases are typically restored automatically, but calling this manually is good practice.

```dart
ElevatedButton(
  onPressed: () async {
    final result = await Monetization.instance.restorePurchases();

    if (result.restored) {
      // Status stream will update automatically
      showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Purchases Restored'),
          content: Text('Your premium access has been restored.'),
        ),
      );
    } else if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: ${result.error}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous purchases found.')),
      );
    }
  },
  child: const Text('Restore Purchases'),
)
```

> `autoRestoreOnInit: true` (the default) already calls this on startup,
> so purchases are restored before your first screen renders.

---

## Entitlement States

| State | Meaning | `isPremium` |
|---|---|---|
| `unknown` | Restore not yet complete — show loading | `false` |
| `active` | Subscription or lifetime is valid | `true` |
| `expired` | Subscription lapsed, not renewed | `false` |
| `cancelled` | Cancelled by user — valid until `expiryDate` | `true` until expiry |
| `notPurchased` | No purchase found after restore | `false` |
| `gracePeriod` | Payment failed — platform is retrying | `true` |

---

## Reactive UI with StreamBuilder

`statusStream` is a `BehaviorSubject` — it **replays the latest value** immediately on
every new subscription. You never miss an update.

```dart
// Pattern 1 — StreamBuilder (recommended for widget trees)
StreamBuilder<SubscriptionStatus>(
  stream: Monetization.instance.statusStream,
  builder: (context, snapshot) {
    final status = snapshot.data ?? SubscriptionStatus.unknown();
    if (status.isLoading) return const LoadingView();
    if (status.isPremium) return const PremiumView();
    return const FreeView();
  },
)

// Pattern 2 — setState in initState (for StatefulWidget)
@override
void initState() {
  super.initState();
  _sub = Monetization.instance.statusStream.listen((status) {
    if (mounted) setState(() => _status = status);
  });
}

@override
void dispose() {
  _sub.cancel();
  super.dispose();
}

// Pattern 3 — with a state manager (Riverpod example)
final premiumProvider = StreamProvider<bool>((ref) {
  return Monetization.instance.statusStream.map((s) => s.isPremium);
});
```

---

## Gating Features

### Gate a whole screen

```dart
class PremiumFeatureScreen extends StatelessWidget {
  const PremiumFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Monetization.instance.isPremium) {
      // Redirect to paywall instead
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
      });
      return const SizedBox.shrink();
    }

    return const Scaffold(body: ActualPremiumContent());
  }
}
```

### Gate a widget inline

```dart
// Hide or blur a widget based on premium status
StreamBuilder<SubscriptionStatus>(
  stream: Monetization.instance.statusStream,
  builder: (context, snapshot) {
    final isPremium = snapshot.data?.isPremium ?? false;
    return isPremium
        ? const ExportButton()
        : const LockedFeatureBadge(label: 'Export — Premium only');
  },
)
```

### Check subscription details

```dart
final status = Monetization.instance.status;

if (status.activePlan == SubscriptionPlan.lifetime) {
  print('Lifetime member — never expires');
} else if (status.expiryDate != null) {
  final daysLeft = status.remainingDuration?.inDays ?? 0;
  print('Subscription expires in $daysLeft day(s)');
}
```

---

## AdMob Integration

The SDK provides one boolean that your ad controller reads. No AdMob code lives inside this package.

```dart
// Wherever you initialise your ads:
Future<void> setupAds() async {
  // Synchronous check — safe after Monetization.init() resolves
  if (Monetization.instance.isPremium) {
    return; // premium user — skip ads entirely
  }

  await MobileAds.instance.initialize();
  loadBannerAd();
}

// For reactive ad management — disable/enable as status changes:
@override
void initState() {
  super.initState();
  Monetization.instance.statusStream.listen((status) {
    if (status.isPremium) {
      _bannerAd?.dispose();
      _bannerAd = null;
    } else {
      _loadBannerAd();
    }
  });
}
```

---

## Firestore Sync (Optional)

The package provides an abstract interface. Implement it in your app with your own
Firestore logic — **no Firebase dependency is added to this package**.

### 1. Implement the delegate

```dart
// In your app — not in the package
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_monetization/flutter_monetization.dart';

class FirestoreSyncDelegate implements MonetizationSyncDelegate {
  FirestoreSyncDelegate({
    required FirebaseFirestore db,
    required String userId,
  })  : _db = db,
        _userId = userId;

  final FirebaseFirestore _db;
  final String _userId;

  DocumentReference get _userDoc => _db.collection('users').doc(_userId);

  @override
  Future<void> onEntitlementUpdated(SubscriptionStatus status) async {
    await _userDoc.set({
      'isPremium':  status.isPremium,
      'plan':       status.activePlan.name,
      'expiryDate': status.expiryDate?.toIso8601String(),
      'updatedAt':  FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> onPurchaseConfirmed(SubscriptionStatus status) =>
      onEntitlementUpdated(status);

  @override
  Future<void> onRestoreCompleted(SubscriptionStatus status) =>
      onEntitlementUpdated(status);

  @override
  Future<SubscriptionStatus?> fetchRemoteEntitlement() async {
    // Return null to let the store decide.
    // Or map your Firestore document to a SubscriptionStatus hint here.
    return null;
  }
}
```

### 2. Pass it to `init()`

```dart
await Monetization.init(
  MonetizationConfig(
    android: AndroidProducts( ... ),
    ios: IOSProducts( ... ),
    syncDelegate: FirestoreSyncDelegate(
      db: FirebaseFirestore.instance,
      userId: FirebaseAuth.instance.currentUser!.uid,
    ),
  ),
);
```

The delegate receives calls at these moments:

| Hook | When it fires |
|---|---|
| `onPurchaseConfirmed` | A new purchase is verified by the store |
| `onEntitlementUpdated` | Any time the local entitlement state changes |
| `onRestoreCompleted` | After a restore flow finishes |
| `fetchRemoteEntitlement` | During `init()` — return a status hint or `null` |

---

## Analytics (Optional)

```dart
class MyAnalyticsDelegate implements MonetizationAnalyticsDelegate {
  @override
  Future<void> onPurchaseStarted(SubscriptionPlan plan) async {
    await FirebaseAnalytics.instance
        .logEvent(name: 'purchase_started', parameters: {'plan': plan.name});
  }

  @override
  Future<void> onPurchaseCompleted(PurchaseResult result) async {
    if (result is PurchaseSuccess) {
      await FirebaseAnalytics.instance.logPurchase(currency: 'USD', value: 0);
    }
  }

  @override
  Future<void> onRestoreStarted() async {
    await FirebaseAnalytics.instance.logEvent(name: 'restore_started');
  }

  @override
  Future<void> onRestoreCompleted(int restoredCount) async {
    await FirebaseAnalytics.instance.logEvent(
      name: 'restore_completed',
      parameters: {'count': restoredCount},
    );
  }

  @override
  Future<void> onEntitlementChanged(SubscriptionStatus status) async {
    await FirebaseAnalytics.instance.logEvent(
      name: 'entitlement_changed',
      parameters: {
        'status': status.entitlementStatus.name,
        'plan':   status.activePlan.name,
      },
    );
  }
}
```

Pass it to `init()`:

```dart
await Monetization.init(
  MonetizationConfig(
    ...
    analyticsDelegate: MyAnalyticsDelegate(),
  ),
);
```

---

## Custom Storage (Optional)

By default the SDK persists entitlement to `SharedPreferences`. Swap it for encrypted
storage or any other backend by implementing `EntitlementStorage`:

```dart
class SecureStorage implements EntitlementStorage {
  final _storage = const FlutterSecureStorage();

  @override
  Future<void> save(SubscriptionStatus status) async {
    await _storage.write(
      key: 'entitlement',
      value: jsonEncode(status.toJson()),
    );
  }

  @override
  Future<SubscriptionStatus?> load() async {
    final raw = await _storage.read(key: 'entitlement');
    if (raw == null) return null;
    return SubscriptionStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> clear() => _storage.delete(key: 'entitlement');
}
```

Inject it as the second argument to `init()`:

```dart
await Monetization.init(
  MonetizationConfig( ... ),
  storage: SecureStorage(),
);
```

---

## Configuration Reference

```dart
MonetizationConfig(
  // ── Required ──────────────────────────────────────────
  android: AndroidProducts(
    monthly:  'your_android_monthly_id',
    yearly:   'your_android_yearly_id',
    lifetime: 'your_android_lifetime_id',
  ),
  ios: IOSProducts(
    monthly:  'your_ios_monthly_id',
    yearly:   'your_ios_yearly_id',
    lifetime: 'your_ios_lifetime_id',
  ),

  // ── Optional ──────────────────────────────────────────
  syncDelegate:       MyFirestoreSyncDelegate(),  // default: null
  analyticsDelegate:  MyAnalyticsDelegate(),      // default: null
  logLevel:           MonetizationLogLevel.info,  // default: info
  autoRestoreOnInit:  true,                       // default: true
  entitlementCacheTtl: const Duration(hours: 24), // default: 24 h
  gracePeriodDuration: const Duration(days: 16),  // default: 16 d
)
```

### Log levels

| Value | Use when |
|---|---|
| `MonetizationLogLevel.none` | Production release builds |
| `MonetizationLogLevel.error` | Staging — errors only |
| `MonetizationLogLevel.warning` | Staging — errors + warnings |
| `MonetizationLogLevel.info` | Default — normal lifecycle events |
| `MonetizationLogLevel.debug` | Development — everything |

---

## Troubleshooting

**`MonetizationNotInitializedException` at startup**

You called `Monetization.instance` before `await Monetization.init(...)` completed.
Make sure `init()` is awaited at the top of `main()`.

---

**Products not loading / store returns empty list**

- Confirm the product IDs in `MonetizationConfig` exactly match what is registered in
  Google Play Console / App Store Connect — character for character.
- On Android, your app must be uploaded to at least the Internal Testing track.
- On iOS, you must accept the Paid Applications agreement in App Store Connect.
- Use a physical device and a sandbox/test account — simulators often fail IAP.

---

**`isPremium` is `false` right after a successful purchase**

The purchase confirmation arrives asynchronously from the store. Listen to
`purchaseResultStream` for the final `PurchaseSuccess` event rather than reading
`isPremium` immediately after `purchase()` returns.

---

**Restore does nothing on Android**

Google Play restores purchases automatically when the app is reinstalled.
`restorePurchases()` on Android triggers the same background flow — the result
arrives via the stream, not as an immediate return value.

---

**Status stays `unknown` forever**

The store is unreachable (no internet, sandbox not configured, or product IDs wrong).
Check the debug logs with `logLevel: MonetizationLogLevel.debug` to see the exact error.

---

**Sign-out / multi-account support**

```dart
await Monetization.reset();  // clears the instance and disposes all streams
// then call init() again with the new user's sync delegate
await Monetization.init(MonetizationConfig( ... , syncDelegate: newUserDelegate));
```

---

## Running Tests

```bash
flutter test
```

Expected:

```
00:00 +41: All tests passed!
```

---

## Dependencies

| Package | Role |
|---|---|
| [`in_app_purchase`](https://pub.dev/packages/in_app_purchase) | Google Play + App Store plugin |
| [`shared_preferences`](https://pub.dev/packages/shared_preferences) | Local entitlement cache |
| [`rxdart`](https://pub.dev/packages/rxdart) | `BehaviorSubject` for reactive stream |
| [`equatable`](https://pub.dev/packages/equatable) | Value equality on `SubscriptionStatus` |

Firebase, AdMob, and analytics SDKs are **not included** — inject them through the
delegate interfaces so this package stays dependency-free.

---

## License

MIT — see [LICENSE](LICENSE).
