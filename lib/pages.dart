import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db.dart';

String fmt(int n) => NumberFormat.decimalPattern().format(n);

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
            child: Text('Total DHIKRS = ${fmt(_total)}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              children: _cats
                  .map((c) => ListTile(
                        title: Text(c.name),
                        trailing: Text(fmt(c.total),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        onTap: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => CategoryPage(category: c)));
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
  List<DayEntry> _entries = [];
  Map<String, int> _prayerOrder = {};
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await Db.days(widget.category.id);
    final total = await Db.categoryTotal(widget.category.id);
    final prayers = await Db.prayers();
    setState(() {
      _entries = entries;
      _total = total;
      _prayerOrder = {for (final p in prayers) p.name: p.ord};
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
    final theme = Theme.of(context);

    // month -> date -> entries (entries arrive newest day first)
    final byMonth = <String, Map<String, List<DayEntry>>>{};
    for (final e in _entries) {
      byMonth.putIfAbsent(e.date.substring(0, 7), () => {}).putIfAbsent(e.date, () => []).add(e);
    }

    final items = <Widget>[];
    for (final month in byMonth.entries) {
      final monthSum = month.value.values.expand((l) => l).fold(0, (s, e) => s + e.count);
      items.add(Container(
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('MMMM yyyy').format(DateTime.parse('${month.key}-01')),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Total ${fmt(monthSum)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ));
      for (final day in month.value.entries) {
        final dayEntries = [...day.value]..sort((a, b) =>
            (_prayerOrder[a.prayer] ?? 99).compareTo(_prayerOrder[b.prayer] ?? 99));
        final dayTotal = dayEntries.fold(0, (s, e) => s + e.count);
        items.add(ListTile(
          dense: true,
          title: Text('$name  ${DateFormat('d MMM').format(DateTime.parse(day.key))}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Text('total count ${fmt(dayTotal)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ));
        for (final e in dayEntries.where((e) => e.prayer.isNotEmpty)) {
          items.add(Padding(
            padding: const EdgeInsets.only(left: 32, right: 16, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(e.prayer), Text(fmt(e.count))],
            ),
          ));
        }
        items.add(const SizedBox(height: 6));
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
            child: Text('Total $name count = ${fmt(_total)}',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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

/// Reorder (drag), add, edit and delete the zikir queue.
class ZikirListPage extends StatefulWidget {
  const ZikirListPage({super.key});

  @override
  State<ZikirListPage> createState() => _ZikirListPageState();
}

class _ZikirListPageState extends State<ZikirListPage> {
  List<Category> _cats = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await Db.categories();
    setState(() => _cats = cats);
  }

  Future<void> _edit([Category? c]) async {
    final name = TextEditingController(text: c?.name);
    final target = TextEditingController(text: c?.target);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'Add zikir' : 'Edit zikir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: target,
              decoration: const InputDecoration(
                  labelText: 'Suggested count (optional)', hintText: 'e.g. 100 or 1-100'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      if (c == null) {
        await Db.addCategory(name.text, target: target.text);
      } else {
        await Db.updateCategory(c.id, name.text, target.text);
      }
      _load();
    }
  }

  Future<void> _delete(Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text('All saved counts in this category will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await Db.deleteCategory(c.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('জিকিরের তালিকা'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _edit)],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
                'Drag to set the order. After you reset, the next zikir in this list is selected.'),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _cats.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() => _cats.insert(newIndex, _cats.removeAt(oldIndex)));
                Db.reorder(_cats.map((c) => c.id).toList());
              },
              itemBuilder: (ctx, i) {
                final c = _cats[i];
                return ListTile(
                  key: ValueKey(c.id),
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(c.name),
                  subtitle: c.target.isEmpty ? null : Text('সংখ্যা: ${c.target}'),
                  onTap: () => _edit(c),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)),
                      ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                              padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Time windows used to tag each saved count with a prayer name.
class PrayerTimesPage extends StatefulWidget {
  const PrayerTimesPage({super.key});

  @override
  State<PrayerTimesPage> createState() => _PrayerTimesPageState();
}

class _PrayerTimesPageState extends State<PrayerTimesPage> {
  List<Prayer> _prayers = [];

  @override
  void initState() {
    super.initState();
    Db.prayers().then((p) => setState(() => _prayers = p));
  }

  String _label(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  Future<void> _pick(Prayer p, {required bool start}) async {
    final cur = start ? p.startMin : p.endMin;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    if (start) {
      p.startMin = m;
    } else {
      p.endMin = m;
    }
    await Db.updatePrayer(p);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('নামাজের সময়সূচী')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('A count is tagged with the prayer whose window contains the time you '
                'started counting. A window can cross midnight (e.g. Isha 7:30 PM → 2:00 AM). '
                'Times outside every window are saved without a prayer name.'),
          ),
          for (final p in _prayers)
            ListTile(
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Row(
                children: [
                  TextButton(
                      onPressed: () => _pick(p, start: true), child: Text(_label(p.startMin))),
                  const Text('→'),
                  TextButton(
                      onPressed: () => _pick(p, start: false), child: Text(_label(p.endMin))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
