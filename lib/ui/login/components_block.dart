import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/components.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';

/// Shows the one-time download of the components a first sign-in needs.
/// Renders nothing once they are in place.
class ComponentsBlock extends ConsumerWidget {
  const ComponentsBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(componentsProvider);
    final fraction = state.fraction;
    final c = context.am;
    final error = state.error;

    return switch (state.status) {
      ComponentsStatus.ready => const SizedBox.shrink(),
      ComponentsStatus.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmNotice(
            tone: AmTone.danger,
            title: S.componentsFailed,
            body: error == null ? S.componentsFailedHint : S.errorText(error),
          ),
          if (error != null) ...[
            const SizedBox(height: AmSize.fieldGap),
            Text(
              S.componentsFailedHint,
              style: Automatorn.caption.copyWith(color: c.muted),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: ref.read(componentsProvider.notifier).ensure,
            child: const Text(S.componentsRetry),
          ),
          const SizedBox(height: AmSize.formGap),
        ],
      ),
      ComponentsStatus.checking || ComponentsStatus.downloading => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AmLabel(S.componentsLabel),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AmSpinner(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(switch ((state.status, state.stage)) {
                  (ComponentsStatus.checking, _) => S.componentsChecking,
                  (_, final stage?) => S.componentsDownloading(stage),
                  _ => S.componentsStarting,
                }, style: Automatorn.code.copyWith(color: c.text)),
              ),
            ],
          ),
          if (state.status == ComponentsStatus.downloading) ...[
            if (fraction != null) ...[
              const SizedBox(height: 8),
              AmAsciiProgress(value: fraction),
            ],
            if (state.bytes > 0) ...[
              const SizedBox(height: 4),
              Text(
                [
                  S.componentsAmount(state.bytes, state.total),
                  if (fraction != null) S.componentsRemaining(state.remaining),
                ].join(' · '),
                style: Automatorn.meta.copyWith(color: c.muted),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              S.componentsWhy,
              style: Automatorn.caption.copyWith(color: c.muted),
            ),
          ],
          const SizedBox(height: AmSize.formGap),
        ],
      ),
    };
  }
}
