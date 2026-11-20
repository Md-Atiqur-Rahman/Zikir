import 'dart:io';

import 'package:digital_tasbih/db.dart';
import 'package:digital_tasbih/lock.dart';
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
  // days inside / outside the editable last week
  final recent = today.subtract(const Duration(days: 2));
  final recentStr = ymd(recent);
  final recent3 = today.subtract(const Duration(days: 3));
  final old = today.subtract(const Duration(days: 10));
  final oldStr = ymd(old);

  setUpAll(() async {
    AppLock.enabled.value =
        false; // the lock has its own tests (lock_test.dart)
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

      // the bottom hint line is gone, and the two total tiles are small
      expect(find.textContaining('Small button'), findsNothing);
      final tile = find.ancestor(
        of: find.text('TODAY'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(tile.first).height, lessThan(52));

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
    'day details: groups start collapsed, one line per zikir, whole-day total last',
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

      // collapsed: only the headers (with totals) are on screen, no zikir names
      expect(find.text('জোহর'), findsOneWidget);
      expect(find.text('আসর'), findsOneWidget);
      expect(find.text(cats[0].name), findsNothing);
      expect(find.text('200'), findsNWidgets(2)); // জোহর and আসর headers
      expect(find.text('400'), findsOneWidget); // whole-day total header
      expect(find.text('Total = 400   (2 zikir)'), findsOneWidget);

      // জোহর comes before আসর (order of the day), even though আসর was saved first
      final zohr = tester.getTopLeft(find.text('জোহর')).dy;
      final asr = tester.getTopLeft(find.text('আসর')).dy;
      final total = tester
          .getTopLeft(find.text('সারাদিনের মোট (Day total)'))
          .dy;
      expect(zohr, lessThan(asr));
      expect(total, greaterThan(asr));

      // expanding জোহর shows its zikirs on single lines with their counts
      await tester.tap(find.text('জোহর'));
      await tester.pumpAndSettle();
      expect(find.text(cats[0].name), findsOneWidget);
      expect(find.text(cats[4].name), findsOneWidget);
      final nameText = tester.widget<Text>(find.text(cats[0].name));
      expect(nameText.maxLines, 1);
      expect(nameText.overflow, TextOverflow.ellipsis);
      expect(find.text('100'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('day details: a count can be raised, lowered and removed', (
    tester,
  ) async {
    phone(tester);
    final cats = (await tester.runAsync(() => Db.categories()))!;
    final a = cats[2].id; // আল্লাহু আকবার
    await tester.runAsync(() => Db.saveCount(a, recentStr, 'ফজর', 50));
    await tester.pumpWidget(MaterialApp(home: DayPage(date: recent)));
    await settle(tester, until: find.text('ফজর'));
    await tester.tap(find.text('ফজর'));
    await tester.pumpAndSettle();

    Future<int?> saved() => tester.runAsync<int?>(
      () async =>
          (await Db.dayRows(recentStr))
              .where((r) => r.categoryId == a && r.prayer == 'ফজর')
              .map((r) => r.count)
              .firstOrNull,
    );

    // tap the row -> dialog with the current count; + twice, then save
    await tester.tap(find.text(cats[2].name));
    await tester.pumpAndSettle();
    expect(find.text('Was 50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('count-plus')));
    await tester.tap(find.byKey(const Key('count-plus')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester, until: find.text('Total = 52   (1 zikir)'));
    await tester.pumpAndSettle(); // let the dialog finish closing
    expect(await saved(), 52);
    expect(find.text('Total = 52   (1 zikir)'), findsOneWidget);

    // type a smaller number
    await tester.tap(find.text(cats[2].name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('count-field')), '30');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester, until: find.text('Total = 30   (1 zikir)'));
    await tester.pumpAndSettle();
    expect(await saved(), 30);

    // cancelling changes nothing
    await tester.tap(find.text(cats[2].name));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('count-plus')));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await saved(), 30);

    // 0 removes the entry
    await tester.tap(find.text(cats[2].name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('count-field')), '0');
    await tester.pump();
    expect(find.text('Saving 0 removes this entry.'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester, until: find.text('Nothing saved on this day.'));
    await tester.pumpAndSettle();
    expect(await saved(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day with only prayer-less rows: one editable group, no repeat', (
    tester,
  ) async {
    phone(tester);
    final cats = (await tester.runAsync(() => Db.categories()))!;
    await tester.runAsync(() => Db.saveCount(cats[3].id, ymd(recent3), '', 70));
    await tester.pumpWidget(MaterialApp(home: DayPage(date: recent3)));
    await settle(tester, until: find.text('অন্য সময় (no prayer)'));
    expect(find.text('সারাদিনের মোট (Day total)'), findsNothing);
    await tester.tap(find.text('অন্য সময় (no prayer)'));
    await tester.pumpAndSettle();
    expect(find.text(cats[3].name), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('only the last 7 days can be edited; older days are view-only', (
    tester,
  ) async {
    phone(tester);
    final cats = (await tester.runAsync(() => Db.categories()))!;
    await tester.runAsync(() async {
      await Db.saveCount(cats[0].id, oldStr, 'ফজর', 40);
    });

    // 10 days ago: shown, but no pencil, no dialog, and a note says why
    await tester.pumpWidget(MaterialApp(home: DayPage(date: old)));
    await settle(tester, until: find.text('ফজর'));
    await tester.tap(find.text('ফজর'));
    await tester.pumpAndSettle();
    expect(find.text(cats[0].name), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byKey(const Key('read-only-note')), findsOneWidget);
    await tester.tap(find.text(cats[0].name));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('editable window: today and the 6 days before it', () {
    final now = DateTime(2026, 11, 20, 15, 30);
    expect(isEditableDay(DateTime(2026, 11, 20), now: now), isTrue);
    expect(
      isEditableDay(DateTime(2026, 11, 14), now: now),
      isTrue,
    ); // 6 days ago
    expect(
      isEditableDay(DateTime(2026, 11, 13), now: now),
      isFalse,
    ); // 7 days ago
    expect(isEditableDay(DateTime(2026, 10, 1), now: now), isFalse);
    expect(isEditableDay(DateTime(2026, 11, 21), now: now), isFalse); // future
    expect(editableDays, 7);
  });

  group('counter: choosing another zikir, no toast', () {
    Future<List<Category>> pump(
      WidgetTester tester, {
      required int count,
      required int current,
      String prayer = 'আসর',
    }) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      SharedPreferences.setMockInitialValues({
        'sound': false,
        'prayerOverride': prayer,
        'currentCategory': cats[current].id,
        'count': count,
        if (count > 0) 'start': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(const TasbihApp());
      await settle(tester, until: find.textContaining('পড়া:'));
      return cats;
    }

    Finder lcd(String n) =>
        find.descendant(of: find.byType(CounterDevice), matching: find.text(n));

    Future<void> openList(WidgetTester tester) async {
      // top-left of the card is padding + name, away from the chips
      await tester.tapAt(
        tester.getTopLeft(find.byType(InfoCard)) + const Offset(30, 20),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a count in progress is saved under the old zikir, the picked one starts at 0',
      (tester) async {
        final cats = await pump(
          tester,
          count: 30,
          current: 1,
        ); // আলহামদুলিল্লাহ 30
        final oldBefore = (await tester.runAsync(
          () => Db.categoryTotal(cats[1].id),
        ))!;
        final newBefore = (await tester.runAsync(
          () => Db.categoryTotal(cats[2].id),
        ))!;
        expect(lcd('30'), findsOneWidget);

        await openList(tester);
        await tester.tap(find.text(cats[2].name)); // আল্লাহু আকবার
        await settle(tester, until: lcd('0'));
        await tester.pumpAndSettle();

        expect(lcd('0'), findsOneWidget);
        expect(
          await tester.runAsync(() => Db.categoryTotal(cats[1].id)),
          oldBefore + 30,
        );
        expect(
          await tester.runAsync(() => Db.categoryTotal(cats[2].id)),
          newBefore,
        );
        final prefs = await tester.runAsync(SharedPreferences.getInstance);
        expect(prefs!.getInt('currentCategory'), cats[2].id);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('nothing counted: picking another zikir just switches', (
      tester,
    ) async {
      final cats = await pump(tester, count: 0, current: 1);
      final total = (await tester.runAsync(() => Db.grandTotal()))!;
      await openList(tester);
      await tester.tap(find.text(cats[3].name));
      await tester.pumpAndSettle();
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      // the switch happens after a few real database reads; wait for it (max ~8 s)
      for (var i = 0; i < 40; i++) {
        if (prefs.getInt('currentCategory') == cats[3].id) break;
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
      }
      expect(prefs.getInt('currentCategory'), cats[3].id);
      expect(await tester.runAsync(() => Db.grandTotal()), total);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking the zikir you are already on changes nothing', (
      tester,
    ) async {
      final cats = await pump(tester, count: 12, current: 4);
      final total = (await tester.runAsync(() => Db.grandTotal()))!;
      await openList(tester);
      await tester.tap(find.text(cats[4].name).last);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(lcd('12'), findsOneWidget);
      expect(await tester.runAsync(() => Db.grandTotal()), total);
    });

    testWidgets('reset saves and moves on without showing any toast', (
      tester,
    ) async {
      final cats = await pump(tester, count: 5, current: 5, prayer: 'মাগরিব');
      final before = (await tester.runAsync(
        () => Db.categoryTotal(cats[5].id),
      ))!;
      await tester.tap(resetButton());
      await settle(tester, until: lcd('0'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await tester.runAsync(() => Db.categoryTotal(cats[5].id)),
        before + 5,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Saved'), findsNothing);
      expect(find.textContaining('Next:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  test('sanity: today string is the one the app uses', () {
    expect(todayStr, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });
}
