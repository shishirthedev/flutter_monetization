import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_status.dart';
import '../utils/monetization_logger.dart';

/// Abstraction over local cache so implementations can be swapped
/// (e.g., encrypted storage in high-security apps).
abstract interface class EntitlementStorage {
  Future<void> save(SubscriptionStatus status);
  Future<SubscriptionStatus?> load();
  Future<void> clear();
}

/// [SharedPreferences]-backed implementation of [EntitlementStorage].
///
/// The cached value is used ONLY as a startup hint to avoid a blank loading
/// screen. The store is always re-queried on init. Do NOT trust cached state
/// alone for premium gating.
class SharedPreferencesEntitlementStorage implements EntitlementStorage {
  SharedPreferencesEntitlementStorage({
    SharedPreferences? prefs,
  }) : _prefsOrNull = prefs;

  static const _kEntitlementKey = 'flutter_monetization_entitlement_v2';

  SharedPreferences? _prefsOrNull;

  Future<SharedPreferences> get _prefs async {
    _prefsOrNull ??= await SharedPreferences.getInstance();
    return _prefsOrNull!;
  }

  @override
  Future<void> save(SubscriptionStatus status) async {
    try {
      final prefs = await _prefs;
      final json = jsonEncode(status.toJson());
      await prefs.setString(_kEntitlementKey, json);
      logger.debug('Entitlement saved to local cache.');
    } catch (e, st) {
      logger.error('Failed to save entitlement to cache', e, st);
      // Non-fatal: store is always the source of truth.
    }
  }

  @override
  Future<SubscriptionStatus?> load() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_kEntitlementKey);
      if (raw == null || raw.isEmpty) return null;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      final status = SubscriptionStatus.fromJson(map);
      logger.debug('Entitlement loaded from local cache: $status');
      return status;
    } catch (e, st) {
      logger.error('Failed to load entitlement from cache', e, st);
      // Corrupted cache — treat as no cache.
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(_kEntitlementKey);
      logger.debug('Entitlement cache cleared.');
    } catch (e, st) {
      logger.error('Failed to clear entitlement cache', e, st);
    }
  }
}
