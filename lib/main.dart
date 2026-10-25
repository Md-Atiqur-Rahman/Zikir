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

class _CounterPageState extends State<CounterPage> {
  int _count = 0;
  bool _vibrate = true;
  bool _sound = true;
  SharedPreferences? _prefs;
  List<Category> _cats = [];
  List<Prayer> _prayers = [];
  int? _currentId;
  DateTime? _start; // when the running count began; decides date and prayer

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
    });
    await _reload();
  }

  Future<void> _reload() async {
    final cats = await Db.categories();
    final prayers = await Db.prayers();
    if (mounted) {
      setState(() {
        _cats = cats;
        _prayers = prayers;
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

  Future<void> _vibrateFor(int ms) async {
    if (!_vibrate) return;
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: ms);
    } else {
      HapticFeedback.lightImpact();
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
      _vibrateFor(150);
    } else {
      _vibrateFor(30);
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
    });
    _prefs?.setInt('count', 0);
    _prefs?.remove('start');
  }

  /// Saves the running count into [cat] under the prayer window it started in,
  /// then moves on to the next zikir in the list.
  Future<void> _commit(Category cat) async {
    final start = _start ?? DateTime.now();
    final prayer = prayerAt(_prayers, start);
    final saved = _count;
    await Db.saveCount(
      cat.id,
      DateFormat('yyyy-MM-dd').format(start),
      prayer,
      saved,
    );
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
    final prayer = prayerAt(_prayers, _start ?? DateTime.now());
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
              onSelected: (v) => _open(switch (v) {
                0 => const ZikirListPage(),
                1 => const PrayerTimesPage(),
                2 => const ThemePage(),
                _ => const SoundPage(),
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('জিকিরের তালিকা')),
                PopupMenuItem(value: 1, child: Text('নামাজের সময়সূচী')),
                PopupMenuItem(value: 2, child: Text('Theme')),
                PopupMenuItem(value: 3, child: Text('Sounds')),
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
                prayer: prayer,
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
              Text(
                'Small button: save & next  •  tap the zikir name to change it',
                style: TextStyle(color: t.onBackground, fontSize: 12),
              ),
              TextButton.icon(
                onPressed: _count == 0 ? null : _discard,
                style: TextButton.styleFrom(foregroundColor: t.onBackground),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear without saving'),
              ),
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
  final String prayer;
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
    required this.prayer,
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
                  if (prayer.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.access_time, size: 16),
                      label: Text(prayer),
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
      width: 320,
      height: 460,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Body
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(110),
                topRight: Radius.circular(110),
                bottomLeft: Radius.circular(150),
                bottomRight: Radius.circular(150),
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
            top: 40,
            left: 28,
            right: 28,
            child: Container(
              height: 120,
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
            top: 190,
            right: 40,
            child: MetalButton(size: 44, onTap: onReset, glow: theme.glowReset),
          ),
          // Big count button
          Positioned(
            bottom: 50,
            child: MetalButton(
              size: 200,
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
