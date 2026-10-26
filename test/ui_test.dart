import 'dart:io';

import 'package:digital_tasbih/db.dart';
import 'package:digital_tasbih/main.dart';
import 'package:digital_tasbih/pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Screen-level checks that run without a phone or a browser.
/// Tests share one database and run in order.
void main() {
  late Directory dir;
  final today = DateTime.now();
  final todayStr = ymd(today);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zikir_ui');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // vibration has no implementation in tests
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vibration'),
      (call) async => true,
    );
  }

  /// Lets real database I/O finish, then redraws. With [until], waits (up to ~8 s)
  /// for that widget to show up.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (until == null && i >= 1) return;
      if (until != null && until.evaluate().isNotEmpty) return;
    }
  }

  Finder bigButton() =>
      find.byWidgetPredicate((w) => w is MetalButton && w.ridged);
  Finder resetButton() =>
      find.byWidgetPredicate((w) => w is MetalButton && !w.ridged);

  testWidgets(
    'counter screen: layout, bigger buttons, hidden clear button, contact icons',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'sound': false});
      await tester.pumpWidget(const TasbihApp());
      await settle(tester, until: find.text('পড়া: 0/20'));

      // the "Clear without saving" button is gone from the screen
      expect(find.text('Clear without saving'), findsNothing);

      // buttons are bigger than before (reset 44 -> 64, count 200 -> 250)
      expect(tester.widget<MetalButton>(bigButton()).size, 250);
      expect(tester.widget<MetalButton>(resetButton()).size, 64);

      // today / all total sit below the counter
      final deviceY = tester.getTopLeft(find.byType(CounterDevice)).dy;
      expect(tester.getTopLeft(find.text('TODAY')).dy, greaterThan(deviceY));
      expect(
        tester.getTopLeft(find.text('ALL TOTAL')).dy,
        greaterThan(deviceY),
      );

      // contact details are behind icons, not printed on the screen
      expect(find.text('atiqur.rahman.himel@gmail.com'), findsNothing);
      expect(find.text('01970091221'), findsNothing);
      await tester.tap(find.byIcon(Icons.email_outlined));
      await tester.pumpAndSettle();
      expect(find.text('atiqur.rahman.himel@gmail.com'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.phone_outlined));
      await tester.pumpAndSettle();
      expect(find.text('01970091221'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // progress chip starts at 0 of 20
      expect(find.text('পড়া: 0/20'), findsOneWidget);

      // menu has bulk import and the clear action
      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      expect(find.text('Bulk import'), findsOneWidget);
      expect(find.text('Clear running count'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'progress chip counts zikirs done in this prayer; last one shows congratulations',
    (tester) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      // 19 of the 20 zikirs already done today in ফজর
      await tester.runAsync(
        () => Db.bulkAdd(today, today, {
          for (final c in cats.take(19)) c.id: 1,
        }, 'ফজর'),
      );
      SharedPreferences.setMockInitialValues({
        'sound': false,
        'prayerOverride': 'ফজর',
        'currentCategory': cats[19].id,
      });
      await tester.pumpWidget(const TasbihApp());
      await settle(tester, until: find.text('পড়া: 19/20'));

      expect(find.text('পড়া: 19/20'), findsOneWidget);
      expect(find.text('Congratulations!'), findsNothing);

      await tester.tap(bigButton());
      await tester.tap(bigButton());
      await tester.pump();
      await tester.tap(resetButton());
      await settle(tester, until: find.text('Congratulations!'));

      expect(find.text('Congratulations!'), findsOneWidget);
      expect(find.textContaining('অভিনন্দন'), findsOneWidget);
      await tester.tap(find.text('Alhamdulillah'));
      await tester.pumpAndSettle();
      // the prayer goes back to automatic after a save, so check the saved data itself
      expect(await tester.runAsync(() => Db.doneCount(todayStr, 'ফজর')), 20);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day details are grouped by prayer, then the whole-day total per zikir',
    (tester) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      final a = cats[0].id, b = cats[4].id; // সুবহানাল্লাহ, আস্তাগফিরুল্লাহ
      await tester.runAsync(() async {
        for (final prayer in ['আসর', 'জোহর']) {
          await Db.saveCount(a, '2026-10-20', prayer, 100);
          await Db.saveCount(b, '2026-10-20', prayer, 100);
        }
      });
      await tester.pumpWidget(
        MaterialApp(home: DayPage(date: DateTime(2026, 10, 20))),
      );
      await settle(tester, until: find.text('সারাদিনের মোট (Day total)'));

      // জোহর comes before আসর (order of the day), even though আসর was saved first
      final zohr = tester.getTopLeft(find.text('জোহর')).dy;
      final asr = tester.getTopLeft(find.text('আসর')).dy;
      expect(zohr, lessThan(asr));

      // whole-day total section comes last: each prayer subtotal and each zikir total is 200
      final totalHeader = tester
          .getTopLeft(find.text('সারাদিনের মোট (Day total)'))
          .dy;
      expect(totalHeader, greaterThan(asr));
      expect(
        find.text('200'),
        findsNWidgets(4),
      ); // 2 prayer subtotals + 2 zikir totals
      expect(find.text('Total = 400   (2 zikir)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bulk import: defaults, range 20 Sep to today, adds the right total',
    (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'sound': false});
      await tester.pumpWidget(const MaterialApp(home: BulkImportPage()));
      await settle(tester, until: find.byType(Checkbox));

      final f = DateFormat('d MMM yyyy');
      final sep20 = DateTime(today.year, 9, 20).isAfter(today)
          ? DateTime(today.year - 1, 9, 20)
          : DateTime(today.year, 9, 20);
      expect(find.text('From  ${f.format(sep20)}'), findsOneWidget);
      expect(find.text('To  ${f.format(today)}'), findsOneWidget);

      // pre-filled counts from the owner's list, all selected
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller!.text, '100');
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes.every((c) => c.value == true), isTrue);

      final days =
          DateTime.utc(today.year, today.month, today.day)
              .difference(DateTime.utc(sep20.year, sep20.month, sep20.day))
              .inDays +
          1;
      const perDay = 5 * 100 + 4 * 21 + 100 + 5 * 21 + 5 * 10; // 839
      expect(find.textContaining('20 zikirs × $days days'), findsOneWidget);

      final before = (await tester.runAsync(() => Db.grandTotal()))!;
      await tester.tap(find.text('Add to history'));
      await tester.pumpAndSettle();
      expect(find.text('Add to history?'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await settle(tester);
      await settle(tester);

      final after = (await tester.runAsync(() => Db.grandTotal()))!;
      expect(after - before, perDay * days);
      expect(tester.takeException(), isNull);
    },
  );

  test('sanity: today string is the one the app uses', () {
    expect(todayStr, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });
}
