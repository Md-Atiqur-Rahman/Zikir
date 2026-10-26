import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:vibration/vibration.dart';

import 'db.dart';
import 'pages.dart';
import 'sound.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // sqflite has no web support of its own; use the wasm build there.
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  await themeController.load();
  await Beeper.load();
  runApp(const TasbihApp());
}

class TasbihApp extends StatelessWidget {
  const TasbihApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ZikirTheme>(
    valueListenable: themeController,
    builder: (_, t, _) => MaterialApp(
      title: 'Zikir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: t.bodyB,
        brightness: t.dark ? Brightness.dark : Brightness.light,
        useMaterial3: true,
      ),
      home: const CounterPage(),
    ),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

// returned by the prayer chooser for "Auto (by clock)"
const _autoKey = '__auto__';

class _CounterPageState extends State<CounterPage> {
  int _count = 0;
  bool _vibrate = true;
  bool _sound = true;
  SharedPreferences? _prefs;
  List<Category> _cats = [];
  List<Prayer> _prayers = [];
  int _todaySaved = 0; // saved today, not counting the running count
  int _allSaved = 0; // saved ever, not counting the running count
  int _doneNow =
      0; // different zikirs already saved today in the running prayer time
  int? _currentId;
  DateTime? _start; // when the running count began; decides date and prayer
  String? _prayerOverride; // prayer picked by hand for the running count; null = by clock

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final startStr = p.getString('start');
    setState(() {
      _count = p.getInt('count') ?? 0;
      _vibrate = p.getBool('vibrate') ?? true;
      _sound = p.getBool('sound') ?? true;
      _currentId = p.getInt('currentCategory');
      _start = startStr == null ? null : DateTime.tryParse(startStr);
      _prayerOverride = p.getString('prayerOverride');
    });
    await _reload();
  }

  Future<void> _reload() async {
    final cats = await Db.categories();
    final prayers = await Db.prayers();
    final today = ymd(DateTime.now());
    final todaySaved = await Db.dayTotal(today);
    final allSaved = await Db.grandTotal();
    final prayerNow =
        _prayerOverride ?? prayerAt(prayers, _start ?? DateTime.now());
    final doneNow = await Db.doneCount(today, prayerNow);
    if (mounted) {
      setState(() {
        _cats = cats;
        _prayers = prayers;
        _todaySaved = todaySaved;
        _allSaved = allSaved;
        _doneNow = doneNow;
      });
    }
  }

  Category? get _current {
    if (_cats.isEmpty) return null;
    return _cats.firstWhere(
      (c) => c.id == _currentId,
      orElse: () => _cats.first,
    );
  }

  Category _nextAfter(int id) {
    final i = _cats.indexWhere((c) => c.id == id);
    return _cats[(i + 1) % _cats.length];
  }

  void _setCurrent(int id) {
    _currentId = id;
    _prefs?.setInt('currentCategory', id);
  }

  bool? _canVibrate;
  bool _hasAmplitude = false;

  Future<void> _vibrateFor(int ms) async {
    if (!_vibrate) return;
    // look the hardware up once; asking on every tap added delay
    if (_canVibrate == null) {
      _canVibrate = await Vibration.hasVibrator();
      _hasAmplitude = await Vibration.hasAmplitudeControl();
    }
    if (_canVibrate == true) {
      Vibration.vibrate(duration: ms, amplitude: _hasAmplitude ? 255 : -1);
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _tap() async {
    setState(() {
      if (_start == null) {
        _start = DateTime.now();
        _prefs?.setString('start', _start!.toIso8601String());
      }
      _count++;
    });
    _prefs?.setInt('count', _count);

    final c = _current;
    if (c != null && c.goal > 0 && _count == c.goal) {
      // goal reached: three beeps and a long vibration
      if (_sound) Beeper.playDone();
      _vibrateFor(900);
    } else if (c != null && c.beepEvery > 0 && _count % c.beepEvery == 0) {
      if (_sound) Beeper.playInterval();
      _vibrateFor(200);
    } else {
      // 30 ms was too short for many phone motors to be felt
      _vibrateFor(60);
    }
  }

  void _toggleSound() {
    setState(() => _sound = !_sound);
    _prefs?.setBool('sound', _sound);
  }

  void _toggleVibrate() {
    setState(() => _vibrate = !_vibrate);
    _prefs?.setBool('vibrate', _vibrate);
  }

  void _clearSession() {
    setState(() {
      _count = 0;
      _start = null;
      _prayerOverride = null; // back to automatic for the next count
    });
    _prefs?.setInt('count', 0);
    _prefs?.remove('start');
    _prefs?.remove('prayerOverride');
  }

  String get _prayerNow =>
      _prayerOverride ?? prayerAt(_prayers, _start ?? DateTime.now());

  /// Tap on the prayer chip: pick the prayer time by hand, or go back to automatic.
  Future<void> _choosePrayer() async {
    final auto = prayerAt(_prayers, _start ?? DateTime.now());
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose time (ওয়াক্ত)'),
        children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Auto (by clock)'),
            subtitle: Text(auto.isEmpty ? 'No prayer window now' : auto),
            selected: _prayerOverride == null,
            onTap: () => Navigator.pop(ctx, _autoKey),
          ),
          for (final p in _prayers)
            ListTile(
              title: Text(p.name),
              selected: _prayerOverride == p.name,
              onTap: () => Navigator.pop(ctx, p.name),
            ),
          ListTile(
            title: const Text('None'),
            selected: _prayerOverride == '',
            onTap: () => Navigator.pop(ctx, ''),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _prayerOverride = picked == _autoKey ? null : picked);
    if (_prayerOverride == null) {
      _prefs?.remove('prayerOverride');
    } else {
      _prefs?.setString('prayerOverride', _prayerOverride!);
    }
    _reload();
  }

  /// Saves the running count into [cat] under the prayer window it started in,
  /// then moves on to the next zikir in the list.
  Future<void> _commit(Category cat) async {
    final start = _start ?? DateTime.now();
    final prayer = _prayerOverride ?? prayerAt(_prayers, start);
    final saved = _count;
    final date = DateFormat('yyyy-MM-dd').format(start);
    final before = await Db.doneCount(date, prayer);
    await Db.saveCount(cat.id, date, prayer, saved);
    final after = await Db.doneCount(date, prayer);
    final next = _nextAfter(cat.id);
    _setCurrent(next.id);
    _clearSession();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Saved $saved → ${cat.name}${prayer.isEmpty ? '' : ' ($prayer)'}\nNext: ${next.name}',
          ),
        ),
      );
    final total = _cats.length;
    if (total > 0 && before < total && after >= total) {
      _congratulate(prayer, total);
    }
  }

  Future<void> _congratulate(String prayer, int total) async {
    if (_sound) Beeper.playDone();
    _vibrateFor(900);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.celebration, size: 48),
        title: const Text('Congratulations!'),
        content: Text(
          'অভিনন্দন! ${prayer.isEmpty ? 'আজকের' : '$prayer-এর'} '
          'সব $total টি জিকির সম্পন্ন হয়েছে।\n\n'
          'All $total zikirs completed${prayer.isEmpty ? '' : ' for $prayer'}.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Alhamdulillah'),
          ),
        ],
      ),
    );
  }

  Future<void> _reset() async {
    final cur = _current;
    if (_count == 0 || cur == null) return;
    await _commit(cur);
  }

  /// Tap on the zikir card: pick the zikir yourself instead of following the queue.
  /// The next reset saves into it, then the queue continues from there.
  Future<void> _choose() async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => PickCategoryDialog(cats: _cats, currentId: _current?.id),
    );
    if (id == null) return;
    await _reload();
    setState(() => _setCurrent(id));
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear without saving?'),
        content: Text('The count of $_count will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) _clearSession();
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final prayer = _prayerNow;
    return ValueListenableBuilder<ZikirTheme>(
      valueListenable: themeController,
      builder: (context, t, _) => Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          title: const Text('Zikir'),
          backgroundColor: Colors.transparent,
          foregroundColor: t.onBackground,
          actions: [
            IconButton(
              tooltip: _vibrate ? 'Vibration on' : 'Vibration off',
              icon: Icon(_vibrate ? Icons.vibration : Icons.mobile_off),
              onPressed: _toggleVibrate,
            ),
            IconButton(
              tooltip: _sound ? 'Sound on' : 'Sound off',
              icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
              onPressed: _toggleSound,
            ),
            IconButton(
              tooltip: 'Summary',
              icon: const Icon(Icons.bar_chart),
              onPressed: () => _open(const SummaryPage()),
            ),
            PopupMenuButton<int>(
              onSelected: (v) {
                if (v == 5) {
                  if (_count > 0) _discard();
                  return;
                }
                _open(switch (v) {
                  0 => const ZikirListPage(),
                  1 => const PrayerTimesPage(),
                  2 => const ThemePage(),
                  3 => const SoundPage(),
                  _ => const BulkImportPage(),
                });
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('জিকিরের তালিকা')),
                const PopupMenuItem(value: 1, child: Text('নামাজের সময়সূচী')),
                const PopupMenuItem(value: 2, child: Text('Theme')),
                const PopupMenuItem(value: 3, child: Text('Sounds')),
                const PopupMenuItem(value: 4, child: Text('Bulk import')),
                PopupMenuItem(
                  value: 5,
                  enabled: _count > 0,
                  child: const Text('Clear running count'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              InfoCard(
                onTap: _choose,
                name: cur?.name ?? '',
                meaning: cur?.meaning ?? '',
                target: cur?.targetLabel ?? '',
                count: _count,
                goal: cur?.goal ?? 0,
                done: _doneNow,
                total: _cats.length,
                prayer: prayer,
                prayerManual: _prayerOverride != null,
                onPrayerTap: _choosePrayer,
                theme: t,
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CounterDevice(
                        count: _count,
                        onTap: _tap,
                        onReset: _reset,
                        theme: t,
                      ),
                    ),
                  ),
                ),
              ),
              DayStats(
                theme: t,
                today: _todaySaved + _count,
                all: _allSaved + _count,
                onToday: () => _open(DayPage(date: DateTime.now())),
                onAll: () => _open(const MonthsPage()),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Small button: save & next  •  tap the zikir name to change it',
                  style: TextStyle(color: t.onBackground, fontSize: 12),
                ),
              ),
              CopyrightFooter(theme: t),
            ],
          ),
        ),
      ),
    );
  }
}

/// Current zikir, its suggested count and the prayer time that is running.
class InfoCard extends StatelessWidget {
  final String name;
  final String meaning;
  final String target;
  final int count;
  final int goal;
  final int done;
  final int total;
  final String prayer;
  final bool prayerManual;
  final VoidCallback onPrayerTap;
  final ZikirTheme theme;
  final VoidCallback onTap;
  const InfoCard({
    super.key,
    required this.onTap,
    required this.name,
    required this.meaning,
    required this.target,
    required this.count,
    required this.goal,
    required this.done,
    required this.total,
    required this.prayer,
    required this.prayerManual,
    required this.onPrayerTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.34,
        ),
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.onBackground.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        // long zikirs scroll inside the card instead of squeezing the counter
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // the arrow hints that tapping the card opens the zikir list
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: name),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.arrow_drop_down,
                        color: theme.onBackground,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.onBackground,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (meaning.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meaning,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.onBackground.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  // always shown so the time can be changed even outside every window
                  ActionChip(
                    avatar: Icon(
                      prayerManual ? Icons.edit : Icons.access_time,
                      size: 16,
                    ),
                    label: Text(prayer.isEmpty ? 'সময়: —' : prayer),
                    onPressed: onPrayerTap,
                    visualDensity: VisualDensity.compact,
                  ),
                  if (total > 0)
                    Chip(
                      avatar: Icon(
                        done >= total ? Icons.check_circle : Icons.checklist,
                        size: 16,
                      ),
                      label: Text('পড়া: $done/$total'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (target.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.flag_outlined, size: 16),
                      label: Text(
                        goal > 0 ? 'সংখ্যা: $count / $goal' : 'সংখ্যা: $target',
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's and the all-time total; tap one for the details behind it.
class DayStats extends StatelessWidget {
  final ZikirTheme theme;
  final int today;
  final int all;
  final VoidCallback onToday;
  final VoidCallback onAll;
  const DayStats({
    super.key,
    required this.theme,
    required this.today,
    required this.all,
    required this.onToday,
    required this.onAll,
  });

  Widget _tile(IconData icon, String label, int value, VoidCallback onTap) {
    final fg = theme.onBackground;
    return Expanded(
      child: Material(
        color: fg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: fg.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 14, color: theme.glowCount),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.85),
                              fontSize: 12,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          NumberFormat.decimalPattern().format(value),
                          style: TextStyle(
                            color: fg,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: fg.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _tile(Icons.today, 'TODAY', today, onToday),
          const SizedBox(width: 10),
          _tile(Icons.all_inclusive, 'ALL TOTAL', all, onAll),
        ],
      ),
    );
  }
}

/// Copyright line with email and phone icons; tap one to see the detail and copy it.
class CopyrightFooter extends StatelessWidget {
  final ZikirTheme theme;
  const CopyrightFooter({super.key, required this.theme});

  static const email = 'atiqur.rahman.himel@gmail.com';
  static const phone = '01970091221';

  void _show(BuildContext context, IconData icon, String title, String value) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: SelectableText(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Copied $value'),
                    duration: const Duration(seconds: 2),
                  ),
                );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = theme.onBackground.withValues(alpha: 0.85);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '\u00a9 ${DateTime.now().year} Zikir',
          style: TextStyle(color: fg, fontSize: 11),
        ),
        IconButton(
          tooltip: 'Email',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.email_outlined, size: 20, color: fg),
          onPressed: () => _show(context, Icons.email_outlined, 'Email', email),
        ),
        IconButton(
          tooltip: 'Phone',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.phone_outlined, size: 20, color: fg),
          onPressed: () => _show(context, Icons.phone_outlined, 'Phone', phone),
        ),
      ],
    );
  }
}

/// Pick which zikir a count belongs to, or create a new one.
class PickCategoryDialog extends StatefulWidget {
  final List<Category> cats;
  final int? currentId;
  const PickCategoryDialog({super.key, required this.cats, this.currentId});

  @override
  State<PickCategoryDialog> createState() => _PickCategoryDialogState();
}

class _PickCategoryDialogState extends State<PickCategoryDialog> {
  bool _adding = false;
  final _name = TextEditingController();
  final _meaning = TextEditingController();
  final _goal = TextEditingController();
  final _beep = TextEditingController();

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final goal = int.tryParse(_goal.text) ?? 0;
    final id = await Db.addCategory(
      name,
      meaning: _meaning.text,
      target: goal > 0 ? '$goal' : '',
      goal: goal,
      beepEvery: int.tryParse(_beep.text) ?? 0,
    );
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose zikir'),
      content: SizedBox(
        width: double.maxFinite,
        child: _adding
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'New zikir name',
                    ),
                  ),
                  TextField(
                    controller: _meaning,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'অর্থ (meaning, optional)',
                    ),
                  ),
                  TextField(
                    controller: _goal,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Target count (optional)',
                    ),
                  ),
                  TextField(
                    controller: _beep,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Beep every (optional)',
                    ),
                  ),
                ],
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.cats.length,
                itemBuilder: (_, i) {
                  final c = widget.cats[i];
                  return ListTile(
                    dense: true,
                    selected: c.id == widget.currentId,
                    leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                    title: Text(c.name),
                    subtitle: c.targetLabel.isEmpty
                        ? null
                        : Text('সংখ্যা: ${c.targetLabel}'),
                    onTap: () => Navigator.pop(context, c.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_adding)
          FilledButton(onPressed: _add, child: const Text('Add'))
        else
          TextButton(
            onPressed: () => setState(() => _adding = true),
            child: const Text('+ New'),
          ),
      ],
    );
  }
}

/// A finger-tally counter: blue body, LCD display, big metal button to count,
/// small metal button (top right) to save & go to the next zikir.
class CounterDevice extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onReset;
  final ZikirTheme theme;
  const CounterDevice({
    super.key,
    required this.count,
    required this.onTap,
    required this.onReset,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 520,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Body
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(120),
                topRight: Radius.circular(120),
                bottomLeft: Radius.circular(160),
                bottomRight: Radius.circular(160),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [theme.bodyA, theme.bodyB, theme.bodyC],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
          ),
          // Display bezel + LCD
          Positioned(
            top: 36,
            left: 30,
            right: 30,
            child: Container(
              height: 116,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.bezel,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: theme.lcdBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black54, width: 2),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: theme.lcdText,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Small reset button
          Positioned(
            top: 162,
            right: 34,
            child: MetalButton(size: 64, onTap: onReset, glow: theme.glowReset),
          ),
          // Big count button
          Positioned(
            bottom: 36,
            child: MetalButton(
              size: 250,
              onTap: onTap,
              glow: theme.glowCount,
              ridged: true,
            ),
          ),
        ],
      ),
    );
  }
}

class MetalButton extends StatefulWidget {
  final double size;
  final VoidCallback onTap;
  final Color glow; // neon colour shown while pressed
  final bool ridged; // brushed-metal look for the big button
  const MetalButton({
    super.key,
    required this.size,
    required this.onTap,
    required this.glow,
    this.ridged = false,
  });

  @override
  State<MetalButton> createState() => _MetalButtonState();
}

class _MetalButtonState extends State<MetalButton> {
  bool _down = false;
  bool _lit = false;
  Timer? _glowTimer;

  void _press() {
    _glowTimer?.cancel();
    setState(() {
      _down = true;
      _lit = true;
    });
  }

  void _release() {
    setState(() => _down = false);
    // keep the light on briefly so a quick tap still visibly flashes
    _glowTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  void dispose() {
    _glowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final ridged = widget.ridged;
    return GestureDetector(
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 60),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: s,
          height: s,
          padding: EdgeInsets.all(s * 0.05),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF5F5F5), Color(0xFF7A7A7A)],
            ),
            boxShadow: [
              const BoxShadow(
                color: Colors.black45,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
              if (_lit) ...[
                BoxShadow(
                  color: widget.glow,
                  blurRadius: s * 0.15,
                  spreadRadius: s * 0.03,
                ),
                BoxShadow(
                  color: widget.glow.withValues(alpha: 0.6),
                  blurRadius: s * 0.4,
                  spreadRadius: s * 0.08,
                ),
              ],
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ridged
                  ? const SweepGradient(
                      colors: [
                        Color(0xFFEDEDED),
                        Color(0xFF9A9A9A),
                        Color(0xFFF8F8F8),
                        Color(0xFF8A8A8A),
                        Color(0xFFEDEDED),
                        Color(0xFF9A9A9A),
                        Color(0xFFF8F8F8),
                        Color(0xFF8A8A8A),
                        Color(0xFFEDEDED),
                      ],
                    )
                  : const RadialGradient(
                      colors: [Color(0xFFF2F2F2), Color(0xFF9E9E9E)],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
