import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'l10n.dart';
import 'sound.dart';
import 'theme.dart';

/// Version of the backup file layout. A file with a higher number was made by a
/// newer app and is refused instead of being half-understood.
const backupVersion = 1;

enum BackupErrorKind { notJson, notZikir, newer, broken }

/// Why a file could not be used as a backup; shown in the current language.
class BackupError implements Exception {
  final BackupErrorKind kind;
  final String detail;
  const BackupError(this.kind, [this.detail = '']);

  String message(S s) => switch (kind) {
    BackupErrorKind.notJson => s.backupNotJson,
    BackupErrorKind.notZikir => s.backupNotZikir,
    BackupErrorKind.newer => s.backupNewer,
    BackupErrorKind.broken => s.backupBroken(detail),
  };

  @override
  String toString() => message(S.en);
}

/// What is inside a backup (or in the app), for the confirmation dialog.
class BackupSummary {
  final int zikirs;
  final int entries;
  final int total;
  final String? firstDate;
  final String? lastDate;
  final DateTime? exportedAt;
  const BackupSummary({
    required this.zikirs,
    required this.entries,
    required this.total,
    this.firstDate,
    this.lastDate,
    this.exportedAt,
  });
}

/// A backup that passed every check and is ready to be restored.
class ParsedBackup {
  final List<Map<String, Object?>> categories;
  final List<Map<String, Object?>> entries;
  final List<Map<String, Object?>> prayers;
  final Map<String, Object?> settings;
  final BackupSummary summary;
  const ParsedBackup({
    required this.categories,
    required this.entries,
    required this.prayers,
    required this.settings,
    required this.summary,
  });
}

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// True only for a real calendar day written as yyyy-MM-dd. (`DateTime.tryParse`
/// alone accepts 2026-13-45 and quietly turns it into another date.)
bool _isRealDate(String v) {
  if (!_dateRe.hasMatch(v)) {
    return false;
  }
  final d = DateTime.tryParse(v);
  return d != null && ymd(d) == v;
}

class Backup {
  /// The whole app as a JSON-ready map: zikirs, every saved count, prayer
  /// windows and the settings worth keeping (theme, tones, language, switches).
  static Future<Map<String, Object?>> build({DateTime? now}) async {
    final all = await Db.dumpAll();
    final p = await SharedPreferences.getInstance();

    Object? theme;
    final rawTheme = p.getString('theme');
    if (rawTheme != null) {
      try {
        theme = jsonDecode(rawTheme);
      } catch (_) {
        theme = null; // an unreadable theme is simply not backed up
      }
    }

    return {
      'app': 'zikir',
      'version': backupVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'categories': [
        for (final c in all.categories)
          {
            'id': c['id'],
            'name': c['name'],
            'target': c['target'],
            'meaning': c['meaning'],
            'goal': c['goal'],
            'beepEvery': c['beep_every'],
            'order': c['sort_order'],
          },
      ],
      'entries': [
        for (final e in all.entries)
          {
            'categoryId': e['category_id'],
            'date': e['date'],
            'prayer': e['prayer'],
            'count': e['count'],
          },
      ],
      'prayers': [
        for (final r in all.prayers)
          {
            'name': r['name'],
            'order': r['ord'],
            'start': r['start_min'],
            'end': r['end_min'],
          },
      ],
      'settings': {
        'theme': ?theme,
        'toneInterval': Beeper.interval,
        'toneDone': Beeper.done,
        'language': lang.defaultCode,
        'vibrate': p.getBool('vibrate') ?? true,
        'sound': p.getBool('sound') ?? true,
        'currentCategoryId': ?p.getInt('currentCategory'),
      },
    };
  }

  static String encode(Map<String, Object?> data) =>
      const JsonEncoder.withIndent('  ').convert(data);

  static String fileName(DateTime now) => 'zikir-backup-${ymd(now)}.json';

  /// Reads and checks a backup. Throws [BackupError] with a clear reason.
  static ParsedBackup parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const BackupError(BackupErrorKind.notJson);
    }
    if (decoded is! Map || decoded['app'] != 'zikir') {
      throw const BackupError(BackupErrorKind.notZikir);
    }
    final root = decoded;
    final version = root['version'];
    if (version is! int || version < 1) {
      throw const BackupError(BackupErrorKind.broken, 'version');
    }
    if (version > backupVersion) {
      throw const BackupError(BackupErrorKind.newer);
    }

    BackupError bad(String what) => BackupError(BackupErrorKind.broken, what);

    List<Map> listOf(String key) {
      final v = root[key];
      if (v is! List) {
        throw bad(key);
      }
      return [
        for (final item in v)
          if (item is Map) item else throw bad(key),
      ];
    }

    String str(Map m, String key, {bool required = false}) {
      final v = m[key];
      if (v == null && !required) {
        return '';
      }
      if (v is! String || (required && v.trim().isEmpty)) {
        throw bad(key);
      }
      return v;
    }

    int integer(Map m, String key, {int min = 0, int max = 1 << 31}) {
      final v = m[key];
      if (v is! int || v < min || v > max) {
        throw bad(key);
      }
      return v;
    }

    // ---- zikirs
    final categories = <Map<String, Object?>>[];
    final ids = <int>{};
    final names = <String>{};
    for (final c in listOf('categories')) {
      final id = integer(c, 'id', min: 1);
      final name = str(c, 'name', required: true).trim();
      if (!ids.add(id) || !names.add(name)) {
        throw bad('categories');
      }
      categories.add({
        'id': id,
        'name': name,
        'target': str(c, 'target'),
        'meaning': str(c, 'meaning'),
        'goal': c['goal'] == null ? 0 : integer(c, 'goal'),
        'beep_every': c['beepEvery'] == null ? 0 : integer(c, 'beepEvery'),
        'sort_order': c['order'] == null ? id : integer(c, 'order'),
      });
    }
    if (categories.isEmpty) {
      throw bad('categories');
    }

    // ---- prayer windows
    final prayers = <Map<String, Object?>>[];
    final prayerNames = <String>{};
    for (final r in listOf('prayers')) {
      final name = str(r, 'name', required: true);
      if (!prayerNames.add(name)) {
        throw bad('prayers');
      }
      prayers.add({
        'name': name,
        'ord': integer(r, 'order'),
        'start_min': integer(r, 'start', max: 1440),
        'end_min': integer(r, 'end', max: 1440),
      });
    }
    if (prayers.isEmpty) {
      throw bad('prayers');
    }

    // ---- saved counts
    final entries = <Map<String, Object?>>[];
    var total = 0;
    String? first;
    String? last;
    for (final e in listOf('entries')) {
      final categoryId = integer(e, 'categoryId', min: 1);
      final date = str(e, 'date', required: true);
      if (!ids.contains(categoryId) || !_isRealDate(date)) {
        throw bad('entries');
      }
      final count = integer(e, 'count', min: 1, max: 1000000000);
      entries.add({
        'category_id': categoryId,
        'date': date,
        'prayer': str(e, 'prayer'),
        'count': count,
      });
      total += count;
      if (first == null || date.compareTo(first) < 0) {
        first = date;
      }
      if (last == null || date.compareTo(last) > 0) {
        last = date;
      }
    }

    // ---- settings: unknown or wrong-typed values are skipped, never fatal
    final settings = <String, Object?>{};
    final raw = root['settings'];
    if (raw is Map) {
      final theme = raw['theme'];
      if (theme is Map && ZikirTheme.fromJson(theme.cast()) != null) {
        settings['theme'] = theme;
      }
      for (final k in ['toneInterval', 'toneDone']) {
        final v = raw[k];
        if (v is String && Beeper.tones.any((t) => t.id == v)) {
          settings[k] = v;
        }
      }
      final l = raw['language'];
      if (l == 'bn' || l == 'en') {
        settings['language'] = l;
      }
      for (final k in ['vibrate', 'sound']) {
        if (raw[k] is bool) {
          settings[k] = raw[k];
        }
      }
      final cur = raw['currentCategoryId'];
      if (cur is int && ids.contains(cur)) {
        settings['currentCategoryId'] = cur;
      }
    }

    final at = root['exportedAt'];
    return ParsedBackup(
      categories: categories,
      entries: entries,
      prayers: prayers,
      settings: settings,
      summary: BackupSummary(
        zikirs: categories.length,
        entries: entries.length,
        total: total,
        firstDate: first,
        lastDate: last,
        exportedAt: at is String ? DateTime.tryParse(at) : null,
      ),
    );
  }

  /// Replaces all data and the backed-up settings, then refreshes what is live.
  static Future<void> restore(ParsedBackup b) async {
    await Db.replaceAll(
      categories: b.categories,
      entries: b.entries,
      prayers: b.prayers,
    );
    final p = await SharedPreferences.getInstance();
    final st = b.settings;
    if (st['theme'] != null) {
      await p.setString('theme', jsonEncode(st['theme']));
    }
    if (st['toneInterval'] != null) {
      await p.setString('toneInterval', st['toneInterval'] as String);
    }
    if (st['toneDone'] != null) {
      await p.setString('toneDone', st['toneDone'] as String);
    }
    if (st['language'] != null) {
      await p.setString('langDefault', st['language'] as String);
    }
    if (st['vibrate'] != null) {
      await p.setBool('vibrate', st['vibrate'] as bool);
    }
    if (st['sound'] != null) {
      await p.setBool('sound', st['sound'] as bool);
    }
    if (st['currentCategoryId'] != null) {
      await p.setInt('currentCategory', st['currentCategoryId'] as int);
    } else {
      await p.remove('currentCategory'); // the old id may not exist any more
    }
    await themeController.load();
    await Beeper.load();
    await lang.reload();
  }

  /// What is in the app right now.
  static Future<BackupSummary> current() async {
    final all = await Db.dumpAll();
    var total = 0;
    String? first;
    String? last;
    for (final e in all.entries) {
      total += e['count'] as int;
      final d = e['date'] as String;
      if (first == null || d.compareTo(first) < 0) {
        first = d;
      }
      if (last == null || d.compareTo(last) > 0) {
        last = d;
      }
    }
    return BackupSummary(
      zikirs: all.categories.length,
      entries: all.entries.length,
      total: total,
      firstDate: first,
      lastDate: last,
    );
  }
}

/// Writes a file for the user. Returns false when they cancelled the dialog.
typedef SaveBackupFile = Future<bool> Function(String name, Uint8List bytes);

/// Lets the user choose a file. Returns null when they cancelled.
typedef PickBackupFile = Future<Uint8List?> Function();

Future<bool> _saveWithPicker(String name, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: name,
    bytes: bytes,
    mimeType: 'application/json',
  );
  return uri != null;
}

Future<Uint8List?> _pickWithPicker() async {
  final f = await FilePicker.pickFile();
  return f?.readAsBytes();
}

/// Menu → Backup & restore.
class BackupPage extends StatefulWidget {
  /// Replaceable so the page can be tested without a real file dialog.
  final SaveBackupFile? save;
  final PickBackupFile? pick;
  final DateTime Function()? now;
  const BackupPage({super.key, this.save, this.pick, this.now});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  BackupSummary? _now;
  DateTime? _lastBackup;
  bool _busy = false;

  DateTime _clock() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await Backup.current();
    final p = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(p.getString('lastBackup') ?? '');
    if (!mounted) {
      return;
    }
    setState(() {
      _now = summary;
      _lastBackup = last;
    });
  }

  Future<void> _info(String title, String body, {IconData? icon}) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: icon == null ? null : Icon(icon, size: 40),
          title: Text(title),
          content: Text(body),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(S.of(ctx).ok),
            ),
          ],
        ),
      );

  Future<void> _export() async {
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final now = _clock();
      final data = await Backup.build(now: now);
      final bytes = Uint8List.fromList(utf8.encode(Backup.encode(data)));
      final name = Backup.fileName(now);
      final saved = await (widget.save ?? _saveWithPicker)(name, bytes);
      if (!saved) {
        return; // the user cancelled
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('lastBackup', now.toIso8601String());
      if (!mounted) {
        return;
      }
      setState(() => _lastBackup = now);
      await _info(
        s.backupSaved,
        s.backupSavedBody(name),
        icon: Icons.check_circle_outline,
      );
    } catch (e) {
      if (mounted) {
        await _info(
          s.exportTitle,
          s.backupFailed('$e'),
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await (widget.pick ?? _pickWithPicker)();
      if (bytes == null) {
        return; // the user cancelled
      }

      final ParsedBackup parsed;
      try {
        parsed = Backup.parse(utf8.decode(bytes));
      } on FormatException {
        throw const BackupError(BackupErrorKind.notJson);
      }
      if (!mounted) {
        return;
      }

      final mine = await Backup.current();
      if (!mounted) {
        return;
      }
      final sum = parsed.summary;
      String d(String? v) =>
          v == null ? '-' : s.date('d MMM yyyy', DateTime.parse(v));
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, size: 40),
          title: Text(s.restoreAskTitle),
          content: SingleChildScrollView(
            child: Text(
              [
                s.restoreFileLine(
                  sum.zikirs,
                  sum.entries,
                  sum.total,
                  d(sum.firstDate),
                  d(sum.lastDate),
                ),
                if (sum.exportedAt != null)
                  s.restoreSavedOn(
                    s.date('d MMM yyyy, HH:mm', sum.exportedAt!),
                  ),
                '',
                s.backupNowLine(mine.zikirs, mine.total),
                '',
                s.restoreWarn,
              ].join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of(ctx).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(S.of(ctx).restoreReplace),
            ),
          ],
        ),
      );
      if (sure != true) {
        return;
      }

      await Backup.restore(parsed);
      if (!mounted) {
        return;
      }
      await _load();
      if (!mounted) {
        return;
      }
      await _info(s.restored, s.restoredBody, icon: Icons.check_circle_outline);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on BackupError catch (e) {
      if (mounted) {
        await _info(
          s.restoreTitle,
          e.message(S.of(context)),
          icon: Icons.error_outline,
        );
      }
    } catch (e) {
      if (mounted) {
        await _info(
          s.restoreTitle,
          s.restoreFailed('$e'),
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String help,
    required String button,
    required VoidCallback onPressed,
    required Key key,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(help),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: key,
                onPressed: _busy ? null : onPressed,
                child: Text(button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final now = _now;
    return Scaffold(
      appBar: AppBar(title: Text(s.backupTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(s.backupIntro),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              [
                if (now != null) s.backupNowLine(now.zikirs, now.total),
                _lastBackup == null
                    ? s.backupNever
                    : s.backupLast(s.date('d MMM yyyy, HH:mm', _lastBackup!)),
              ].join('\n'),
              key: const Key('backup-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _card(
            key: const Key('export-button'),
            icon: Icons.upload_file,
            title: s.exportTitle,
            help: s.exportHelp,
            button: s.exportButton,
            onPressed: _export,
          ),
          _card(
            key: const Key('restore-button'),
            icon: Icons.restore,
            title: s.restoreTitle,
            help: s.restoreHelp,
            button: s.restoreButton,
            onPressed: _restore,
          ),
        ],
      ),
    );
  }
}
