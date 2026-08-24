// ignore_for_file: use_null_aware_elements
// Zones editor panel — zoned delivery fees (FEATURES §11.7).
// Flat `delivery_fee` in app_config is edited in Rules; polygon fees in
// `public.zones` (0009_zones.sql) are CRUD here. Map preview via flutter_map.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/maps/maps_config.dart';
import '../../../core/maps/maps_preview.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';

class ZonesEditorPanel extends ConsumerStatefulWidget {
  const ZonesEditorPanel({super.key, required this.strings, required this.onAccessDenied});
  final AdminStrings strings;
  final VoidCallback onAccessDenied;
  @override
  ConsumerState<ZonesEditorPanel> createState() => _ZonesEditorPanelState();
}

class _ZonesEditorPanelState extends ConsumerState<ZonesEditorPanel> {
  List<Map<String, dynamic>>? _zones;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.from('zones').select().order('fee');
      if (!mounted) return;
      setState(() {
        _zones = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<LatLng>? _parsePolygon(Object? raw) {
    if (raw == null) return null;
    try {
      dynamic data = raw;
      if (data is String) data = jsonDecode(data);
      // GeoJSON Polygon: {type: Polygon, coordinates: [[[lng,lat],...]]}
      if (data is Map && data['coordinates'] is List) {
        final coords = data['coordinates'] as List;
        final ring = coords.isNotEmpty ? coords[0] as List : coords;
        return [
          for (final p in ring)
            if (p is List && p.length >= 2) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
        ];
      }
      if (data is List) {
        // List of [lat,lng] or {lat,lng}
        return [
          for (final p in data)
            if (p is List && p.length >= 2) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())
            else if (p is Map && p['lat'] != null && p['lng'] != null)
              LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
        ];
      }
    } catch (_) {}
    return null;
  }

  Future<void> _deleteZone(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.strings.delete),
        content: Text(widget.strings.deleteItemBodyFn('Zone')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(widget.strings.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(widget.strings.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    final zones = _zones;
    if (zones == null) return;
    final idx = zones.indexWhere((z) => z['id'] == id);
    if (idx < 0) return;
    final prev = List<Map<String, dynamic>>.from(zones);
    setState(() => _zones!.removeAt(idx));
    try {
      await supabase.from('zones').delete().eq('id', id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.saved)));
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _zones = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.revertedError)));
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? zone}) async {
    final isEdit = zone != null;
    final nameArCtrl = TextEditingController(text: zone?['name_ar'] as String? ?? '');
    final nameEnCtrl = TextEditingController(text: zone?['name_en'] as String? ?? '');
    final feeCtrl = TextEditingController(text: (zone?['fee']?.toString() ?? '15'));
    final polygonCtrl = TextEditingController(text: zone?['polygon'] == null ? '' : jsonEncode(zone!['polygon']));
    final formKey = GlobalKey<FormState>();
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm16),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isEdit ? widget.strings.edit : widget.strings.addItem, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm16),
                TextFormField(
                  controller: nameArCtrl,
                  decoration: InputDecoration(labelText: widget.strings.fieldNameAr, border: const OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? widget.strings.nameRequiredError : null,
                ),
                const SizedBox(height: AppSpacing.xs8),
                TextFormField(
                  controller: nameEnCtrl,
                  decoration: InputDecoration(labelText: widget.strings.fieldNameEn, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.xs8),
                TextFormField(
                  controller: feeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: 'Fee (EGP) / سعر (ج.م)', border: const OutlineInputBorder()),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return widget.strings.priceInvalidError;
                    final n = int.tryParse(v.trim());
                    if (n == null) return widget.strings.priceInvalidError;
                    if (n < 0) return widget.strings.pricePositiveError;
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.xs8),
                TextFormField(
                  controller: polygonCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Polygon JSON (GeoJSON Polygon) — اختياري',
                    hintText: '{"type":"Polygon","coordinates":[[[31.0,29.0],...]]}',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs8),
                if (isEdit && _parsePolygon(zone['polygon']) != null)
                  MapsPreview(height: 160, polygonPoints: _parsePolygon(zone['polygon']), markers: const []),
                const SizedBox(height: AppSpacing.sm16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: Text(widget.strings.cancel)),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        dynamic polygon;
                        final raw = polygonCtrl.text.trim();
                        if (raw.isNotEmpty) {
                          try {
                            polygon = jsonDecode(raw);
                          } catch (_) {
                            polygon = raw;
                          }
                        }
                        Navigator.of(ctx).pop({
                          'name_ar': nameArCtrl.text.trim(),
                          'name_en': nameEnCtrl.text.trim().isEmpty ? null : nameEnCtrl.text.trim(),
                          'fee': int.parse(feeCtrl.text.trim()),
                          if (polygon != null) 'polygon': polygon,
                        });
                      },
                      child: Text(widget.strings.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    try {
      if (isEdit) {
        await supabase.from('zones').update(result).eq('id', zone['id']);
      } else {
        await supabase.from('zones').insert(result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.saved)));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.revertedError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final allPolygons = <LatLng>[];
    if (_zones != null) {
      for (final z in _zones!) {
        final pts = _parsePolygon(z['polygon']);
        if (pts != null) allPolygons.addAll(pts);
      }
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        children: [
          Card(
            color: AppColors.parchment.withValues(alpha: 0.6),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs8),
                  Expanded(child: Text('Zones — flat fee in Rules is live. Polygon preview via map. Zones / منطقة / سعر', style: AppTextStyles.bodySm)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          MapsPreview(
            height: 200,
            center: allPolygons.isNotEmpty ? allPolygons.first : elkadyCafeLatLng,
            polygonPoints: allPolygons.isEmpty ? null : allPolygons,
            markers: allPolygons.isEmpty ? const [] : [Marker(point: elkadyCafeLatLng, width: 36, height: 36, child: Icon(Icons.local_cafe, color: AppColors.primary, size: 28))],
          ),
          const SizedBox(height: AppSpacing.xs8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(widget.strings.addItem),
              onPressed: () => _openEditor(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          if (_zones == null || _zones!.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(widget.strings.noData)))
          else
            for (final z in _zones!)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(z['name_ar'] as String? ?? '—', style: AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(z['name_en'] as String? ?? '', style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primaryContainer.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.pill)),
                                child: Text('${z['fee']} ${widget.strings.currencySuffix} / zonas / منطقة', style: AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
                              ),
                              const Spacer(),
                              if (z['polygon'] != null) const Icon(Icons.map_outlined, size: 16, color: AppColors.outline),
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: widget.strings.edit, onPressed: () => _openEditor(zone: z)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error), tooltip: widget.strings.delete, onPressed: () => _deleteZone(z['id'] as String)),
                        ],
                      ),
                    ),
                    if (_parsePolygon(z['polygon']) != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: MapsPreview(height: 140, polygonPoints: _parsePolygon(z['polygon']), center: _parsePolygon(z['polygon'])!.first),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
