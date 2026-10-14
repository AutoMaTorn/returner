import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/settings.dart';
import 'theme/automatorn_theme.dart';
import 'ui/home/home_page.dart';
import 'ui/login/login_page.dart';
import 'ui/setup/setup_page.dart';
import 'ui/strings.dart';

abstract final class Routes {
  static const setup = '/';
  static const login = '/login';
  static const home = '/home';
}

class ReturnerApp extends ConsumerWidget {
  const ReturnerApp({super.key});

  static const _pages = <String, Widget>{
    Routes.setup: SetupPage(),
    Routes.login: LoginPage(),
    Routes.home: HomePage(),
  };

  /// Fills two gaps of the generated theme without editing it:
  /// Flutter shrinks controls on desktop, while the system's are 32px on
  /// every platform; and `SegmentedButton` has no style there, so it gets the
  /// system's control shape, border and the ink-on-`ruleFaint` selection of
  /// the side navigation.
  static ThemeData _complete(ThemeData theme) {
    final c = theme.extension<AmColors>()!;
    return theme.copyWith(
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AmSize.controlHeight),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AmSize.radiusControl),
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.ruleStrong)),
          textStyle: const WidgetStatePropertyAll(Automatorn.code),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? c.ruleFaint
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? c.ink : c.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: _complete(Automatorn.light()),
      darkTheme: _complete(Automatorn.dark()),
      // "Ночь" is the primary theme; the user's choice is remembered.
      themeMode: ref.watch(themeModeProvider),
      initialRoute: Routes.setup,
      // Pages fade into each other: nothing slides or jumps.
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => _pages[settings.name] ?? const SetupPage(),
        transitionsBuilder: (context, animation, _, child) =>
            MediaQuery.disableAnimationsOf(context)
            ? child
            : FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: AmSize.ease),
                child: child,
              ),
      ),
    );
  }
}
