import 'package:flutter/material.dart';

import '../theme/medguard_colors.dart';
import '../theme/page_transitions.dart';
import '../widgets/common/floating_nav_bar.dart';
import 'ai/ai_screen.dart';
import 'dose/dose_screen.dart';
import 'home/home_screen.dart';
import 'insights/insights_screen.dart';
import 'medications/medications_screen.dart';
import 'profile/profile_screen.dart';
import 'search/search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = AppNavTab.home});

  static const String routeName = '/main';

  final AppNavTab initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late AppNavTab _current;

  // Bumped each time the Home tab is (re)entered from another tab, so the home
  // regimen-risk meter re-sweeps from the lowest position on every revisit.
  int _homeVisitNonce = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _current = widget.initialTab;
    }
  }

  void _selectTab(AppNavTab tab) {
    if (_current == tab) return;
    setState(() {
      _current = tab;
      if (tab == AppNavTab.home) _homeVisitNonce++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('main-shell-scaffold'),
      extendBody: true,
      backgroundColor: context.colors.scaffold,
      // Fades THROUGH on a tab change rather than cutting. Still an
      // IndexedStack underneath, so every tab keeps its scroll position and
      // in-flight loads when the user comes back to it.
      body: FadeThroughIndexedStack(
        key: const ValueKey('main-shell-tab-stack'),
        index: _tabIndex(_current),
        children: [
          HomeScreen(
            showNavigation: false,
            bottomContentPadding: kFloatingNavReserveHeight,
            homeRevisitNonce: _homeVisitNonce,
            onOpenSearch: () =>
                Navigator.of(context).pushNamed(SearchScreen.routeName),
            onOpenSafety: () => _selectTab(AppNavTab.interactions),
            onOpenDose: () => _selectTab(AppNavTab.dose),
            // Profile no longer lives in the nav bar — it opens as its own
            // routed screen from the home header, so Back returns to Home.
            onOpenProfile: () =>
                Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
          MedicationsScreen(
            showNavigation: false,
            bottomContentPadding: kFloatingNavReserveHeight,
            onOpenProfile: () =>
                Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
          // The AI tab is full-screen and hides the bottom nav; navigation off
          // it happens through the AI screen's own side menu (drawer), so it
          // gets the tab selector and reserves no nav space.
          AiScreen(
            showNavigation: false,
            bottomContentPadding: 0,
            currentTab: _current,
            onSelectTab: _selectTab,
            onOpenProfile: () =>
                Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
          InsightsScreen(
            showNavigation: false,
            bottomContentPadding: kFloatingNavReserveHeight,
            onOpenProfile: () =>
                Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
          DoseScreen(
            showNavigation: false,
            bottomContentPadding: kFloatingNavReserveHeight,
            onOpenProfile: () =>
                Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
        ],
      ),
      // The AI tab is a full-screen, immersive experience — the floating nav
      // is hidden there and returns on every other tab.
      bottomNavigationBar: _current == AppNavTab.ai
          ? null
          : FloatingNavBar(current: _current, onTabSelected: _selectTab),
    );
  }
}

int _tabIndex(AppNavTab tab) {
  return switch (tab) {
    AppNavTab.home => 0,
    AppNavTab.interactions => 1,
    AppNavTab.ai => 2,
    AppNavTab.insights => 3,
    AppNavTab.dose => 4,
  };
}
