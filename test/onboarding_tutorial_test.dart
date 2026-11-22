import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language_app/core/di/app_providers.dart';
import 'package:sign_language_app/core/theme/app_theme.dart';
import 'package:sign_language_app/data/datasources/local_storage_datasource.dart';
import 'package:sign_language_app/data/repositories/settings_repository_impl.dart';
import 'package:sign_language_app/presentation/screens/settings/settings_screen.dart';
import 'package:sign_language_app/presentation/screens/tutorial/interactive_tutorial_screen.dart';
import 'package:sign_language_app/presentation/screens/tutorial/welcome_tutorial_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Onboarding & Tutorial Tests', () {
    test('SettingsRepositoryImpl persists hasSeenOnboarding flag', () async {
      final repo1 = SettingsRepositoryImpl(LocalStorageDataSource());
      await repo1.initialize();
      expect(repo1.hasSeenOnboarding, isFalse);

      await repo1.setHasSeenOnboarding(true);
      expect(repo1.hasSeenOnboarding, isTrue);

      final repo2 = SettingsRepositoryImpl(LocalStorageDataSource());
      await repo2.initialize();
      expect(repo2.hasSeenOnboarding, isTrue);
    });

    testWidgets('WelcomeTutorialDialog displays options and returns user choice',
        (WidgetTester tester) async {
      bool? acceptResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      acceptResult = await WelcomeTutorialDialog.show(context);
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. Probar botón "Ver tutorial" -> retorna true
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Bienvenido a LSC RT'), findsOneWidget);
      expect(find.text('Ver tutorial'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);

      await tester.tap(find.text('Ver tutorial'));
      await tester.pumpAndSettle();
      expect(acceptResult, isTrue);

      // 2. Probar botón "Ahora no" -> retorna false
      acceptResult = null;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(acceptResult, isFalse);
    });

    testWidgets(
        'InteractiveTutorialScreen navigates through all 5 steps and closes on Empezar/Omitir',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => InteractiveTutorialScreen.show(context),
                child: const Text('StartTutorial'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('StartTutorial'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveTutorialScreen), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('Bienvenido a LSC RT'), findsOneWidget);
      expect(find.text('Anterior'), findsNothing);

      // Avanzar al paso 2
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 5'), findsOneWidget);
      expect(find.text('Graba y recorta tus señas'), findsOneWidget);
      expect(find.text('Anterior'), findsOneWidget);

      // Retroceder al paso 1
      await tester.tap(find.text('Anterior'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 5'), findsOneWidget);

      // Avanzar del paso 1 hasta el paso 5
      for (int step = 2; step <= 5; step++) {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        expect(find.text('$step / 5'), findsOneWidget);
      }

      expect(find.text('Privacidad y Respaldo'), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);

      // Tocar "Empezar" cierra el tutorial
      await tester.tap(find.text('Empezar'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveTutorialScreen), findsNothing);

      // Abrir de nuevo y probar "Omitir"
      await tester.tap(find.text('StartTutorial'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveTutorialScreen), findsOneWidget);

      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveTutorialScreen), findsNothing);
    });

    testWidgets(
        'SettingsScreen displays revisit tutorial option and opens InteractiveTutorialScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.buildProviders([]),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Ver tutorial interactivo'),
        200,
      );
      await tester.pumpAndSettle();

      expect(find.text('AYUDA Y TUTORIAL'), findsOneWidget);
      expect(find.text('Ver tutorial interactivo'), findsOneWidget);

      await tester.tap(find.text('Ver tutorial interactivo'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveTutorialScreen), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
    });
  });
}
