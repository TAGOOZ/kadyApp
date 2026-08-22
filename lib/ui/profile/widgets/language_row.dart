// Language row (#011): العربية / English segmented control wired to the
// global locale switcher via SessionController.setLang (persists globally).
// Content-only: the screen supplies the card chrome and section title.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/session_controller.dart';

class LanguageRow extends ConsumerWidget {
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AppStrings.of(lang);

    return Row(
      children: [
        Expanded(
          child: Text(strings.languageLabel, style: AppTextStyles.bodyLg),
        ),
        SegmentedButton<AppLang>(
          key: const Key('profile_language_segmented'),
          segments: [
            ButtonSegment(value: AppLang.ar, label: Text(strings.langAr)),
            ButtonSegment(value: AppLang.en, label: Text(strings.langEn)),
          ],
          selected: {lang},
          onSelectionChanged: (selection) {
            ref
                .read(sessionControllerProvider.notifier)
                .setLang(selection.first);
          },
        ),
      ],
    );
  }
}
