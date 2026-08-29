// QR scanner sheet for staff check-in (FEATURES §11.31).
// Uses `mobile_scanner` to capture a Customer QR (phone hash) and returns
// the raw scan value via Navigator.pop. The caller parses it with
// `parseQrPhone` and applies it to the check-in form.
// The widget handles loading / error (camera unavailable) and a manual
// close affordance. A parchment placeholder is shown while the camera warms.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_staff.dart';
import '../../../core/theme/app_theme.dart';

class QrScannerSheet extends ConsumerStatefulWidget {
  const QrScannerSheet({super.key});

  @override
  ConsumerState<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends ConsumerState<QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _handled = true;
    _controller.stop();
    if (mounted) Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final strings = StaffStrings.of(ref.watch(localeNotifierProvider));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text(strings.qrScannerTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SizedBox(
            height: 320,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.gutter16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam_off_outlined,
                          size: 48, color: AppColors.outline),
                      const SizedBox(height: AppSpacing.xs8),
                      Text(
                        strings.cameraUnavailable,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs8),
                      Text(
                        error.errorDetails?.message ?? '',
                        style: AppTextStyles.bodySm,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm16),
            child: Text(
              strings.qrHint,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> showQrScannerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QrScannerSheet(),
  );
}
