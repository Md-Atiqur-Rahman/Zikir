import 'dart:io';

import 'package:digital_tasbih/db.dart';
import 'package:digital_tasbih/l10n.dart';
import 'package:digital_tasbih/lock.dart';
import 'package:digital_tasbih/main.dart';
import 'package:digital_tasbih/pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Bangla / English: the language setting, the translator, and the screens in both languages.
void main() {
  late Directory dir;
  final today = DateTime.now();
  final recent = today.subtract(const Duration(days: 1));

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zikir_l10n');
    await databaseFactory.setDatabasesPath(dir.path);
    await initializeDateFormatting('bn');
    AppLock.enabled.value = false;
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vibration'),
      (call) async => true,
    );
  }

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

  Widget page(Widget home, String code) => MaterialApp(
    locale: Locale(code),
    supportedLocales: const [Locale('bn'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );

  group('numbers, dates and names', () {
    test('Bangla numbers use Bangla digits and lakh grouping', () {
      const s = S.bangla;
      expect(s.n(0), '০');
      expect(s.n(7), '৭');
      expect(s.n(520), '৫২০');
      expect(s.n(1000), '১,০০০');
      expect(s.n(25000), '২৫,০০০');
      expect(s.n(1234567), '১২,৩৪,৫৬৭');
      expect(s.n(-1500), '-১,৫০০');
      expect(s.digits('1-100'), '১-১০০');
    });

    test('English numbers are unchanged', () {
      const s = S.en;
      expect(s.n(1234567), '1,234,567');
      expect(s.n(520), '520');
      expect(s.digits('1-100'), '1-100');
    });

    test('dates follow the language', () {
      final d = DateTime(2026, 11, 20);
      expect(S.en.date('d MMM yyyy', d), '20 Nov 2026');
      expect(S.bangla.date('d MMM yyyy', d), '২০ নভে ২০২৬');
      expect(S.en.date('MMMM yyyy', d), 'November 2026');
      expect(S.bangla.date('MMMM yyyy', d), 'নভেম্বর ২০২৬');
    });

    test('all 20 built-in zikirs and 8 prayers have an English form', () {
      expect(zikirEnglish.length, defaultZikirNames.length);
      expect(defaultZikirNames.length, 20);
      for (final name in defaultZikirNames) {
        final en = S.en.zikirName(name);
        expect(en, isNot(name), reason: name);
        expect(RegExp('[ঀ-৿]').hasMatch(en), isFalse, reason: en);
        expect(S.bangla.zikirName(name), name);
        final m = S.en.zikirMeaning(name, defaultMeaningFor(name));
        expect(m, isNot(defaultMeaningFor(name)), reason: name);
        expect(RegExp('[ঀ-৿]').hasMatch(m), isFalse, reason: m);
      }
      for (final p in [
        'ফজর',
        'ইশরাক',
        'চাশত',
        'জোহর',
        'আসর',
        'মাগরিব',
        'ইশা',
        'তাহাজ্জুদ',
      ]) {
        expect(RegExp('[ঀ-৿]').hasMatch(S.en.prayer(p)), isFalse, reason: p);
        expect(S.bangla.prayer(p), p);
      }
      expect(S.en.prayer(''), '');
    });

    test('things you wrote yourself are never translated', () {
      expect(S.en.zikirName('My own zikir'), 'My own zikir');
      expect(S.en.zikirName('আমার জিকির'), 'আমার জিকির');
      // a built-in zikir whose meaning you edited keeps your text
      final name = defaultZikirNames.first;
      expect(S.en.zikirMeaning(name, 'আমার লেখা অর্থ'), 'আমার লেখা অর্থ');
      expect(S.en.zikirMeaning('My own zikir', 'something'), 'something');
      expect(S.en.zikirMeaning(name, ''), '');
    });

    test('every screen string exists in both languages and differs', () {
      String keep(S s) => [
        s.appName,
        s.cancel,
        s.save,
        s.delete,
        s.menuLanguage,
        s.menuAppLock,
        s.congratsTitle,
        s.congratsButton,
        s.summary,
        s.dayWise,
        s.allTotal,
        s.lockSolveToOpen,
        s.updNow,
        s.bulkTitle,
        s.listTitle,
        s.dragHint,
        s.prayerTimesHelp,
        s.readOnly(7),
        s.dayHeader(10, 2),
        s.week(3),
        s.doneChip(1, 20),
        s.countChipGoal(1, 20),
        s.tone('bell'),
        s.themeColor(8),
        s.themeName('Rose'),
        s.bulkBottom(2, 3, 600),
        s.deleteTitle('x'),
        s.copyright(2026),
        s.langToggleLabel,
      ].join('|');
      final en = keep(S.en), bn = keep(S.bangla);
      expect(en, isNot(bn));
    }, skip: false);
  });

  group('language setting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      lang.useForTest('bn');
    });

    test(
      'Bangla is the default; a saved choice is what the app opens in',
      () async {
        final l = Lang();
        await l.load();
        expect(l.code, 'bn');
        expect(l.defaultCode, 'bn');

        await l.setDefault('en');
        expect(l.code, 'en'); // switches right away
        final p = await SharedPreferences.getInstance();
        expect(p.getString('langDefault'), 'en');

        final again = Lang();
        await again.load(); // "next start"
        expect(again.code, 'en');
        expect(again.defaultCode, 'en');
      },
    );

    test(
      'the quick switch changes only this session, not the saved default',
      () async {
        final l = Lang();
        await l.load();
        await l.setDefault('bn');
        l.toggle();
        expect(l.code, 'en');
        expect(l.defaultCode, 'bn');
        final p = await SharedPreferences.getInstance();
        expect(p.getString('langDefault'), 'bn');

        final next = Lang();
        await next.load(); // restart: back to the default
        expect(next.code, 'bn');
        l.toggle();
        expect(l.code, 'bn');
      },
    );

    test('garbage in storage falls back to Bangla', () async {
      SharedPreferences.setMockInitialValues({'langDefault': 'fr'});
      final l = Lang();
      await l.load();
      expect(l.code, 'bn');
    });
  });

  group('screens', () {
    Finder lcd(String n) =>
        find.descendant(of: find.byType(CounterDevice), matching: find.text(n));

    Future<List<Category>> pumpApp(WidgetTester tester, {int count = 0}) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      SharedPreferences.setMockInitialValues({
        'sound': false,
        'currentCategory': cats[0].id,
        'prayerOverride': 'জোহর',
        'count': count,
        if (count > 0) 'start': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(const TasbihApp());
      await settle(tester, until: find.textContaining('/'));
      return cats;
    }

    testWidgets(
      'the app opens in Bangla by default and shows no English UI text',
      (tester) async {
        lang.useForTest('bn');
        await pumpApp(tester);
        await settle(tester, until: find.text('পড়া: ০/২০'));
        expect(find.text('পড়া: ০/২০'), findsOneWidget);
        expect(find.text('আজ'), findsOneWidget); // today tile
        expect(find.text('সর্বমোট'), findsOneWidget); // all-total tile
        expect(find.text('TODAY'), findsNothing);
        expect(find.text('Zikir'), findsNothing);
        expect(find.text('জিকির'), findsWidgets);
        expect(
          find.text('EN'),
          findsOneWidget,
        ); // the quick button names the other language
        expect(find.byTooltip('কম্পন চালু'), findsOneWidget);
        expect(
          find.byTooltip('শব্দ বন্ধ'),
          findsOneWidget,
        ); // sound is off in this test
        expect(find.textContaining('©'), findsOneWidget);

        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        for (final t in [
          'জিকিরের তালিকা',
          'নামাজের সময়সূচী',
          'থিম',
          'শব্দ',
          'একসাথে ইমপোর্ট',
          'ভাষা',
          'অ্যাপ লক',
          'আপডেট দেখুন',
          'চলমান গণনা মুছুন',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('Theme'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the quick button switches language without losing the running count',
      (tester) async {
        lang.useForTest('bn');
        await pumpApp(tester, count: 7);
        await settle(tester, until: find.text('পড়া: ০/২০'));
        expect(lcd('7'), findsOneWidget); // LCD keeps Latin digits
        expect(find.text('আজ'), findsOneWidget);

        await tester.tap(find.byKey(const Key('lang-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('Done: 0/20'), findsOneWidget);
        expect(find.text('বাং'), findsOneWidget); // now offers the way back
        expect(lcd('7'), findsOneWidget); // count survived
        expect(find.text('আজ'), findsNothing);
        expect(lang.defaultCode, 'bn'); // only this session changed

        await tester.tap(find.byKey(const Key('lang-toggle')));
        await tester.pumpAndSettle();
        expect(find.text('আজ'), findsOneWidget);
        expect(lcd('7'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('built-in zikirs read in English when English is on', (
      tester,
    ) async {
      lang.useForTest('en');
      final cats = await pumpApp(tester);
      await settle(tester, until: find.text('Done: 0/20'));
      // the card shows the English transliteration and meaning, not the Bangla text
      expect(
        find.textContaining(S.en.zikirName(cats[0].name), findRichText: true),
        findsWidgets,
      );
      expect(find.text('Allah is pure.'), findsOneWidget);
      expect(find.textContaining('আল্লাহ পবিত্র'), findsNothing);
      lang.useForTest('bn');
    });

    testWidgets(
      'language dialog: choosing a default switches now and is saved',
      (tester) async {
        lang.useForTest('bn');
        await pumpApp(tester);
        await settle(tester, until: find.text('পড়া: ০/২০'));

        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ভাষা'));
        await tester.pumpAndSettle();
        expect(find.text('বাংলা'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);

        await tester.tap(find.byKey(const Key('lang-en')));
        await tester.pumpAndSettle();
        expect(lang.defaultCode, 'en');
        expect(lang.code, 'en');
        expect(
          find.text('Language'),
          findsOneWidget,
        ); // the dialog itself switched too
        final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
        expect(prefs.getString('langDefault'), 'en');

        await tester.tap(find.byKey(const Key('lang-bn')));
        await tester.pumpAndSettle();
        expect(lang.defaultCode, 'bn');
        expect(find.text('ভাষা'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('day page in Bangla: Bangla digits, names and messages', (
      tester,
    ) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      await tester.runAsync(() async {
        await Db.saveCount(cats[0].id, ymd(recent), 'জোহর', 100);
        await Db.saveCount(cats[1].id, ymd(recent), 'আসর', 50);
      });
      await tester.pumpWidget(page(DayPage(date: recent), 'bn'));
      await settle(tester, until: find.text('জোহর'));

      expect(find.text('মোট = ১৫০   (২টি জিকির)'), findsOneWidget);
      expect(find.text('জোহর'), findsOneWidget);
      expect(find.text('সারাদিনের মোট'), findsOneWidget);
      expect(
        find.textContaining(S.bangla.digits('${recent.year}')),
        findsOneWidget,
      );
      expect(find.byTooltip('আগের দিন'), findsOneWidget);
      expect(find.byTooltip('পরের দিন'), findsOneWidget);

      await tester.tap(find.text('জোহর'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(cats[0].name)); // recent day is editable
      await tester.pumpAndSettle();
      expect(find.text('আগে ছিল ১০০'), findsOneWidget);
      expect(find.text('সংরক্ষণ'), findsOneWidget);
      expect(find.text('বাতিল'), findsOneWidget);
      await tester.tap(find.byKey(const Key('count-field')));
      await tester.enterText(find.byKey(const Key('count-field')), '0');
      await tester.pump();
      expect(find.text('০ সংরক্ষণ করলে এই এন্ট্রি মুছে যাবে।'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same day in English uses English names and numbers', (
      tester,
    ) async {
      phone(tester);
      final cats = (await tester.runAsync(() => Db.categories()))!;
      await tester.pumpWidget(page(DayPage(date: recent), 'en'));
      await settle(tester, until: find.text('Zuhr'));
      expect(find.text('Total = 150   (2 zikir)'), findsOneWidget);
      expect(find.text('Day total'), findsOneWidget);
      await tester.tap(find.text('Zuhr'));
      await tester.pumpAndSettle();
      expect(find.text(S.en.zikirName(cats[0].name)), findsOneWidget);
      expect(find.text(cats[0].name), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('other pages open in Bangla without English leftovers', (
      tester,
    ) async {
      phone(tester);
      SharedPreferences.setMockInitialValues({'sound': false});

      Future<void> expectBangla(
        Widget home,
        List<String> texts,
        List<String> absent,
      ) async {
        await tester.pumpWidget(page(home, 'bn'));
        await settle(tester);
        await settle(tester);
        for (final t in texts) {
          expect(find.textContaining(t), findsWidgets, reason: t);
        }
        for (final t in absent) {
          expect(find.text(t), findsNothing, reason: t);
        }
        expect(tester.takeException(), isNull);
      }

      await expectBangla(
        const SummaryPage(),
        ['সারসংক্ষেপ', 'মোট জিকির'],
        ['Summary'],
      );
      await expectBangla(
        const MonthsPage(),
        ['সর্বমোট', 'গত দিন', 'এই সপ্তাহ', 'এই মাস', 'মাসভিত্তিক'],
        ['All total', 'This week'],
      );
      await expectBangla(
        const BulkImportPage(),
        ['একসাথে ইমপোর্ট', 'ইতিহাসে যোগ করুন', 'শুরু', 'শেষ'],
        ['Bulk import', 'Add to history'],
      );
      await expectBangla(
        const ZikirListPage(),
        ['জিকিরের তালিকা', 'ক্রম ঠিক করতে'],
        ['Zikir list'],
      );
      await expectBangla(
        const PrayerTimesPage(),
        ['নামাজের সময়সূচী', 'গণনা যে সময়ে'],
        ['Prayer times'],
      );
    });
  });
}
