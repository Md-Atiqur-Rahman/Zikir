import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'theme.dart';

/// On/off switch for the "solve a sum to open the app" lock (on by default).
class AppLock {
  static final enabled = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool('appLock') ?? true;
  }

  static Future<void> set(bool value) async {
    enabled.value = value;
    (await SharedPreferences.getInstance()).setBool('appLock', value);
  }
}

/// A random, easy addition sum.
class MathQuestion {
  final List<int> terms;
  const MathQuestion(this.terms);

  int get answer => terms.fold(0, (a, b) => a + b);
  String get text => '${terms.join(' + ')} = ?';

  /// Always two single digits added together, like `4 + 6 = ?`.
  factory MathQuestion.random(Random r) =>
      MathQuestion([1 + r.nextInt(9), 1 + r.nextInt(9)]);
}

/// A sum with an on-screen number pad. A wrong answer clears the input and
/// shows a new sum, so guessing never gets easier.
class MathPad extends StatefulWidget {
  final VoidCallback onSolved;
  final Color color;
  final Random? random;
  const MathPad({
    super.key,
    required this.onSolved,
    required this.color,
    this.random,
  });

  @override
  State<MathPad> createState() => _MathPadState();
}

class _MathPadState extends State<MathPad> {
  late final Random _random = widget.random ?? Random();
  late MathQuestion _q = MathQuestion.random(_random);
  String _answer = '';
  bool _wrong = false;

  void _digit(int d) {
    if (_answer.length >= 4) return;
    setState(() {
      _answer += '$d';
      _wrong = false;
    });
  }

  void _back() {
    if (_answer.isEmpty) return;
    setState(() => _answer = _answer.substring(0, _answer.length - 1));
  }

  void _check() {
    if (_answer.isEmpty) return;
    if (int.tryParse(_answer) == _q.answer) {
      widget.onSolved();
      return;
    }
    final old = _q.text;
    MathQuestion next;
    do {
      next = MathQuestion.random(_random);
    } while (next.text == old);
    setState(() {
      _q = next;
      _answer = '';
      _wrong = true;
    });
  }

  Widget _key(Key key, Widget child, VoidCallback onTap) => SizedBox(
    width: 72,
    height: 56,
    child: FilledButton.tonal(
      key: key,
      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
      onPressed: onTap,
      child: child,
    ),
  );

  Widget _digitKey(int d) => _key(
    Key('pad-$d'),
    Text('$d', style: const TextStyle(fontSize: 22)),
    () => _digit(d),
  );

  @override
  Widget build(BuildContext context) {
    final fg = widget.color;
    final s = S.of(context);
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            keys[i],
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _q.text,
          key: const Key('math-question'),
          style: TextStyle(
            color: fg,
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 224,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _answer,
            key: const Key('math-answer'),
            style: TextStyle(
              color: fg,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 28,
          child: _wrong
              ? Center(
                  child: Text(
                    s.lockWrong,
                    key: const Key('math-wrong'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : null,
        ),
        row([_digitKey(1), _digitKey(2), _digitKey(3)]),
        row([_digitKey(4), _digitKey(5), _digitKey(6)]),
        row([_digitKey(7), _digitKey(8), _digitKey(9)]),
        row([
          _key(
            const Key('pad-back'),
            const Icon(Icons.backspace_outlined),
            _back,
          ),
          _digitKey(0),
          _key(const Key('pad-ok'), const Icon(Icons.check), _check),
        ]),
      ],
    );
  }
}

/// Full-screen lock shown over the app.
class LockScreen extends StatelessWidget {
  final VoidCallback onUnlocked;
  final Random? random;
  const LockScreen({super.key, required this.onUnlocked, this.random});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ZikirTheme>(
      valueListenable: themeController,
      builder: (context, t, _) => Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 52, color: t.onBackground),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).appName,
                    style: TextStyle(
                      color: t.onBackground,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    S.of(context).lockSolveToOpen,
                    style: TextStyle(
                      color: t.onBackground.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 20),
                  MathPad(
                    color: t.onBackground,
                    random: random,
                    onSolved: onUnlocked,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the whole app (including every page pushed on top) and covers it with
/// [LockScreen] when the app starts and after it was in the background for
/// [relockAfter].
class LockGate extends StatefulWidget {
  final Widget child;
  final Duration relockAfter;
  final DateTime Function()? now;
  final Random? random;
  const LockGate({
    super.key,
    required this.child,
    this.relockAfter = const Duration(minutes: 1),
    this.now,
    this.random,
  });

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked = AppLock.enabled.value;
  DateTime? _pausedAt;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = _now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null &&
          AppLock.enabled.value &&
          _now().difference(since) >= widget.relockAfter) {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            // swallow every touch so nothing underneath can be reached
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: LockScreen(
                random: widget.random,
                onUnlocked: () => setState(() => _locked = false),
              ),
            ),
          ),
      ],
    );
  }
}

/// Menu entry: turn the lock on or off. Turning it off needs a solved sum.
Future<void> showLockSettings(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LockSettings());

class _LockSettings extends StatefulWidget {
  const _LockSettings();

  @override
  State<_LockSettings> createState() => _LockSettingsState();
}

class _LockSettingsState extends State<_LockSettings> {
  Future<void> _change(bool on) async {
    if (on) {
      await AppLock.set(true);
    } else {
      final solved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(S.of(ctx).lockSolveToOff),
          // scrolls on short screens (landscape) instead of overflowing
          content: SingleChildScrollView(
            child: MathPad(
              color: Theme.of(ctx).colorScheme.onSurface,
              onSolved: () => Navigator.pop(ctx, true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of(ctx).cancel),
            ),
          ],
        ),
      );
      if (solved != true) return;
      await AppLock.set(false);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.lockTitle),
      content: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(s.lockSwitch),
        subtitle: Text(s.lockHint),
        value: AppLock.enabled.value,
        onChanged: _change,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.close),
        ),
      ],
    );
  }
}
