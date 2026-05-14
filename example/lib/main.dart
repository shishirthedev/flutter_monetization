// flutter_monetization — Example App
//
// Demonstrates:
//  - Package initialization with configurable product IDs
//  - Reactive status stream (BehaviorSubject)
//  - Purchase flow for monthly, yearly, and lifetime plans
//  - Restore purchases
//  - isPremium hook for AdMob integration
//  - Custom FirestoreSyncDelegate example (stub — no Firebase dependency here)
//  - Custom AnalyticsDelegate example (stub)
//  - Entitlement-gated UI

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_monetization/flutter_monetization.dart';

// ---------------------------------------------------------------------------
// Optional delegate implementations (normally in your app, not this package)
// ---------------------------------------------------------------------------

/// Example Firestore sync delegate stub.
/// In production: inject FirebaseFirestore + userId.
class ExampleFirestoreSyncDelegate implements MonetizationSyncDelegate {
  @override
  Future<void> onEntitlementUpdated(SubscriptionStatus status) async {
    debugPrint('[Firestore] Entitlement updated: $status');
    // await db.collection('users').doc(userId).update({...});
  }

  @override
  Future<void> onRestoreCompleted(SubscriptionStatus status) async {
    debugPrint('[Firestore] Restore completed: $status');
  }

  @override
  Future<void> onPurchaseConfirmed(SubscriptionStatus status) async {
    debugPrint('[Firestore] Purchase confirmed: $status');
    // await db.collection('users').doc(userId).set({
    //   'isPremium': true,
    //   'plan': status.activePlan.name,
    //   'expiryDate': status.expiryDate?.toIso8601String(),
    // }, SetOptions(merge: true));
  }

  @override
  Future<SubscriptionStatus?> fetchRemoteEntitlement() async {
    debugPrint('[Firestore] Fetching remote entitlement...');
    // final doc = await db.collection('users').doc(userId).get();
    // Map to SubscriptionStatus here
    return null; // null = defer to store
  }
}

/// Example Analytics delegate stub.
class ExampleAnalyticsDelegate implements MonetizationAnalyticsDelegate {
  @override
  Future<void> onPurchaseStarted(SubscriptionPlan plan) async {
    debugPrint('[Analytics] purchase_started: ${plan.name}');
  }

  @override
  Future<void> onPurchaseCompleted(PurchaseResult result) async {
    debugPrint('[Analytics] purchase_completed: $result');
  }

  @override
  Future<void> onRestoreStarted() async {
    debugPrint('[Analytics] restore_started');
  }

  @override
  Future<void> onRestoreCompleted(int restoredCount) async {
    debugPrint('[Analytics] restore_completed: $restoredCount');
  }

  @override
  Future<void> onEntitlementChanged(SubscriptionStatus status) async {
    debugPrint('[Analytics] entitlement_changed: ${status.entitlementStatus.name}');
  }
}

// ---------------------------------------------------------------------------
// App entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: Initialize Firebase here before SDK init
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Monetization.init(
    MonetizationConfig(
      android: const AndroidProducts(
        monthly: 'com.example.myapp.premium_monthly',
        yearly: 'com.example.myapp.premium_yearly',
        lifetime: 'com.example.myapp.premium_lifetime',
      ),
      ios: const IOSProducts(
        monthly: 'com.example.myapp.premium_monthly',
        yearly: 'com.example.myapp.premium_yearly',
        lifetime: 'com.example.myapp.premium_lifetime',
      ),
      syncDelegate: ExampleFirestoreSyncDelegate(),
      analyticsDelegate: ExampleAnalyticsDelegate(),
      logLevel: MonetizationLogLevel.debug,
    ),
  );

  runApp(const MyApp());
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monetization Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen (entitlement-gated)
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SubscriptionStatus _status = SubscriptionStatus.unknown();

  @override
  void initState() {
    super.initState();

    // Subscribe to reactive status updates
    Monetization.instance.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);

      // AdMob integration hook: disable/enable ads based on premium state
      _handleAdMobIntegration(status.isPremium);
    });
  }

  void _handleAdMobIntegration(bool isPremium) {
    if (isPremium) {
      debugPrint('[AdMob] User is premium — do NOT load ads.');
      // adController.disable();
    } else {
      debugPrint('[AdMob] User is not premium — load ads.');
      // adController.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monetization Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Restore Purchases',
            onPressed: _onRestore,
          ),
        ],
      ),
      body: _status.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _EntitlementCard(status: _status),
        const SizedBox(height: 24),
        if (!_status.isPremium) ...[
          const Text(
            'Choose a Plan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            title: 'Monthly',
            subtitle: 'Billed monthly. Cancel anytime.',
            plan: SubscriptionPlan.monthly,
            onTap: _onPurchase,
          ),
          _PlanCard(
            title: 'Yearly',
            subtitle: 'Best value. Billed annually.',
            plan: SubscriptionPlan.yearly,
            onTap: _onPurchase,
          ),
          _PlanCard(
            title: 'Lifetime',
            subtitle: 'One-time purchase. Never expires.',
            plan: SubscriptionPlan.lifetime,
            onTap: _onPurchase,
          ),
        ] else
          _PremiumContent(status: _status),
      ],
    );
  }

  Future<void> _onPurchase(SubscriptionPlan plan) async {
    final result = await Monetization.instance.purchase(plan: plan);
    if (!mounted) return;

    switch (result) {
      case PurchasePending():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processing purchase...')),
        );
        // Listen to purchaseResultStream for the final outcome:
        unawaited(
          Monetization.instance.purchaseResultStream.first.then((finalResult) {
            if (!mounted) return;
            _handleFinalPurchaseResult(finalResult);
          }),
        );

      case PurchaseSuccess():
        _handleFinalPurchaseResult(result);

      case PurchaseFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: $message')),
        );

      case PurchaseCancelled():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase cancelled.')),
        );

      case RestoreResult():
        break; // Not expected from purchase()
    }
  }

  void _handleFinalPurchaseResult(PurchaseResult result) {
    if (!mounted) return;
    switch (result) {
      case PurchaseSuccess(:final plan):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '✅ ${plan.displayName} purchase successful! Welcome to premium.')),
        );
      case PurchaseFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Purchase failed: $message')),
        );
      default:
        break;
    }
  }

  Future<void> _onRestore() async {
    final result = await Monetization.instance.restorePurchases();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.restored
              ? '✅ Restored ${result.restoredCount} purchase(s).'
              : result.hasError
                  ? '❌ Restore failed: ${result.error}'
                  : 'No previous purchases found.',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _EntitlementCard extends StatelessWidget {
  const _EntitlementCard({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.isPremium ? Colors.green : Colors.grey;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  status.isPremium ? Icons.star : Icons.star_border,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  status.isPremium ? 'Premium Active' : 'Free Plan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Row('Status', status.entitlementStatus.displayName),
            _Row('Plan', status.activePlan.displayName),
            _Row('Platform', status.platformSource.displayName),
            if (status.expiryDate != null)
              _Row(
                'Expires',
                status.expiryDate!.toLocal().toString().split('.').first,
              ),
            if (status.lastVerifiedAt != null)
              _Row(
                'Last Verified',
                status.lastVerifiedAt!.toLocal().toString().split('.').first,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.subtitle,
    required this.plan,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final SubscriptionPlan plan;
  final void Function(SubscriptionPlan) onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade100,
          child: Icon(
            plan.isLifetime ? Icons.all_inclusive : Icons.subscriptions,
            color: Colors.indigo,
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: ElevatedButton(
          onPressed: () => onTap(plan),
          child: const Text('Buy'),
        ),
      ),
    );
  }
}

class _PremiumContent extends StatelessWidget {
  const _PremiumContent({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.verified, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        Text(
          'Welcome, Premium Member!',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Plan: ${status.activePlan.displayName}',
          style: const TextStyle(color: Colors.black54),
        ),
        if (status.expiryDate != null && !status.isLifetime)
          Text(
            'Renews: ${status.expiryDate!.toLocal().toString().split('.').first}',
            style: const TextStyle(color: Colors.black54),
          ),
        if (status.isLifetime)
          const Text(
            'Lifetime access — never expires.',
            style: TextStyle(color: Colors.green),
          ),
      ],
    );
  }
}
