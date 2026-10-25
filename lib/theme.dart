import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every colour the counter screen uses, in the order of [ZikirTheme.labels].
class ZikirTheme {
  final String name;
  final List<Color> colors;
  const ZikirTheme(this.name, this.colors);

  static const labels = [
    'Background',
    'Body (light)',
    'Body (middle)',
    'Body (dark)',
    'Display frame',
    'Display background',
    'Display digits',
    'Count button glow',
    'Reset button glow',
  ];

  Color get background => colors[0];
  Color get bodyA => colors[1];
  Color get bodyB => colors[2];
  Color get bodyC => colors[3];
  Color get bezel => colors[4];
  Color get lcdBg => colors[5];
  Color get lcdText => colors[6];
  Color get glowCount => colors[7];
  Color get glowReset => colors[8];

  /// Very dark backgrounds switch the other pages to Material's dark mode too.
  bool get dark => background.computeLuminance() < 0.2;

  /// Text on the counter screen: white on mid/dark backgrounds, near-black on light ones.
  Color get onBackground => background.computeLuminance() < 0.5
      ? Colors.white
      : const Color(0xFF1B1B1B);

  ZikirTheme withColor(int index, Color c) {
    final next = [...colors]..[index] = c;
    return ZikirTheme('Custom', next);
  }

  bool sameAs(ZikirTheme o) {
    if (name != o.name) return false;
    for (var i = 0; i < colors.length; i++) {
      if (colors[i].toARGB32() != o.colors[i].toARGB32()) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'colors': colors.map((c) => c.toARGB32()).toList(),
  };

  static ZikirTheme? fromJson(Map<String, dynamic> j) {
    final list = (j['colors'] as List?)?.cast<int>();
    if (list == null || list.length != labels.length) return null;
    return ZikirTheme(j['name'] as String, list.map(Color.new).toList());
  }

  static const presets = <ZikirTheme>[
    ZikirTheme('Classic Blue', [
      Color(0xFF5AB0FF),
      Color(0xFF1E88E5),
      Color(0xFF0D47A1),
      Color(0xFF08306B),
      Color(0xFF111111),
      Color(0xFFB9C1B4),
      Color(0xFF1B1B1B),
      Color(0xFFA6FF00),
      Color(0xFFDC143C),
    ]),
    ZikirTheme('Emerald', [
      Color(0xFF81C784),
      Color(0xFF43A047),
      Color(0xFF1B5E20),
      Color(0xFF0B3D12),
      Color(0xFF0D1F0F),
      Color(0xFFC5D8B0),
      Color(0xFF1B2A1B),
      Color(0xFFA6FF00),
      Color(0xFFDC143C),
    ]),
    ZikirTheme('Midnight', [
      Color(0xFF0B1220),
      Color(0xFF455A64),
      Color(0xFF263238),
      Color(0xFF101A1F),
      Color(0xFF000000),
      Color(0xFF0F2A2E),
      Color(0xFF4DFFEA),
      Color(0xFF00E5FF),
      Color(0xFFFF1744),
    ]),
    ZikirTheme('Royal Purple', [
      Color(0xFFB39DDB),
      Color(0xFF7E57C2),
      Color(0xFF512DA8),
      Color(0xFF311B92),
      Color(0xFF140A33),
      Color(0xFFD1C4E9),
      Color(0xFF1A1033),
      Color(0xFFA6FF00),
      Color(0xFFDC143C),
    ]),
    ZikirTheme('Golden Sand', [
      Color(0xFFF5E6C8),
      Color(0xFFD4A017),
      Color(0xFFB8860B),
      Color(0xFF7A5C00),
      Color(0xFF2B2100),
      Color(0xFFE8E0C0),
      Color(0xFF3A2E00),
      Color(0xFF76FF03),
      Color(0xFFD50000),
    ]),
    ZikirTheme('Rose', [
      Color(0xFFF8BBD0),
      Color(0xFFEC407A),
      Color(0xFFC2185B),
      Color(0xFF880E4F),
      Color(0xFF2A0A16),
      Color(0xFFF3E5E8),
      Color(0xFF3A0F1F),
      Color(0xFFA6FF00),
      Color(0xFFDC143C),
    ]),
  ];
}

class ThemeController extends ValueNotifier<ZikirTheme> {
  ThemeController() : super(ZikirTheme.presets.first);

  Future<void> load() async {
    final s = (await SharedPreferences.getInstance()).getString('theme');
    if (s == null) return;
    try {
      final t = ZikirTheme.fromJson(jsonDecode(s) as Map<String, dynamic>);
      if (t != null) value = t;
    } catch (_) {
      // keep the default theme if the saved one is unreadable
    }
  }

  Future<void> set(ZikirTheme t) async {
    value = t;
    (await SharedPreferences.getInstance()).setString(
      'theme',
      jsonEncode(t.toJson()),
    );
  }
}

final themeController = ThemeController();

String _hex(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  Future<void> _edit(BuildContext context, ZikirTheme t, int i) async {
    final c = await showDialog<Color>(
      context: context,
      builder: (_) =>
          _ColorDialog(title: ZikirTheme.labels[i], initial: t.colors[i]),
    );
    if (c != null) themeController.set(t.withColor(i, c));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ZikirTheme>(
      valueListenable: themeController,
      builder: (context, t, _) => Scaffold(
        appBar: AppBar(title: const Text('Theme')),
        body: ListView(
          children: [
            const _Header('Ready-made themes'),
            for (final p in ZikirTheme.presets)
              ListTile(
                leading: _Swatches([
                  p.background,
                  p.bodyB,
                  p.lcdBg,
                  p.glowCount,
                ]),
                title: Text(p.name),
                trailing: t.sameAs(p) ? const Icon(Icons.check_circle) : null,
                onTap: () => themeController.set(p),
              ),
            _Header('Make your own  (now: ${t.name})'),
            for (var i = 0; i < ZikirTheme.labels.length; i++)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.colors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey, width: 1),
                  ),
                ),
                title: Text(ZikirTheme.labels[i]),
                trailing: Text('#${_hex(t.colors[i])}'),
                onTap: () => _edit(context, t, i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _Swatches extends StatelessWidget {
  final List<Color> colors;
  const _Swatches(this.colors);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in colors)
        Container(
          width: 18,
          height: 36,
          decoration: BoxDecoration(
            color: c,
            border: Border.all(color: Colors.black12),
          ),
        ),
    ],
  );
}

class _ColorDialog extends StatefulWidget {
  final String title;
  final Color initial;
  const _ColorDialog({required this.title, required this.initial});

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  static const _quick = [
    0xFFA6FF00,
    0xFFDC143C,
    0xFF00E5FF,
    0xFFFF1744,
    0xFFFFD600,
    0xFFFF6D00,
    0xFFE040FB,
    0xFF2979FF,
    0xFFFFFFFF,
    0xFFB0BEC5,
    0xFF37474F,
    0xFF000000,
  ];

  late int _r = (widget.initial.r * 255).round();
  late int _g = (widget.initial.g * 255).round();
  late int _b = (widget.initial.b * 255).round();
  late final _hexCtl = TextEditingController(text: _hex(_color));

  Color get _color => Color.fromARGB(255, _r, _g, _b);

  void _set(int r, int g, int b) {
    setState(() {
      _r = r;
      _g = g;
      _b = b;
      _hexCtl.text = _hex(_color);
    });
  }

  Widget _slider(
    String label,
    int value,
    Color tint,
    void Function(int) onChanged,
  ) => Row(
    children: [
      SizedBox(width: 16, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          activeColor: tint,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey),
              ),
            ),
            _slider('R', _r, Colors.red, (v) => _set(v, _g, _b)),
            _slider('G', _g, Colors.green, (v) => _set(_r, v, _b)),
            _slider('B', _b, Colors.blue, (v) => _set(_r, _g, v)),
            TextField(
              controller: _hexCtl,
              maxLength: 6,
              decoration: const InputDecoration(
                prefixText: '#',
                labelText: 'Hex',
                counterText: '',
              ),
              onChanged: (s) {
                final v = int.tryParse(s, radix: 16);
                if (s.length == 6 && v != null) {
                  setState(() {
                    _r = (v >> 16) & 0xFF;
                    _g = (v >> 8) & 0xFF;
                    _b = v & 0xFF;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _quick)
                  GestureDetector(
                    onTap: () =>
                        _set((q >> 16) & 0xFF, (q >> 8) & 0xFF, q & 0xFF),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(q),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Select'),
        ),
      ],
    );
  }
}
