// App entry, auth gate, login, the five-tab RootShell, and the Account
// screen. Anything that reaches RootShell runs with the platform set to
// Linux, so the real openAppDatabase() opens an FFI SQLite file in the
// fake documents directory instead of calling the sqflite plugin.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/app.dart';
import 'package:quillfin/auth/auth_service.dart';
import 'package:quillfin/main.dart' as app;
import 'package:quillfin/screens/account/account_screen.dart';
import 'package:quillfin/screens/login/login_screen.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/screens/notes/notes_home_screen.dart';
import 'package:quillfin/screens/root_shell.dart';
import 'package:quillfin/screens/settings/settings_screen.dart';
import 'package:quillfin/screens/today/today_screen.dart';
import 'package:quillfin/screens/tracker/problems_screen.dart';
import 'package:quillfin/services/reminder_service.dart';
import 'package:quillfin/settings/app_settings.dart';
import 'package:quillfin/theme/theme.dart';

import '../helpers/fake_notifications.dart';
import '../helpers/test_env.dart';

final linux = TargetPlatformVariant.only(TargetPlatform.linux);

Future<HardcodedAuthService> signedIn() async {
  final auth = HardcodedAuthService();
  await auth.login('admin', '1234');
  return auth;
}

void main() {
  setUpTestEnv();

  group('app entry', () {
    testWidgets('main() starts signed out, on the login screen', (tester) async {
      await tester.runAsync(() async {
        app.main();
        await tester.pump();
        await waitForLoad(tester);

        expect(find.byType(LoginScreen), findsOneWidget);
      });
    });

    testWidgets('QuillFinApp shows a spinner, then the login screen when signed out', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(QuillFinApp(authService: HardcodedAuthService()));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await waitForLoad(tester);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.scaffoldBackgroundColor, BrandPalette.light.paper);
      });
    });

    testWidgets('QuillFinApp goes straight to the app shell when already signed in', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(QuillFinApp(authService: await signedIn()));
        await waitForLoad(tester);

        expect(find.byType(RootShell), findsOneWidget);
        expect(find.byType(TodayScreen), findsOneWidget);
      });
    }, variant: linux);
  });

  group('LoginScreen', () {
    Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);

    testWidgets('wrong credentials show an error and stay on the screen', (tester) async {
      await tester.runAsync(() async {
        final auth = HardcodedAuthService();
        await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: auth)));

        await tester.enterText(field('Username'), 'admin');
        await tester.enterText(field('Password'), 'nope');
        await tester.tap(find.text('Sign in'));
        await pumpUntil(tester, () => find.text('Incorrect username or password.').evaluate().isNotEmpty);

        expect(find.text('Sign in'), findsOneWidget); // button re-enabled
        expect(await auth.currentUser(), isNull);
      });
    });

    testWidgets('correct credentials sign in and open the app shell', (tester) async {
      await tester.runAsync(() async {
        final auth = HardcodedAuthService();
        await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: auth)));

        await tester.enterText(field('Username'), '  admin  '); // username is trimmed
        await tester.enterText(field('Password'), '1234');
        await tester.tap(find.text('Sign in'));
        await tester.pump();
        expect(find.text('Signing in...'), findsOneWidget);

        await pumpUntil(tester, () => find.byType(RootShell).evaluate().isNotEmpty);
        await settleNavigation(tester);
        expect(find.byType(LoginScreen), findsNothing);
        expect((await auth.currentUser())?.username, 'admin');
      });
    }, variant: linux);

    testWidgets('pressing done on the password field submits', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: LoginScreen(authService: HardcodedAuthService())));

        await tester.enterText(field('Password'), 'wrong');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await pumpUntil(tester, () => find.text('Incorrect username or password.').evaluate().isNotEmpty);
      });
    });
  });

  group('RootShell', () {
    // The default 800x600 test window is "medium", so sections are in a rail.
    Finder tab(String label) => find.descendant(of: find.byType(NavigationRail), matching: find.text(label));

    testWidgets('opens the app database, then switches between the five tabs', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: RootShell(authService: await signedIn())));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await waitForLoad(tester);

        expect(find.byType(TodayScreen), findsOneWidget);
        for (final (label, screen) in [
          ('Notes', NotesHomeScreen),
          ('Tracker', ProblemsScreen),
          ('Account', AccountScreen),
          ('Settings', SettingsScreen),
          ('Today', TodayScreen),
        ]) {
          await tester.tap(tab(label));
          await waitForLoad(tester);
          expect(find.byType(screen), findsOneWidget, reason: label);
        }
        expect(documentsDir.listSync().map((f) => f.path.split('/').last), contains('quillfin.db'));
      });
    }, variant: linux);

    testWidgets('syncs reminders on open and after study changes elsewhere', (tester) async {
      await tester.runAsync(() async {
        final fake = useFakeNotifications(FakeAndroidNotifications());
        await const AppSettingsStore().save(const AppSettings(remindersEnabled: true));
        final reminders = ReminderService(delivery: ReminderDelivery.scheduled);
        await tester.pumpWidget(MaterialApp(home: RootShell(authService: await signedIn(), reminders: reminders)));
        await waitForLoad(tester);
        await pumpUntil(tester, () => fake.cancelAllCalls == 1);

        // Adding a problem on the Tracker tab re-plans reminders and shows up on Today.
        await tester.tap(tab('Tracker'));
        await waitForLoad(tester);
        await tester.tap(find.text('Add a problem'));
        await settleNavigation(tester);
        await tester.enterText(find.byType(TextField).first, 'Two Sum');
        await tester.tap(find.byIcon(Icons.save));
        await settleNavigation(tester);
        await tester.pageBack();
        await settleNavigation(tester);
        await pumpUntil(tester, () => fake.cancelAllCalls == 2);
        expect(find.text('Two Sum'), findsOneWidget);
      });
    }, variant: linux);
  });

  group('AccountScreen', () {
    Finder field(String label) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
    String text(WidgetTester tester, String label) => tester.widget<TextField>(field(label)).controller!.text;

    Future<HardcodedAuthService> show(WidgetTester tester) async {
      final auth = await signedIn();
      await tester.pumpWidget(MaterialApp(home: AccountScreen(authService: auth)));
      await waitForLoad(tester);
      return auth;
    }

    testWidgets('shows the signed-in user and default AI settings', (tester) async {
      await tester.runAsync(() async {
        await show(tester);

        expect(find.text('admin'), findsOneWidget);
        expect(find.text(defaultProvider), findsOneWidget);
        expect(text(tester, 'Model (e.g. gpt-4o-mini)'), defaultModel);
        expect(text(tester, 'Base URL override (optional)'), '');
        expect(text(tester, 'API key'), '');
        expect(tester.widget<TextField>(field('API key')).obscureText, isTrue);
      });
    });

    testWidgets('pre-fills saved settings and the stored key', (tester) async {
      await tester.runAsync(() async {
        await const AppSettingsStore().save(const AppSettings(provider: 'anthropic', model: 'claude', baseUrl: 'u'));
        await const FlutterSecureStorage().write(key: 'ai_api_key', value: 'sk-saved');
        await show(tester);

        expect(find.text('anthropic'), findsOneWidget);
        expect(text(tester, 'Model (e.g. gpt-4o-mini)'), 'claude');
        expect(text(tester, 'Base URL override (optional)'), 'u');
        expect(text(tester, 'API key'), 'sk-saved');
      });
    });

    testWidgets('Save stores the key securely and the rest as settings, trimmed', (tester) async {
      await tester.runAsync(() async {
        await show(tester);

        await tester.tap(find.text(defaultProvider));
        await tester.pumpAndSettle();
        await tester.tap(find.text('anthropic').last);
        await tester.pumpAndSettle();
        await tester.enterText(field('Model (e.g. gpt-4o-mini)'), ' claude-haiku-5-5 ');
        await tester.enterText(field('Base URL override (optional)'), ' https://proxy.example.com ');
        await tester.enterText(field('API key'), ' sk-new ');
        await tester.tap(find.text('Save'));
        await pumpUntil(tester, () => find.text('Saved').evaluate().isNotEmpty);

        expect(await const FlutterSecureStorage().read(key: 'ai_api_key'), 'sk-new');
        final settings = await const AppSettingsStore().load();
        expect((settings.provider, settings.model, settings.baseUrl), ('anthropic', 'claude-haiku-5-5', 'https://proxy.example.com'));
      });
    });

    testWidgets('Save keeps Settings-tab choices it does not own', (tester) async {
      await tester.runAsync(() async {
        await const AppSettingsStore().save(const AppSettings(
          defaultQuestionFormat: questionTypeMultipleChoice,
          remindersEnabled: true,
          desiredRetention: 0.8,
        ));
        await show(tester);

        await tester.tap(find.text('Save'));
        await pumpUntil(tester, () => find.text('Saved').evaluate().isNotEmpty);
        final settings = await const AppSettingsStore().load();
        expect((settings.defaultQuestionFormat, settings.remindersEnabled, settings.desiredRetention),
            (questionTypeMultipleChoice, true, 0.8));
      });
    });

    testWidgets('a blank base URL is saved as none, and editing any field un-marks Saved', (tester) async {
      await tester.runAsync(() async {
        await const AppSettingsStore().save(const AppSettings(baseUrl: 'old'));
        await show(tester);

        await tester.enterText(field('Base URL override (optional)'), '   ');
        await tester.tap(find.text('Save'));
        await pumpUntil(tester, () => find.text('Saved').evaluate().isNotEmpty);
        expect((await const AppSettingsStore().load()).baseUrl, isNull);

        for (final label in ['Model (e.g. gpt-4o-mini)', 'Base URL override (optional)', 'API key']) {
          await tester.enterText(field(label), 'changed');
          await tester.pump();
          expect(find.text('Save'), findsOneWidget, reason: label);
          await tester.tap(find.text('Save'));
          await pumpUntil(tester, () => find.text('Saved').evaluate().isNotEmpty);
        }
      });
    });

    testWidgets('Log out signs out and replaces the whole stack with the login screen', (tester) async {
      await tester.runAsync(() async {
        final auth = await show(tester);

        // Below the fold of the 800x600 test viewport, so not built until scrolled to.
        // Each TextField has its own Scrollable, so name the list's (the outermost) explicitly.
        await tester.scrollUntilVisible(find.text('Log out'), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Log out'));
        await settleNavigation(tester);

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(AccountScreen), findsNothing);
        expect(await auth.currentUser(), isNull);
      });
    });
  });
}
