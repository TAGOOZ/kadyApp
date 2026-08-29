// RiskEngine provider — deep module seam for risk preview (RISK-09/10).
// Loads RiskConfig + risk_rules catalog with fallback, exposes single RiskEngine.
// Mirrors loyalty_gateway.dart offline policy: fetch fails → fallback constants.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/risk_engine.dart';

Future<RiskConfig> _fetchRiskConfig() async {
  try {
    final rows = await supabase.from('app_config').select('key, value').inFilter('key', [
      'risk.low_max_score',
      'risk.medium_max_score',
      'risk.large_order_threshold',
      'risk.rapid_orders_count',
      'risk.rapid_orders_window_minutes',
    ]) as List;
    final map = <String, dynamic>{
      for (final r in rows.cast<Map>()) r['key'] as String: r['value'],
    };
    return RiskConfig.fromMap(map);
  } catch (_) {
    return RiskConfig.fallback;
  }
}

Future<List<RiskRule>> _fetchRiskRules() async {
  try {
    final rows = await supabase.from('risk_rules').select('rule_code, score, enabled, is_extrinsic') as List;
    return [
      for (final r in rows.cast<Map>())
        RiskRule(
          code: RuleCodeX.fromWire(r['rule_code'] as String),
          score: (r['score'] as num).toInt(),
          enabled: r['enabled'] as bool? ?? true,
          isExtrinsic: r['is_extrinsic'] as bool? ?? false,
          description: null,
        ),
    ];
  } catch (_) {
    return kDefaultRiskRules;
  }
}

final riskConfigProvider = FutureProvider<RiskConfig>((ref) => _fetchRiskConfig());

final riskRulesProvider = FutureProvider<List<RiskRule>>((ref) => _fetchRiskRules());

/// Deep Risk module — one evaluate hides config/catalog + extrinsic cap.
/// Leverage: one interface, N callers (checkout preview, staff queue, admin tuning).
final riskEngineProvider = FutureProvider<RiskEngine>((ref) async {
  final cfg = await ref.watch(riskConfigProvider.future).catchError((_) => RiskConfig.fallback);
  final rules = await ref.watch(riskRulesProvider.future).catchError((_) => kDefaultRiskRules);
  return RiskEngine(config: cfg, rules: rules);
});
