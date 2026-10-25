import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import 'db.dart';

void main() => runApp(const TasbihApp());

class TasbihApp extends StatelessWidget {
  const TasbihApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Zikir',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
        ),
        home: const CounterPage(),
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
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      setState(() {
        _count = p.getInt('count') ?? 0;
        _vibrate = p.getBool('vibrate') ?? true;
      });
    });
  }

  Future<void> _tap() async {
    setState(() => _count++);
    _prefs?.setInt('count', _count);
    if (_vibrate) {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 30);
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  void _toggleVibrate() {
    setState(() => _vibrate = !_vibrate);
    _prefs?.setBool('vibrate', _vibrate);
  }

  Future<void> _reset() async {
    if (_count == 0) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SaveDialog(count: _count),
    );
    if (saved == true) {
      setState(() => _count = 0);
      _prefs?.setInt('count', 0);
    }
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset without saving?'),
        content: Text('The count of $_count will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _count = 0);
      _prefs?.setInt('count', 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5AB0FF),
      appBar: AppBar(
        title: const Text('Zikir'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _vibrate ? 'Vibration on' : 'Vibration off',
            icon: Icon(_vibrate ? Icons.vibration : Icons.mobile_off),
            onPressed: _toggleVibrate,
          ),
          IconButton(
            tooltip: 'Summary',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SummaryPage())),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: _discard,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear without saving'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A finger-tally counter: blue body, LCD display, big metal button to count,
/// small metal button (top right) to reset & save.
class CounterDevice extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final VoidCallback onReset;
  const CounterDevice(
      {super.key, required this.count, required this.onTap, required this.onReset});

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
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E88E5), Color(0xFF0D47A1), Color(0xFF08306B)],
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 10)),
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
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFB9C1B4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black54, width: 2),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF1B1B1B),
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
            child: MetalButton(size: 44, onTap: onReset),
          ),
          // Big count button
          Positioned(
            bottom: 50,
            child: MetalButton(size: 200, onTap: onTap, ridged: true),
          ),
        ],
      ),
    );
  }
}

class MetalButton extends StatefulWidget {
  final double size;
  final VoidCallback onTap;
  final bool ridged;
  const MetalButton({super.key, required this.size, required this.onTap, this.ridged = false});

  @override
  State<MetalButton> createState() => _MetalButtonState();
}

class _MetalButtonState extends State<MetalButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 60),
        child: Container(
          width: s,
          height: s,
          padding: EdgeInsets.all(s * 0.05),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF5F5F5), Color(0xFF7A7A7A)],
            ),
            boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.ridged
                  ? const SweepGradient(colors: [
                      Color(0xFFEDEDED),
                      Color(0xFF9A9A9A),
                      Color(0xFFF8F8F8),
                      Color(0xFF8A8A8A),
                      Color(0xFFEDEDED),
                      Color(0xFF9A9A9A),
                      Color(0xFFF8F8F8),
                      Color(0xFF8A8A8A),
                      Color(0xFFEDEDED),
                    ])
                  : const RadialGradient(
                      colors: [Color(0xFFF2F2F2), Color(0xFF9E9E9E)]),
            ),
          ),
        ),
      ),
    );
  }
}

class SaveDialog extends StatefulWidget {
  final int count;
  const SaveDialog({super.key, required this.count});

  @override
  State<SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<SaveDialog> {
  static const _newKey = -1;
  List<Category> _cats = [];
  int? _selected;
  final _name = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await Db.categories();
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('lastCategory');
    setState(() {
      _cats = cats;
      _selected = cats.any((c) => c.id == last)
          ? last
          : (cats.isEmpty ? _newKey : cats.first.id);
      _loading = false;
    });
  }

  Future<void> _save() async {
    int id;
    if (_selected == _newKey) {
      final name = _name.text.trim();
      if (name.isEmpty) return;
      final existing = _cats.where((c) => c.name.toLowerCase() == name.toLowerCase());
      id = existing.isNotEmpty ? existing.first.id : await Db.addCategory(name);
    } else {
      id = _selected!;
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await Db.saveCount(id, today, widget.count);
    (await SharedPreferences.getInstance()).setInt('lastCategory', id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Save ${widget.count} to...'),
      content: _loading
          ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    ..._cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                    const DropdownMenuItem(value: _newKey, child: Text('+ New category')),
                  ],
                  onChanged: (v) => setState(() => _selected = v),
                ),
                if (_selected == _newKey)
                  TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'New category name'),
                  ),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _loading ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

String _fmt(int n) => NumberFormat.decimalPattern().format(n);

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  List<Category> _cats = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await Db.categories();
    final total = await Db.grandTotal();
    setState(() {
      _cats = cats;
      _total = total;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Summary')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Text('Total DHIKRS = ${_fmt(_total)}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _cats.isEmpty
                ? const Center(child: Text('No categories yet. Count and reset to save.'))
                : ListView(
                    children: _cats
                        .map((c) => ListTile(
                              title: Text(c.name),
                              trailing: Text(_fmt(c.total),
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold)),
                              onTap: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CategoryPage(category: c)));
                                _load();
                              },
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class CategoryPage extends StatefulWidget {
  final Category category;
  const CategoryPage({super.key, required this.category});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List<DayCount> _days = [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await Db.days(widget.category.id);
    final total = await Db.categoryTotal(widget.category.id);
    setState(() {
      _days = days;
      _total = total;
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${widget.category.name}?'),
        content: const Text('All saved counts in this category will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await Db.deleteCategory(widget.category.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.category.name;
    final items = <Widget>[];
    String? month;
    int monthSum = 0;
    // Group by month; days are newest first.
    final byMonth = <String, List<DayCount>>{};
    for (final d in _days) {
      byMonth.putIfAbsent(d.date.substring(0, 7), () => []).add(d);
    }
    for (final entry in byMonth.entries) {
      month = entry.key;
      monthSum = entry.value.fold(0, (s, d) => s + d.count);
      final label = DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));
      items.add(Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Total ${_fmt(monthSum)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ));
      for (final d in entry.value) {
        final date = DateFormat('d MMM').format(DateTime.parse(d.date));
        items.add(ListTile(
          dense: true,
          title: Text('$name  $date'),
          trailing: Text('total count ${_fmt(d.count)}'),
        ));
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Total $name count = ${_fmt(_total)}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (items.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16), child: Text('No entries in the last 6 months.')),
          ...items,
        ],
      ),
    );
  }
}
