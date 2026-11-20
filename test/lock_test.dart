import 'dart:math';

import 'package:digital_tasbih/lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the sum on screen and returns its answer.
int shownAnswer(WidgetTester tester) {
  final text = tester
      .widget<Text>(find.byKey(const Key('math-question')))
      .data!;
  final nums = RegExp(r'\d+')
      .allMatches(text)
      .map((m) => int.parse(m.group(0)!));
  return nums.fold(0, (a, b) => a + b);
}

Future<void> typeAnswer(WidgetTester tester, int answer) async {
  for (final ch in '$answer'.split('')) {
    await tester.tap(find.byKey(Key('pad-$ch')));
  }
  await tester.tap(find.byKey(const Key('pad-ok')));
  await tester.pumpAndSettle();
}

Widget app({DateTime Function()? now, Random? random}) => MaterialApp(
  builder: (context, child) => LockGate(
    now: now,
    random: random,
    child: child ?? const SizedBox.shrink(),
  ),
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showLockSettings(context),
          child: const Text('home screen'),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLock.enabled.value = true;
  });

  test('questions are additions with the right answer and vary', () {
    final r = Random(1);
    final seen = <String>{};
    for (var i = 0; i < 200; i++) {
      final q = MathQuestion.random(r);
      expect(q.terms.length, inInclusiveRange(2, 3));
      expect(q.terms.every((t) => t >= 3 && t < 400), isTrue);
      expect(q.answer, q.terms.reduce((a, b) => a + b));
      expect(q.text, endsWith(' = ?'));
      expect(q.text, contains(' + '));
      seen.add(q.text);
    }
    expect(seen.length, greaterThan(100));
    expect(const MathQuestion([2, 3]).text, '2 + 3 = ?');
    expect(const MathQuestion([2, 3]).answer, 5);
  });

  testWidgets(
    'locked at start: the app cannot be touched until the sum is solved',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => LockGate(child: child!),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('home screen'),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('math-question')), findsOneWidget);
      // a tap where the home button is lands on the lock instead
      await tester.tapAt(
        tester.getCenter(find.text('home screen', skipOffstage: false)),
      );
      expect(taps, 0);

      await typeAnswer(tester, shownAnswer(tester));
      expect(find.byKey(const Key('math-question')), findsNothing);
      await tester.tap(find.text('home screen'));
      expect(taps, 1);
    },
  );

  testWidgets('a wrong answer keeps it locked and shows a different sum', (
    tester,
  ) async {
    await tester.pumpWidget(app(random: Random(7)));
    final before = tester
        .widget<Text>(find.byKey(const Key('math-question')))
        .data;
    await typeAnswer(tester, shownAnswer(tester) + 1);
    expect(find.byKey(const Key('math-wrong')), findsOneWidget);
    expect(find.byKey(const Key('math-question')), findsOneWidget);
    final after = tester
        .widget<Text>(find.byKey(const Key('math-question')))
        .data;
    expect(after, isNot(before));
    expect(tester.widget<Text>(find.byKey(const Key('math-answer'))).data, '');

    // backspace removes the last digit, empty answer is ignored
    await tester.tap(find.byKey(const Key('pad-4')));
    await tester.tap(find.byKey(const Key('pad-2')));
    await tester.tap(find.byKey(const Key('pad-back')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('math-answer'))).data, '4');
    await tester.tap(find.byKey(const Key('pad-back')));
    await tester.tap(find.byKey(const Key('pad-ok')));
    await tester.pump();
    expect(find.byKey(const Key('math-question')), findsOneWidget);
  });

  testWidgets('lock turned off: the app opens directly', (tester) async {
    AppLock.enabled.value = false;
    await tester.pumpWidget(app());
    expect(find.byKey(const Key('math-question')), findsNothing);
    expect(find.text('home screen'), findsOneWidget);
  });

  testWidgets('locks again only after the app was away for a minute', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 20, 10);
    await tester.pumpWidget(app(now: () => now));
    await typeAnswer(tester, shownAnswer(tester));
    expect(find.byKey(const Key('math-question')), findsNothing);

    // away 30 seconds -> still open
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('math-question')), findsNothing);

    // away 2 minutes -> locked
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('math-question')), findsOneWidget);

    // and it opens again with a correct answer
    await typeAnswer(tester, shownAnswer(tester));
    expect(find.byKey(const Key('math-question')), findsNothing);
  });

  testWidgets('a disabled lock does not come back after being away', (
    tester,
  ) async {
    AppLock.enabled.value = false;
    var now = DateTime(2026, 11, 20, 10);
    await tester.pumpWidget(app(now: () => now));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const Key('math-question')), findsNothing);
  });

  testWidgets(
    'settings: turning the lock off needs a solved sum, on does not',
    (tester) async {
      AppLock.enabled.value = false;
      await tester.pumpWidget(app());
      await tester.tap(find.text('home screen'));
      await tester.pumpAndSettle();
      expect(find.text('App lock'), findsOneWidget);

      // switch ON: immediate
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(AppLock.enabled.value, isTrue);

      // switch OFF: a sum appears; a wrong answer leaves the lock on
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Solve to turn the lock off'), findsOneWidget);
      await typeAnswer(tester, shownAnswer(tester) + 1);
      expect(AppLock.enabled.value, isTrue);
      await typeAnswer(tester, shownAnswer(tester));
      expect(AppLock.enabled.value, isFalse);
      expect(find.text('Solve to turn the lock off'), findsNothing);
    },
  );

  testWidgets('the choice is remembered', (tester) async {
    SharedPreferences.setMockInitialValues({'appLock': false});
    await AppLock.load();
    expect(AppLock.enabled.value, isFalse);
    await AppLock.set(true);
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    expect(AppLock.enabled.value, isTrue);
    expect(p, isNotNull);
  });
}
