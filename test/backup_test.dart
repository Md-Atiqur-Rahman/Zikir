import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:digital_tasbih/backup.dart';
import 'package:digital_tasbih/db.dart';
import 'package:digital_tasbih/l10n.dart';
import 'package:digital_tasbih/sound.dart';
import 'package:digital_tasbih/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Export / restore: the file, its checks, and the page with a fake file dialog.
void main() {
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('zikir_backup');
    await databaseFactory.setDatabasesPath(dir.path);
    await initializeDateFormatting('bn');
  });

  tearDownAll(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    lang.useForTest('en');
  });

  /// Everything stored, as one comparable string.
  Future<String> snapshot() async {
    final all = await Db.dumpAll();
    return jsonEncode({
      'c': all.categories,
      'e': all.entries,
      'p': all.prayers,
    });
  }

  /// Gives the database some history and some edits worth keeping.
  Future<void> fillWithData() async {
    final cats = await Db.categories();
    await Db.bulkAdd(DateTime(2026, 11, 1), DateTime(2026, 11, 5), {
      cats[0].id: 100,
      cats[4].id: 21,
    }, 'ফজর');
    await Db.saveCount(cats[2].id, '2026-11-03', 'আসর', 33);
    await Db.saveCount(cats[2].id, '2026-11-03', '', 7);
    await Db.updateCategory(
      cats[1].id,
      'My renamed zikir',
      '50',
      'my own meaning',
      50,
      10,
    );
    await Db.reorder([for (final c in cats.reversed) c.id]);
    final prayers = await Db.prayers();
    prayers[0].startMin = 4 * 60 + 45;
    await Db.updatePrayer(prayers[0]);
  }

  Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

  Map<String, Object?> minimalDoc() => {
    'app': 'zikir',
    'version': 1,
    'categories': [
      {'id': 1, 'name': 'A'},
      {'id': 2, 'name': 'B'},
    ],
    'prayers': [
      {'name': 'P', 'order': 0, 'start': 60, 'end': 120},
    ],
    'entries': [
      {'categoryId': 1, 'date': '2026-11-01', 'prayer': 'P', 'count': 5},
    ],
  };

  group('the backup file', () {
    test(
      'fresh app: a backup has the 20 zikirs, 8 prayers and no counts',
      () async {
        final data = await Backup.build(now: DateTime(2026, 11, 20, 9, 30));
        expect(data['app'], 'zikir');
        expect(data['version'], backupVersion);
        expect(data['exportedAt'], '2026-11-20T09:30:00.000');
        final parsed = Backup.parse(Backup.encode(data));
        expect(parsed.summary.zikirs, 20);
        expect(parsed.summary.entries, 0);
        expect(parsed.summary.total, 0);
        expect(parsed.summary.firstDate, isNull);
        expect(parsed.prayers.length, 8);
        expect(parsed.summary.exportedAt, DateTime(2026, 11, 20, 9, 30));
      },
    );

    test('file name carries the date', () {
      expect(
        Backup.fileName(DateTime(2026, 11, 20)),
        'zikir-backup-2026-11-20.json',
      );
    });

    test(
      'everything survives export -> change everything -> restore',
      () async {
        await fillWithData();
        final cats = await Db.categories();

        // settings worth keeping
        await themeController.set(ZikirTheme.presets[2]); // Midnight
        await Beeper.setInterval('bell');
        await Beeper.setDone('alarm');
        await lang.setDefault('en');
        final p = await SharedPreferences.getInstance();
        await p.setBool('vibrate', false);
        await p.setBool('sound', false);
        await p.setInt('currentCategory', cats[3].id);
        final before = await snapshot();
        final text = Backup.encode(await Backup.build());

        // wreck the app
        await Db.deleteCategory(cats[0].id);
        await Db.addCategory('Junk');
        await Db.saveCount(cats[5].id, '2026-11-09', 'জোহর', 999);
        await themeController.set(ZikirTheme.presets[0]);
        await Beeper.setInterval('beep');
        await Beeper.setDone('triple');
        await lang.setDefault('bn');
        await p.setBool('vibrate', true);
        await p.setBool('sound', true);
        await p.setInt('currentCategory', cats[7].id);
        expect(await snapshot(), isNot(before));

        await Backup.restore(Backup.parse(text));

        expect(await snapshot(), before); // every row, id and order is back
        expect(themeController.value.name, 'Midnight');
        expect(Beeper.interval, 'bell');
        expect(Beeper.done, 'alarm');
        expect(lang.defaultCode, 'en');
        expect(p.getBool('vibrate'), isFalse);
        expect(p.getBool('sound'), isFalse);
        expect(p.getInt('currentCategory'), cats[3].id);

        // edits to a built-in zikir and to a prayer window are part of it
        final back = await Db.categories();
        final renamed = back.firstWhere((c) => c.name == 'My renamed zikir');
        expect(
          (renamed.name, renamed.goal, renamed.beepEvery),
          ('My renamed zikir', 50, 10),
        );
        expect((await Db.prayers())[0].startMin, 4 * 60 + 45);
        expect(await Db.dayTotal('2026-11-03'), 100 + 21 + 33 + 7);
      },
    );

    test('the summary tells what is in the file', () async {
      final parsed = Backup.parse(Backup.encode(await Backup.build()));
      expect(parsed.summary.zikirs, (await Db.categories()).length);
      final now = await Backup.current();
      expect(parsed.summary.entries, now.entries);
      expect(parsed.summary.total, now.total);
      expect(parsed.summary.firstDate, '2026-11-01');
      expect(parsed.summary.lastDate, '2026-11-05');
    });

    test('a file with only the required fields still restores', () async {
      final parsed = Backup.parse(jsonEncode(minimalDoc()));
      await Backup.restore(parsed);
      final cats = await Db.categories();
      expect(cats.map((c) => c.name), ['A', 'B']);
      expect(
        cats.every((c) => c.goal == 0 && c.beepEvery == 0 && c.meaning == ''),
        isTrue,
      );
      expect(await Db.grandTotal(), 5);
      expect((await Db.prayers()).single.name, 'P');
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('currentCategory'), isNull); // no stale id left behind
    });

    test(
      'a repeated day in a hand-edited file adds up instead of failing',
      () async {
        final doc = minimalDoc();
        (doc['entries'] as List).add({
          'categoryId': 1,
          'date': '2026-11-01',
          'prayer': 'P',
          'count': 4,
        });
        await Backup.restore(Backup.parse(jsonEncode(doc)));
        expect(await Db.dayTotal('2026-11-01'), 9);
      },
    );

    test('a failure in the middle changes nothing (all or nothing)', () async {
      await Backup.restore(Backup.parse(jsonEncode(minimalDoc())));
      final before = await snapshot();
      // two zikirs with the same name break the UNIQUE rule halfway through
      await expectLater(
        Db.replaceAll(
          categories: [
            {
              'id': 1,
              'name': 'X',
              'target': '',
              'meaning': '',
              'goal': 0,
              'beep_every': 0,
              'sort_order': 1,
            },
            {
              'id': 2,
              'name': 'X',
              'target': '',
              'meaning': '',
              'goal': 0,
              'beep_every': 0,
              'sort_order': 2,
            },
          ],
          entries: [],
          prayers: [],
        ),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    });
  });

  group('files that must be refused', () {
    BackupError refused(String text) {
      try {
        Backup.parse(text);
      } on BackupError catch (e) {
        return e;
      }
      fail('accepted a bad file');
    }

    void expectBroken(Map<String, Object?> doc, String what) {
      final e = refused(jsonEncode(doc));
      expect(e.kind, BackupErrorKind.broken, reason: what);
      expect(e.detail, what);
    }

    test('not json / not ours / too new', () {
      expect(refused('').kind, BackupErrorKind.notJson);
      expect(refused('hello {').kind, BackupErrorKind.notJson);
      expect(refused('[1,2]').kind, BackupErrorKind.notZikir);
      expect(
        refused('{"app":"other","version":1}').kind,
        BackupErrorKind.notZikir,
      );
      expect(refused('{"version":1}').kind, BackupErrorKind.notZikir);
      expect(
        refused(jsonEncode({...minimalDoc(), 'version': backupVersion + 1}))
            .kind,
        BackupErrorKind.newer,
      );
      expectBroken({...minimalDoc(), 'version': 0}, 'version');
      expectBroken({...minimalDoc(), 'version': '1'}, 'version');
    });

    test('zikirs', () {
      expectBroken({...minimalDoc(), 'categories': 'x'}, 'categories');
      expectBroken({...minimalDoc(), 'categories': []}, 'categories');
      expectBroken({
        ...minimalDoc(),
        'categories': [5],
      }, 'categories');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 1, 'name': 'A'},
          {'id': 1, 'name': 'B'},
        ],
      }, 'categories');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 1, 'name': 'A'},
          {'id': 2, 'name': ' A '},
        ],
      }, 'categories');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 1, 'name': '  '},
        ],
      }, 'name');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 1, 'name': 'A', 'goal': -1},
        ],
      }, 'goal');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 0, 'name': 'A'},
        ],
      }, 'id');
      expectBroken({
        ...minimalDoc(),
        'categories': [
          {'id': 1, 'name': 7},
        ],
      }, 'name');
    });

    test('prayers', () {
      expectBroken({...minimalDoc(), 'prayers': []}, 'prayers');
      expectBroken({
        ...minimalDoc(),
        'prayers': [
          {'name': 'P', 'order': 0, 'start': 10, 'end': 20},
          {'name': 'P', 'order': 1, 'start': 10, 'end': 20},
        ],
      }, 'prayers');
      expectBroken({
        ...minimalDoc(),
        'prayers': [
          {'name': 'P', 'order': 0, 'start': 99999, 'end': 20},
        ],
      }, 'start');
    });

    test('counts', () {
      Map<String, Object?> withEntry(Map<String, Object?> e) => {
        ...minimalDoc(),
        'entries': [e],
      };
      expectBroken(
        withEntry({
          'categoryId': 9,
          'date': '2026-11-01',
          'prayer': '',
          'count': 1,
        }),
        'entries',
      );
      expectBroken(
        withEntry({
          'categoryId': 1,
          'date': '2026-13-45',
          'prayer': '',
          'count': 1,
        }),
        'entries',
      );
      expectBroken(
        withEntry({
          'categoryId': 1,
          'date': '20261101',
          'prayer': '',
          'count': 1,
        }),
        'entries',
      );
      expectBroken(
        withEntry({
          'categoryId': 1,
          'date': '2026-11-01',
          'prayer': '',
          'count': 0,
        }),
        'count',
      );
      expectBroken(
        withEntry({
          'categoryId': 1,
          'date': '2026-11-01',
          'prayer': '',
          'count': '5',
        }),
        'count',
      );
      expectBroken(
        withEntry({
          'categoryId': 1,
          'date': '2026-11-01',
          'prayer': 5,
          'count': 5,
        }),
        'prayer',
      );
      expectBroken({...minimalDoc(), 'entries': null}, 'entries');
    });

    test('bad settings are skipped, not fatal', () {
      final doc = minimalDoc();
      doc['settings'] = {
        'theme': {
          'name': 'x',
          'colors': [1, 2],
        },
        'toneInterval': 'no-such-tone',
        'toneDone': 5,
        'language': 'fr',
        'vibrate': 'yes',
        'sound': 1,
        'currentCategoryId': 99,
      };
      expect(Backup.parse(jsonEncode(doc)).settings, isEmpty);
      doc['settings'] = {
        'toneInterval': 'bell',
        'language': 'bn',
        'vibrate': false,
        'currentCategoryId': 2,
      };
      expect(Backup.parse(jsonEncode(doc)).settings, {
        'toneInterval': 'bell',
        'language': 'bn',
        'vibrate': false,
        'currentCategoryId': 2,
      });
    });

    test('messages read well in both languages', () {
      const e = BackupError(BackupErrorKind.broken, 'entries');
      expect(e.message(S.en), contains('damaged'));
      expect(e.message(S.en), contains('entries'));
      expect(e.message(S.bangla), contains('নষ্ট'));
      expect(
        const BackupError(BackupErrorKind.newer).message(S.bangla),
        contains('আপডেট'),
      );
      expect(
        const BackupError(BackupErrorKind.notZikir).toString(),
        contains('not a Zikir'),
      );
    });
  });

  group('the page', () {
    Widget app(
      String code, {
      SaveBackupFile? save,
      PickBackupFile? pick,
      DateTime? now,
    }) => MaterialApp(
      locale: Locale(code),
      supportedLocales: const [Locale('bn'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BackupPage(
                    save: save,
                    pick: pick,
                    now: () => now ?? DateTime(2026, 11, 20, 14, 5),
                  ),
                ),
              ),
              child: const Text('open backup'),
            ),
          ),
        ),
      ),
    );

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(412 * 2, 915 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
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

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('open backup'));
      await tester.pumpAndSettle();
      await settle(tester, until: find.byKey(const Key('backup-status')));
    }

    testWidgets(
      'export: hands the file to the save dialog and remembers the time',
      (tester) async {
        phone(tester);
        String? name;
        Uint8List? bytes;
        await tester.pumpWidget(
          app(
            'en',
            save: (n, b) async {
              name = n;
              bytes = b;
              return true;
            },
          ),
        );
        await open(tester);
        expect(find.textContaining('No backup saved yet.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('export-button')));
        await settle(tester, until: find.text('Backup saved'));
        await tester.pumpAndSettle();

        expect(name, 'zikir-backup-2026-11-20.json');
        final parsed = Backup.parse(utf8.decode(bytes!));
        expect(
          parsed.summary.zikirs,
          (await tester.runAsync(Db.categories))!.length,
        );
        expect(find.text('Backup saved'), findsOneWidget);
        expect(
          find.textContaining('zikir-backup-2026-11-20.json'),
          findsOneWidget,
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Last backup: 20 Nov 2026, 14:05'),
          findsOneWidget,
        );
        final p = (await tester.runAsync(SharedPreferences.getInstance))!;
        expect(p.getString('lastBackup'), '2026-11-20T14:05:00.000');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('export: cancelling the dialog changes nothing', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(app('en', save: (n, b) async => false));
      await open(tester);
      await tester.tap(find.byKey(const Key('export-button')));
      await settle(tester);
      await settle(tester);
      expect(find.text('Backup saved'), findsNothing);
      expect(find.textContaining('No backup saved yet.'), findsOneWidget);
      final p = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(p.getString('lastBackup'), isNull);
    });

    testWidgets('export: a failing file dialog shows the reason', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        app('en', save: (n, b) async => throw 'disk is full'),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('export-button')));
      await settle(tester, until: find.textContaining('disk is full'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not save the backup: disk is full'),
        findsOneWidget,
      );
      final p = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(p.getString('lastBackup'), isNull);
    });

    testWidgets(
      'restore: shows file vs app, then replaces only after you agree',
      (tester) async {
        phone(tester);
        // the backup holds the minimal file's data; the app starts from other,
        // known data (not from whatever an earlier test left behind)
        final fileText = jsonEncode(minimalDoc());
        await tester.runAsync(
          () => Db.replaceAll(
            categories: [
              for (var i = 11; i <= 13; i++)
                {
                  'id': i,
                  'name': 'Zikir $i',
                  'target': '',
                  'meaning': '',
                  'goal': 0,
                  'beep_every': 0,
                  'sort_order': i,
                },
            ],
            entries: [
              {
                'category_id': 11,
                'date': '2026-11-02',
                'prayer': '',
                'count': 40,
              },
              {
                'category_id': 12,
                'date': '2026-11-03',
                'prayer': '',
                'count': 60,
              },
            ],
            prayers: [
              {'name': 'Q', 'ord': 0, 'start_min': 0, 'end_min': 60},
            ],
          ),
        );
        final before = (await tester.runAsync(snapshot))!;

        await tester.pumpWidget(app('en', pick: () async => bytesOf(fileText)));
        await open(tester);

        // 1) cancel at the question: nothing changes
        await tester.tap(find.byKey(const Key('restore-button')));
        await settle(tester, until: find.text('Replace everything?'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('In the file: 2 zikirs, 1 saved days, total 5'),
          findsOneWidget,
        );
        expect(find.textContaining('In the app now: '), findsWidgets);
        expect(find.textContaining('cannot be undone'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect((await tester.runAsync(snapshot))!, before);
        expect(find.text('Restored'), findsNothing);

        // 2) agree: everything is replaced
        await tester.tap(find.byKey(const Key('restore-button')));
        await settle(tester, until: find.text('Replace everything?'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace'));
        await settle(tester, until: find.text('Restored'));
        await tester.pumpAndSettle();
        expect(find.text('Restored'), findsOneWidget);
        expect((await tester.runAsync(snapshot))!, isNot(before));
        expect((await tester.runAsync(Db.categories))!.map((c) => c.name), [
          'A',
          'B',
        ]);

        // closing the message leaves the page
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('restore-button')), findsNothing);
        expect(find.text('open backup'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('restore: bad files are explained and nothing is touched', (
      tester,
    ) async {
      phone(tester);
      await tester.runAsync(
        () => Backup.restore(Backup.parse(jsonEncode(minimalDoc()))),
      );
      final before = (await tester.runAsync(snapshot))!;

      Future<void> tryFile(Uint8List bytes, String message) async {
        await tester.pumpWidget(app('en', pick: () async => bytes));
        await open(tester);
        await tester.tap(find.byKey(const Key('restore-button')));
        await settle(tester, until: find.textContaining(message));
        await tester.pumpAndSettle();
        expect(find.textContaining(message), findsOneWidget, reason: message);
        expect(find.text('Replace everything?'), findsNothing);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect((await tester.runAsync(snapshot))!, before);
        // back to the launcher for the next file
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tryFile(bytesOf('hello, I am not json'), 'not a readable backup');
      await tryFile(
        Uint8List.fromList([0xff, 0xfe, 0x00, 0x80]),
        'not a readable backup',
      );
      await tryFile(bytesOf('{"app":"other"}'), 'not a Zikir backup');
      await tryFile(
        bytesOf(jsonEncode({...minimalDoc(), 'version': 99})),
        'newer version',
      );
      await tryFile(
        bytesOf(jsonEncode({...minimalDoc(), 'entries': 5})),
        'damaged or incomplete (entries)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'restore: closing the file dialog without a file does nothing',
      (tester) async {
        phone(tester);
        await tester.pumpWidget(app('en', pick: () async => null));
        await open(tester);
        await tester.tap(find.byKey(const Key('restore-button')));
        await settle(tester);
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('the page and its messages are Bangla in Bangla', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        app(
          'bn',
          pick: () async => bytesOf('not json'),
          save: (n, b) async => true,
        ),
      );
      await open(tester);
      expect(find.text('ব্যাকআপ ও রিস্টোর'), findsOneWidget);
      expect(find.text('ব্যাকআপ এক্সপোর্ট'), findsOneWidget);
      expect(find.text('ফাইল থেকে রিস্টোর'), findsOneWidget);
      expect(find.text('ব্যাকআপ ফাইল সংরক্ষণ করুন'), findsOneWidget);
      expect(find.text('ব্যাকআপ ফাইল বাছুন'), findsOneWidget);
      expect(find.textContaining('এখন অ্যাপে আছে:'), findsOneWidget);
      expect(
        find.textContaining('এখনো কোনো ব্যাকআপ সংরক্ষণ করা হয়নি'),
        findsOneWidget,
      );
      expect(find.text('Backup & restore'), findsNothing);

      await tester.tap(find.byKey(const Key('restore-button')));
      await settle(tester, until: find.textContaining('পড়ার মতো ব্যাকআপ নয়'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('এই ফাইলটি পড়ার মতো ব্যাকআপ নয়।'),
        findsOneWidget,
      );
      await tester.tap(find.text('ঠিক আছে'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export-button')));
      await settle(tester, until: find.text('ব্যাকআপ সংরক্ষিত হয়েছে'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('zikir-backup-২০২৬'),
        findsNothing,
      ); // the file name stays Latin
      expect(
        find.textContaining('zikir-backup-2026-11-20.json'),
        findsOneWidget,
      );
      await tester.tap(find.text('ঠিক আছে'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('শেষ ব্যাকআপ: ২০ নভে ২০২৬, ১৪:০৫'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
