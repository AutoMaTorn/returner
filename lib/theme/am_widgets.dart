// automatorn — виджеты, которых нет в Material или которые выглядят иначе.
// Всё остальное (FilledButton, OutlinedButton, TextField, Checkbox, Switch,
// TabBar, AlertDialog, PopupMenuButton, SnackBar) уже настроено темой
// в automatorn_theme.dart — используйте стандартные виджеты.
//
// Зависимость: flutter_svg (для AmIcon).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'automatorn_theme.dart';

/// Короткий доступ к цветам системы: `context.am.ink`.
extension AmContext on BuildContext {
  AmColors get am => Theme.of(this).extension<AmColors>()!;
}

/// Сигнал: нейтральный, успех, предупреждение, ошибка.
enum AmTone { neutral, success, warning, danger }

extension on AmTone {
  Color color(AmColors c) => switch (this) {
        AmTone.neutral => c.ink,
        AmTone.success => c.success,
        AmTone.warning => c.warning,
        AmTone.danger => c.danger,
      };

  Color border(AmColors c) => this == AmTone.neutral ? c.ruleStrong : color(c);

  /// Знак состояния — всегда рядом со словом: по светлоте danger и success не различаются.
  String get mark => switch (this) {
        AmTone.neutral => '',
        AmTone.success => '✓',
        AmTone.warning => '~',
        AmTone.danger => '!',
      };
}

/// Иконка из assets/icons (сетка 24, обводка 2). По умолчанию — цвет `muted`.
class AmIcon extends StatelessWidget {
  const AmIcon(this.name, {super.key, this.size = 16, this.color, this.semanticLabel});

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? context.am.muted;
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}

/// Метка раздела или поля: строчными, 12px, `muted`.
class AmLabel extends StatelessWidget {
  const AmLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Automatorn.label.copyWith(color: context.am.muted));
}

/// Тихая кнопка в скобках: `[отмена]`. Цвет `muted`, на наведении — `ink`.
class AmGhostButton extends StatelessWidget {
  const AmGhostButton({super.key, required this.label, required this.onPressed, this.small = false});

  final String label;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size(0, small ? AmSize.controlSize : AmSize.controlHeight),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? c.ink : c.muted,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(small ? Automatorn.label : Automatorn.code),
      ),
      child: Text('[$label]'),
    );
  }
}

/// Ссылка в прозе: `[текст]`, `muted` → `ink` на наведении, без подчёркивания и движения.
class AmBracketLink extends StatefulWidget {
  const AmBracketLink({super.key, required this.text, required this.onTap, this.style});

  final String text;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  State<AmBracketLink> createState() => _AmBracketLinkState();
}

class _AmBracketLinkState extends State<AmBracketLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: AmSize.ease,
          style: (widget.style ?? Automatorn.prose).copyWith(color: _hover ? c.ink : c.muted),
          child: Text('[${widget.text}]'),
        ),
      ),
    );
  }
}

/// Строка списка: название слева (`ink`), мета справа (`muted`, 12px) — как «проекты» на сайте.
class AmListRow extends StatelessWidget {
  const AmListRow({super.key, required this.title, this.meta, this.onTap});

  final String title;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(title, style: Automatorn.prose.copyWith(color: c.ink))),
            if (meta != null) ...[
              const SizedBox(width: 16),
              Text(meta!, style: Automatorn.meta.copyWith(color: c.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Уведомление в потоке: рамка 1px, заголовок строчными со знаком, текст `text`.
/// Без заливки и без цветной полосы слева.
class AmNotice extends StatelessWidget {
  const AmNotice({super.key, required this.title, required this.body, this.tone = AmTone.neutral});

  final String title;
  final String body;
  final AmTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final icon = switch (tone) {
      AmTone.success => 'check',
      AmTone.neutral => 'info',
      _ => 'alert',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: tone.border(c)),
        borderRadius: BorderRadius.circular(AmSize.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AmIcon(icon, size: 14, color: tone.color(c)),
            const SizedBox(width: 8),
            Flexible(child: Text(title, style: Automatorn.label.copyWith(color: tone.color(c), height: 16 / 12))),
          ]),
          const SizedBox(height: 4),
          Text(body, style: Automatorn.code.copyWith(color: c.text)),
        ],
      ),
    );
  }
}

/// Тег: рамка `rule-strong`, 11px, строчными. Статус — со знаком и сигнальным цветом.
class AmTag extends StatelessWidget {
  const AmTag(this.text, {super.key, this.tone = AmTone.neutral, this.onRemove});

  final String text;
  final AmTone tone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final fg = tone == AmTone.neutral ? c.text : tone.color(c);
    final label = tone == AmTone.neutral ? text : '${tone.mark} $text';
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border.all(color: tone.border(c)),
        borderRadius: BorderRadius.circular(AmSize.radiusFocus),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Automatorn.footer.copyWith(color: fg, height: 1)),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          GestureDetector(onTap: onRemove, child: AmIcon('close', size: 12, color: c.muted)),
        ],
      ]),
    );
  }
}

/// Панель приложения: `surface`, рамка `rule`, шапка 40px с меткой и действием.
class AmPanel extends StatelessWidget {
  const AmPanel({super.key, required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.rule),
        borderRadius: BorderRadius.circular(AmSize.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.ruleFaint))),
            child: Row(children: [
              Expanded(child: AmLabel(title)),
              if (action != null) action!,
            ]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16), child: child),
        ],
      ),
    );
  }
}

/// Текстовая шкала прогресса: `индексация  [########--------]  50%`.
class AmAsciiProgress extends StatelessWidget {
  const AmAsciiProgress({super.key, required this.value, this.label, this.width = 20});

  /// От 0 до 1.
  final double value;
  final String? label;
  final int width;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final filled = (value.clamp(0.0, 1.0) * width).round();
    final pct = '${(value.clamp(0.0, 1.0) * 100).round()}%'.padLeft(4);
    final style = Automatorn.meta.copyWith(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]);
    return Text.rich(
      TextSpan(style: style, children: [
        if (label != null) TextSpan(text: '$label  '),
        const TextSpan(text: '['),
        TextSpan(text: '#' * filled, style: TextStyle(color: c.ink)),
        TextSpan(text: '-' * (width - filled)),
        TextSpan(text: ']  $pct'),
      ]),
      semanticsLabel: '${label ?? ''} $pct',
    );
  }
}

/// Пустое состояние: метка, одна-две фразы прозой, одно-два действия. Без картинок.
class AmEmptyState extends StatelessWidget {
  const AmEmptyState({super.key, required this.label, required this.text, this.actions = const []});

  final String label;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AmLabel(label),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(text, style: Automatorn.prose.copyWith(color: context.am.text)),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Тост: `showAmToast(context, 'Резюме сохранено', tone: AmTone.success)`.
void showAmToast(
  BuildContext context,
  String message, {
  AmTone tone = AmTone.neutral,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final c = context.am;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: tone == AmTone.danger ? const Duration(days: 1) : const Duration(seconds: 4),
      showCloseIcon: tone == AmTone.danger,
      closeIconColor: c.muted,
      width: 360,
      content: Row(children: [
        if (tone != AmTone.neutral) ...[
          Text(tone.mark, style: Automatorn.meta.copyWith(color: tone.color(c))),
          const SizedBox(width: 12),
        ],
        Expanded(child: Text(message, style: Automatorn.meta.copyWith(color: c.text))),
      ]),
      action: actionLabel == null ? null : SnackBarAction(label: '[$actionLabel]', onPressed: onAction ?? () {}),
    ),
  );
}

/// Колонка для чтения: 560px, прижата влево внутри центра, поля 20/30px.
class AmColumn extends StatelessWidget {
  const AmColumn({super.key, required this.children, this.gap = AmSize.gapStack});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AmSize.measure),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка списка: иконка в квадрате 32 с рамкой, название и детали, справа — дата, тег или стрелка.
/// Для файлов, устройств, задач, сообщений.
class AmListItem extends StatelessWidget {
  const AmListItem({super.key, required this.title, this.subtitle, this.icon, this.trailing, this.onTap});

  final String title;
  final String? subtitle;
  final String? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.ruleFaint))),
        child: Row(children: [
          if (icon != null) ...[
            Container(
              width: AmSize.controlHeight,
              height: AmSize.controlHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: c.rule),
                borderRadius: BorderRadius.circular(AmSize.radiusControl),
              ),
              child: AmIcon(icon!, color: c.muted),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Automatorn.code.copyWith(color: c.ink)),
              if (subtitle != null)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Automatorn.caption.copyWith(color: c.muted, height: 16 / 12)),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      ),
    );
  }
}

/// «Параметр — значение»: метка строчными слева, значение справа, строки через `ruleFaint`.
class AmKeyValue extends StatelessWidget {
  const AmKeyValue(this.rows, {super.key, this.labelWidth = 140});

  /// Пары «метка — значение», например {'версия': '2.4.1', 'сервер': 'eu-1'}.
  final Map<String, String> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in rows.entries)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.ruleFaint))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: labelWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(e.key, style: Automatorn.label.copyWith(color: c.muted)),
                ),
              ),
              Expanded(
                child: SelectableText(
                  e.value,
                  style: Automatorn.code.copyWith(color: c.ink, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

// --- Добавлено в приложении Returner (нет в выгрузке системы) -----------------

/// Ожидание без процента: символы `| / – \` меняются раз в 150 мс, цвет `muted`.
/// Ставится перед текстом действия. При отключённых анимациях замирает.
class AmSpinner extends StatefulWidget {
  const AmSpinner({super.key});

  @override
  State<AmSpinner> createState() => _AmSpinnerState();
}

class _AmSpinnerState extends State<AmSpinner> with SingleTickerProviderStateMixin {
  static const _frames = ['|', '/', '–', r'\'];
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Automatorn.code.copyWith(color: context.am.muted);
    return ExcludeSemantics(
      child: SizedBox(
        width: 10,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Text(
            _frames[(_controller.value * _frames.length).floor() % _frames.length],
            style: style,
          ),
        ),
      ),
    );
  }
}
