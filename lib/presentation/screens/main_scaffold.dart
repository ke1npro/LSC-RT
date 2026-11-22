import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'avatar/avatar_screen.dart';
import 'dictionary/dictionary_screen.dart';
import 'settings/settings_screen.dart';
import 'teaching/teaching_screen.dart';
import 'translation/translation_screen.dart';
import 'tutorial/interactive_tutorial_screen.dart';
import 'tutorial/welcome_tutorial_dialog.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  bool _onboardingChecked = false;
  SettingsViewModel? _settingsVm;

  final List<Widget> _screens = const [
    DictionaryScreen(),
    TranslationScreen(),
    AvatarScreen(),
    TeachingScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settingsVm = context.read<SettingsViewModel>();
      _settingsVm!.addListener(_checkFirstVisitOnboarding);
      _checkFirstVisitOnboarding();
    });
  }

  void _checkFirstVisitOnboarding() {
    if (_onboardingChecked || !mounted) return;
    final vm = _settingsVm;
    if (vm == null || !vm.isInitialized) return;

    _onboardingChecked = true;
    vm.removeListener(_checkFirstVisitOnboarding);

    if (!vm.hasSeenOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _presentFirstVisitDialog(vm);
      });
    }
  }

  Future<void> _presentFirstVisitDialog(SettingsViewModel vm) async {
    if (!mounted) return;
    final openTutorial = await WelcomeTutorialDialog.show(context);
    await vm.markOnboardingSeen();
    if (openTutorial && mounted) {
      await InteractiveTutorialScreen.show(context);
    }
  }

  @override
  void dispose() {
    _settingsVm?.removeListener(_checkFirstVisitOnboarding);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xF2121727),
          border: Border(
            top: BorderSide(color: AppColors.glassBorder),
          ),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: 'Diccionario',
              ),
              NavigationDestination(
                icon: Icon(Icons.translate_rounded),
                label: 'Traducción',
              ),
              NavigationDestination(
                icon: Icon(Icons.accessibility_new_rounded),
                label: 'Avatar',
              ),
              NavigationDestination(
                icon: Icon(Icons.school_outlined),
                selectedIcon: Icon(Icons.school_rounded),
                label: 'Enseñanza',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Ajustes',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
