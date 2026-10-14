// automatorn — сгенерировано из tokens.json. Не править руками: меняйте токены и перегенерируйте.
// Использование:
//   MaterialApp(theme: Automatorn.light(), darkTheme: Automatorn.dark(), themeMode: ThemeMode.dark)
//   final am = Theme.of(context).extension<AmColors>()!;  // am.ink, am.muted, am.danger…

import 'package:flutter/material.dart';

/// Цвета системы. Есть в теме как ThemeExtension: Theme.of(context).extension<AmColors>().
class AmColors extends ThemeExtension<AmColors> {
  const AmColors({required this.page, required this.ink, required this.text, required this.muted, required this.rule, required this.ruleFaint, required this.selectionBg, required this.surface, required this.scrim, required this.ruleStrong, required this.onInk, required this.danger, required this.success, required this.warning, required this.markerCoral, required this.markerTeal, required this.markerMagenta, required this.markerAmber});

  /// Фон страницы.
  final Color page;
  /// Самое контрастное: названия в списках, заголовки статьи, ссылка на наведении, строка состояния, кольцо фокуса.
  final Color ink;
  /// Проза по умолчанию — цвет body.
  final Color text;
  /// Служебное 11–12px: метки разделов, даты, время чтения, ник, подвал, ссылка в прозе до наведения, скобки.
  final Color muted;
  /// Линия под ссылкой в списках (1px), левая черта у блока кода, линии рисунков.
  final Color rule;
  /// Самые тихие разделители: строки таблиц, черта над подвалом статьи, фон аватара до загрузки.
  final Color ruleFaint;
  /// Фон выделенного текста (::selection) — ink с прозрачностью 8% и 12%.
  final Color selectionBg;
  /// Поверхность всплывающих и рабочих областей: меню, диалог, тост, панели приложений, поля ввода.
  final Color surface;
  /// Затемнение страницы под модальным диалогом.
  final Color scrim;
  /// Рамки контролов: поля, чекбоксы, переключатели, кнопка secondary, тег, клавиша.
  final Color ruleStrong;
  /// Текст и значки на заливке ink: кнопка primary, отмеченный чекбокс, тултип.
  final Color onInk;
  /// Ошибка и разрушительное действие: текст ошибки поля, рамка поля с ошибкой, кнопка danger, уведомление об ошибке.
  final Color danger;
  /// Успех: «сохранено», «готово», выполненный шаг.
  final Color success;
  /// Предупреждение: несохранённые изменения, обрезанный текст, лимит.
  final Color warning;
  /// Маркерная каракуля doodle-loop.
  final Color markerCoral;
  /// Маркерная каракуля doodle-wave.
  final Color markerTeal;
  /// Маркерная каракуля doodle-arrow.
  final Color markerMagenta;
  /// Маркерная каракуля doodle-sparkle.
  final Color markerAmber;

  static const dark = AmColors(
    page: Color(0xFF0C0C0D),
    ink: Color(0xFFEBEBE8),
    text: Color(0xFFB4B4B0),
    muted: Color(0xFF82827D),
    rule: Color(0xFF2A2A29),
    ruleFaint: Color(0xFF1A1A1B),
    selectionBg: Color(0x1FEBEBE8),
    surface: Color(0xFF141416),
    scrim: Color(0xCC0C0C0D),
    ruleStrong: Color(0xFF656562),
    onInk: Color(0xFF0C0C0D),
    danger: Color(0xFFE5533D),
    success: Color(0xFF1F9E83),
    warning: Color(0xFFE0A022),
    markerCoral: Color(0xFFE5533D),
    markerTeal: Color(0xFF1F9E83),
    markerMagenta: Color(0xFFD24A8B),
    markerAmber: Color(0xFFE0A022),
  );

  static const light = AmColors(
    page: Color(0xFFF2F2F0),
    ink: Color(0xFF17181B),
    text: Color(0xFF2C2D31),
    muted: Color(0xFF6A6A66),
    rule: Color(0xFFDCDCD8),
    ruleFaint: Color(0xFFE8E8E5),
    selectionBg: Color(0x1417181B),
    surface: Color(0xFFFAFAF9),
    scrim: Color(0x4017181B),
    ruleStrong: Color(0xFF8A8A86),
    onInk: Color(0xFFF2F2F0),
    danger: Color(0xFFCC321B),
    success: Color(0xFF187A65),
    warning: Color(0xFF8D6414),
    markerCoral: Color(0xFFE5533D),
    markerTeal: Color(0xFF1F9E83),
    markerMagenta: Color(0xFFD24A8B),
    markerAmber: Color(0xFFE0A022),
  );

  @override
  AmColors copyWith({Color? page, Color? ink, Color? text, Color? muted, Color? rule, Color? ruleFaint, Color? selectionBg, Color? surface, Color? scrim, Color? ruleStrong, Color? onInk, Color? danger, Color? success, Color? warning, Color? markerCoral, Color? markerTeal, Color? markerMagenta, Color? markerAmber}) => AmColors(page: page ?? this.page, ink: ink ?? this.ink, text: text ?? this.text, muted: muted ?? this.muted, rule: rule ?? this.rule, ruleFaint: ruleFaint ?? this.ruleFaint, selectionBg: selectionBg ?? this.selectionBg, surface: surface ?? this.surface, scrim: scrim ?? this.scrim, ruleStrong: ruleStrong ?? this.ruleStrong, onInk: onInk ?? this.onInk, danger: danger ?? this.danger, success: success ?? this.success, warning: warning ?? this.warning, markerCoral: markerCoral ?? this.markerCoral, markerTeal: markerTeal ?? this.markerTeal, markerMagenta: markerMagenta ?? this.markerMagenta, markerAmber: markerAmber ?? this.markerAmber);

  @override
  AmColors lerp(AmColors? other, double t) {
    if (other == null) return this;
    return AmColors(page: Color.lerp(page, other.page, t)!, ink: Color.lerp(ink, other.ink, t)!, text: Color.lerp(text, other.text, t)!, muted: Color.lerp(muted, other.muted, t)!, rule: Color.lerp(rule, other.rule, t)!, ruleFaint: Color.lerp(ruleFaint, other.ruleFaint, t)!, selectionBg: Color.lerp(selectionBg, other.selectionBg, t)!, surface: Color.lerp(surface, other.surface, t)!, scrim: Color.lerp(scrim, other.scrim, t)!, ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!, onInk: Color.lerp(onInk, other.onInk, t)!, danger: Color.lerp(danger, other.danger, t)!, success: Color.lerp(success, other.success, t)!, warning: Color.lerp(warning, other.warning, t)!, markerCoral: Color.lerp(markerCoral, other.markerCoral, t)!, markerTeal: Color.lerp(markerTeal, other.markerTeal, t)!, markerMagenta: Color.lerp(markerMagenta, other.markerMagenta, t)!, markerAmber: Color.lerp(markerAmber, other.markerAmber, t)!);
  }
}

/// Размеры, отступы, скругления и кривые.
abstract final class AmSize {
  static const double gapCopy = 16.0;
  static const double gapContent = 40.0;
  static const double gapStack = 40.0;
  static const double radiusFocus = 2.0;
  static const double radiusControl = 4.0;
  static const double radiusAvatar = 6.0;
  static const double radiusPhoto = 10.0;
  static const double radiusPill = 999.0;
  static const double fs2xs = 11.0;
  static const double fsXs = 12.0;
  static const double fsSm = 13.0;
  static const double fsBase = 15.0;
  static const double lhBase = 25.0;
  static const double measure = 560.0;
  static const double collageMax = 1060.0;
  static const double avatarSize = 40.0;
  static const double controlSize = 24.0;
  static const double controlHeight = 32.0;
  static const double fieldGap = 6.0;
  static const double formGap = 20.0;
  static const Curve ease = Cubic(0.2, 0.6, 0.2, 1);
  static const Curve easeSoft = Cubic(0.16, 1, 0.3, 1);
}

abstract final class Automatorn {
  /// Системный моноширинный: SF Mono / Menlo на Apple, Consolas на Windows, системный monospace на Android и Linux.
  static const String fontFamily = 'monospace';
  static const List<String> fontFamilyFallback = ['SF Mono', 'Menlo', 'Consolas', 'Liberation Mono', 'DejaVu Sans Mono', 'Roboto Mono'];

  static const TextStyle prose = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 15.0, height: 1.667, fontWeight: FontWeight.w400);
  static const TextStyle code = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 13.0, height: 1.615, fontWeight: FontWeight.w400);
  static const TextStyle label = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 12.0, height: 1.000, fontWeight: FontWeight.w400, letterSpacing: 0.24);
  static const TextStyle meta = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 12.0, height: 2.083, fontWeight: FontWeight.w400);
  static const TextStyle caption = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 12.0, height: 1.583, fontWeight: FontWeight.w400);
  static const TextStyle footer = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 11.0, height: 1.636, fontWeight: FontWeight.w400, letterSpacing: 0.22);
  static const TextStyle toggle = TextStyle(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, fontSize: 11.0, height: 2.182, fontWeight: FontWeight.w400, letterSpacing: 0.66);

  static ThemeData dark() => _build(Brightness.dark, AmColors.dark);
  static ThemeData light() => _build(Brightness.light, AmColors.light);

  static ThemeData _build(Brightness b, AmColors c) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.ink, onPrimary: c.onInk,
      secondary: c.text, onSecondary: c.page,
      error: c.danger, onError: c.page,
      surface: c.page, onSurface: c.text,
      surfaceContainerLowest: c.page, surfaceContainerLow: c.surface, surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface, surfaceContainerHighest: c.ruleFaint,
      onSurfaceVariant: c.muted, outline: c.ruleStrong, outlineVariant: c.rule,
      shadow: const Color(0xFF000000), scrim: c.scrim,
      inverseSurface: c.ink, onInverseSurface: c.onInk, inversePrimary: c.page,
    );
    final radius = BorderRadius.circular(AmSize.radiusControl);
    OutlineInputBorder border(Color color) => OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color));
    final text = TextTheme(
      bodyLarge: prose.copyWith(color: c.text), bodyMedium: code.copyWith(color: c.text), bodySmall: meta.copyWith(color: c.muted),
      titleLarge: prose.copyWith(color: c.ink), titleMedium: prose.copyWith(color: c.ink), titleSmall: code.copyWith(color: c.ink),
      labelLarge: code.copyWith(color: c.ink), labelMedium: label.copyWith(color: c.muted), labelSmall: footer.copyWith(color: c.muted),
      headlineSmall: prose.copyWith(color: c.ink), displaySmall: prose.copyWith(color: c.ink),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: radius);
    const buttonSize = Size(0, AmSize.controlHeight);
    return ThemeData(
      useMaterial3: true, brightness: b, colorScheme: scheme, extensions: <ThemeExtension<dynamic>>[c],
      scaffoldBackgroundColor: c.page, canvasColor: c.page,
      fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback, textTheme: text,
      splashFactory: NoSplash.splashFactory, highlightColor: Colors.transparent,
      dividerTheme: DividerThemeData(color: c.ruleFaint, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(backgroundColor: c.page, foregroundColor: c.ink, elevation: 0, scrolledUnderElevation: 0, titleTextStyle: prose.copyWith(color: c.ink)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.onInk, minimumSize: buttonSize, shape: buttonShape, textStyle: code, elevation: 0)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.ruleStrong), minimumSize: buttonSize, shape: buttonShape, textStyle: code)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.muted, minimumSize: buttonSize, shape: buttonShape, textStyle: code)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: c.surface, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        labelStyle: label.copyWith(color: c.muted), floatingLabelBehavior: FloatingLabelBehavior.always,
        hintStyle: code.copyWith(color: c.muted), helperStyle: caption.copyWith(color: c.muted), errorStyle: caption.copyWith(color: c.danger),
        border: border(c.ruleStrong), enabledBorder: border(c.ruleStrong), focusedBorder: border(c.ink),
        errorBorder: border(c.danger), focusedErrorBorder: border(c.danger), disabledBorder: border(c.rule),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AmSize.radiusFocus)), side: BorderSide(color: c.ruleStrong),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.surface),
        checkColor: WidgetStatePropertyAll(c.onInk),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.ruleStrong)),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.surface),
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onInk : c.muted),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.ruleStrong),
      ),
      chipTheme: ChipThemeData(backgroundColor: Colors.transparent, side: BorderSide(color: c.ruleStrong), labelStyle: footer.copyWith(color: c.text), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AmSize.radiusFocus))),
      tabBarTheme: TabBarThemeData(labelColor: c.ink, unselectedLabelColor: c.muted, indicatorColor: c.ink, dividerColor: c.ruleFaint, labelStyle: code, unselectedLabelStyle: code, indicatorSize: TabBarIndicatorSize.label),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.rule, linearMinHeight: 4),
      dialogTheme: DialogThemeData(backgroundColor: c.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AmSize.radiusPhoto), side: BorderSide(color: c.rule)), titleTextStyle: prose.copyWith(color: c.ink), contentTextStyle: code.copyWith(color: c.text)),
      popupMenuTheme: PopupMenuThemeData(color: c.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.rule)), textStyle: code.copyWith(color: c.text)),
      snackBarTheme: SnackBarThemeData(backgroundColor: c.surface, contentTextStyle: meta.copyWith(color: c.text), actionTextColor: c.ink, elevation: 0, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.rule))),
      tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(AmSize.radiusFocus)), textStyle: footer.copyWith(color: c.onInk)),
      textSelectionTheme: TextSelectionThemeData(cursorColor: c.ink, selectionColor: c.selectionBg, selectionHandleColor: c.ink),
      listTileTheme: ListTileThemeData(iconColor: c.muted, textColor: c.ink, titleTextStyle: code.copyWith(color: c.ink), subtitleTextStyle: label.copyWith(color: c.muted, height: 16 / 12), leadingAndTrailingTextStyle: label.copyWith(color: c.muted), minVerticalPadding: 8, contentPadding: EdgeInsets.zero, horizontalTitleGap: 12),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: c.page, elevation: 0, height: 64, indicatorColor: Colors.transparent, surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => footer.copyWith(color: s.contains(WidgetState.selected) ? c.ink : c.muted)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 20, color: s.contains(WidgetState.selected) ? c.ink : c.muted))),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: c.page, elevation: 0, indicatorColor: c.ruleFaint, indicatorShape: RoundedRectangleBorder(borderRadius: radius),
        selectedIconTheme: IconThemeData(size: 16, color: c.ink), unselectedIconTheme: IconThemeData(size: 16, color: c.muted),
        selectedLabelTextStyle: code.copyWith(color: c.ink), unselectedLabelTextStyle: code.copyWith(color: c.muted)),
      drawerTheme: DrawerThemeData(backgroundColor: c.page, elevation: 0, shape: const RoundedRectangleBorder()),
      cardTheme: CardThemeData(color: c.surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.rule))),
    );
  }
}
