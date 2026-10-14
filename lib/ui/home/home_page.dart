import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/log.dart';
import '../../state/auth.dart';
import '../../state/devices.dart';
import '../../state/library.dart';
import '../../state/selection.dart';
import '../../state/settings.dart';
import '../../theme/am_widgets.dart';
import '../../theme/automatorn_theme.dart';
import '../strings.dart';
import '../widgets/app_widgets.dart';
import 'install_panel.dart';
import 'sections.dart';
import 'settings_section.dart';

/// Width from which the side navigation replaces the bottom bar.
const _wideLayout = 840.0;

const _sections = [
  (section: HomeSection.catalog, label: S.sectionCatalog, icon: 'menu'),
  (section: HomeSection.search, label: S.sectionSearch, icon: 'search'),
  (section: HomeSection.files, label: S.sectionFiles, icon: 'download'),
  (section: HomeSection.settings, label: S.sectionSettings, icon: 'info'),
];

/// The app's main screen: navigation between sections and, for the working
/// sections, a list panel next to the install panel.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Apple rejected the saved session, or the user signed out.
    ref.listen(authProvider, (previous, next) {
      if (next.status == AuthStatus.expired ||
          next.status == AuthStatus.signedOut) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(Routes.login, (route) => false);
      }
    });

    final section = ref.watch(homeSectionProvider);
    final wide = MediaQuery.sizeOf(context).width >= _wideLayout;
    final content = _Content(section: section);

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SideNav(current: section),
                  const VerticalDivider(),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.am.ruleFaint)),
              ),
              child: NavigationBar(
                selectedIndex: section.index,
                onDestinationSelected: (index) => ref
                    .read(homeSectionProvider.notifier)
                    .show(_sections[index].section),
                destinations: [
                  for (final item in _sections)
                    NavigationDestination(
                      icon: AmIcon(item.icon, size: 20),
                      selectedIcon: AmIcon(
                        item.icon,
                        size: 20,
                        color: context.am.ink,
                      ),
                      label: item.label.toLowerCase(),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section == HomeSection.settings) {
      return const SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: AmSize.gapStack),
        child: SettingsSection(),
      );
    }
    final list = switch (section) {
      HomeSection.search => const SearchPanel(),
      HomeSection.files => const FilesPanel(),
      _ => const CatalogPanel(),
    };
    final hasSelection = ref.watch(
      selectionProvider.select((selection) => selection != null),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two panels side by side when there is room, stacked otherwise.
        // Either way only the list scrolls: the install panel with its
        // actions stays in sight however far down the list goes.
        final sideBySide = constraints.maxWidth >= 720;
        final gap = sideBySide ? 24.0 : 16.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(gap, gap, gap, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DeviceNotices(),
              const ActivityStrip(),
              Expanded(
                child: sideBySide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Scrolling(bottom: gap, child: list),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 360,
                            child: _Scrolling(
                              bottom: gap,
                              child: const InstallPanel(),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Scrolling(bottom: gap, child: list),
                          ),
                          // On a narrow screen the panel docks at the bottom
                          // once something is selected.
                          if (hasSelection)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * 0.55,
                              ),
                              child: _Scrolling(
                                bottom: gap,
                                child: const InstallPanel(),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A panel that scrolls on its own when it is taller than its slot.
class _Scrolling extends StatelessWidget {
  const _Scrolling({required this.child, required this.bottom});

  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.only(bottom: bottom),
    child: child,
  );
}

/// Side navigation of the system: 220px, 32px items, the current one in ink
/// on `ruleFaint`, divided from the content by a line rather than a fill.
class _SideNav extends ConsumerWidget {
  const _SideNav({required this.current});

  final HomeSection current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.am;
    final account = ref.watch(authProvider).account;
    final device = ref.watch(currentDeviceProvider);
    final devices = ref.watch(devicesProvider).value ?? const [];
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final files = ref.watch(libraryProvider).length;

    final deviceTitle = ref.watch(driverMissingProvider)
        ? S.deviceDriverMissing
        : device?.name ?? (devices.length > 1 ? S.deviceSeveral : S.deviceNone);

    return SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: Text(
                S.appName,
                style: Automatorn.prose.copyWith(color: c.ink),
              ),
            ),
            for (final item in _sections)
              _NavItem(
                label: item.label,
                icon: item.icon,
                current: item.section == current,
                count: item.section == HomeSection.files && files > 0
                    ? files
                    : null,
                onTap: () =>
                    ref.read(homeSectionProvider.notifier).show(item.section),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AmLabel(S.navDevice),
                  const SizedBox(height: 8),
                  Text(
                    deviceTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Automatorn.code.copyWith(
                      color: device == null ? c.muted : c.ink,
                    ),
                  ),
                  if (device != null)
                    Text(
                      S.deviceOs(device.osVersion),
                      style: Automatorn.footer.copyWith(color: c.muted),
                    ),
                  const SizedBox(height: 16),
                  const AmLabel(S.navAccount),
                  const SizedBox(height: 8),
                  Text(
                    account == null ? S.accountNone : mask(account.email),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Automatorn.code.copyWith(color: c.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AmGhostButton(
                label: dark
                    ? S.themeNight.toLowerCase()
                    : S.themePaper.toLowerCase(),
                small: true,
                onPressed: ref.read(themeModeProvider.notifier).toggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.current,
    required this.onTap,
    this.count,
  });

  final String label;
  final String icon;
  final bool current;
  final int? count;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  var _active = false;

  @override
  Widget build(BuildContext context) {
    final c = context.am;
    final color = widget.current || _active ? c.ink : c.muted;
    return Semantics(
      selected: widget.current,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _active = value),
        onFocusChange: (value) => setState(() => _active = value),
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AmSize.radiusControl),
        child: Container(
          height: AmSize.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.current ? c.ruleFaint : null,
            borderRadius: BorderRadius.circular(AmSize.radiusControl),
          ),
          child: Row(
            children: [
              AmIcon(widget.icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: Automatorn.code.copyWith(color: color),
                ),
              ),
              if (widget.count != null)
                Text(
                  '${widget.count}',
                  style: Automatorn.footer.copyWith(
                    color: c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
