import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      appBar: AppBar(
        title: const Text('Summary'),
        actions: [
          IconButton(
            tooltip: 'Day-wise',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DayPage(date: DateTime.now())),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Total zikir = ${fmt(_total)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView(
              children: _cats
                  .map(
                    (c) => ListTile(
                      title: Text(c.name),
                      trailing: Text(
                        fmt(c.total),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CategoryPage(category: c),
                          ),
                        );
                        _load();
                      },
                    ),
                  )
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
        content: const Text(
          'All saved counts in this category will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
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
      byMonth
          .putIfAbsent(e.date.substring(0, 7), () => {})
          .putIfAbsent(e.date, () => [])
          .add(e);
    }

    final items = <Widget>[];
    for (final month in byMonth.entries) {
      final monthSum = month.value.values
          .expand((l) => l)
          .fold(0, (s, e) => s + e.count);
      items.add(
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy')
                    .format(DateTime.parse('${month.key}-01')),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Total ${fmt(monthSum)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
      for (final day in month.value.entries) {
        final dayEntries = [...day.value]
          ..sort(
            (a, b) => (_prayerOrder[a.prayer] ?? 99).compareTo(
              _prayerOrder[b.prayer] ?? 99,
            ),
          );
        final dayTotal = dayEntries.fold(0, (s, e) => s + e.count);
        items.add(
          ListTile(
            dense: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DayPage(date: DateTime.parse(day.key)),
              ),
            ),
            title: Text(
              '$name  ${DateFormat('d MMM').format(DateTime.parse(day.key))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Text(
              'total count ${fmt(dayTotal)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        );
        for (final e in dayEntries.where((e) => e.prayer.isNotEmpty)) {
          items.add(
            Padding(
              padding: const EdgeInsets.only(left: 32, right: 16, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(e.prayer), Text(fmt(e.count))],
              ),
            ),
          );
        }
        items.add(const SizedBox(height: 6));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Total $name count = ${fmt(_total)}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No entries in the last 6 months.'),
            ),
          ...items,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String value;
  const _SectionHeader(this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (value.isNotEmpty)
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Everything saved on one day, with arrows and a calendar to move between days.
class DayPage extends StatefulWidget {
  final DateTime date;
  const DayPage({super.key, required this.date});

  @override
  State<DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<DayPage> {
  late DateTime _date = DateUtils.dateOnly(widget.date);
  List<DayRow> _rows = [];
  Map<String, int> _prayerOrder = {};
  bool _loaded = false;

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _oldest => _today.subtract(const Duration(days: 365));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await Db.dayRows(ymd(_date));
    final prayers = await Db.prayers();
    setState(() {
      _rows = rows;
      _prayerOrder = {for (final p in prayers) p.name: p.ord};
      _loaded = true;
    });
  }

  void _go(DateTime d) {
    _date = d;
    _load();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _oldest,
      lastDate: _today,
    );
    if (d != null) _go(DateUtils.dateOnly(d));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _rows.fold(0, (s, r) => s + r.count);

    // all-day rows per zikir, in queue order
    final byZikir = <int, List<DayRow>>{};
    for (final r in _rows) {
      byZikir.putIfAbsent(r.categoryId, () => []).add(r);
    }

    // rows per prayer time, in the order of the day
    final byPrayer = <String, List<DayRow>>{};
    for (final r in _rows) {
      byPrayer.putIfAbsent(r.prayer, () => []).add(r);
    }
    final prayerNames = byPrayer.keys.toList()
      ..sort(
        (a, b) => (_prayerOrder[a] ?? 99).compareTo(_prayerOrder[b] ?? 99),
      );
    final onlyUnnamed = prayerNames.length == 1 && prayerNames.first.isEmpty;

    Widget line(String name, int count) => ListTile(
      dense: true,
      title: Text(name),
      trailing: Text(
        fmt(count),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );

    final items = <Widget>[];
    if (!onlyUnnamed) {
      for (final name in prayerNames) {
        final rows = byPrayer[name]!;
        items.add(
          _SectionHeader(
            name.isEmpty ? 'অন্য সময় (no prayer)' : name,
            fmt(rows.fold(0, (s, r) => s + r.count)),
          ),
        );
        for (final r in rows) {
          items.add(line(r.name, r.count));
        }
      }
    }
    if (_rows.isNotEmpty) {
      items.add(_SectionHeader('সারাদিনের মোট (Day total)', fmt(total)));
      for (final rows in byZikir.values) {
        items.add(line(rows.first.name, rows.fold(0, (s, r) => s + r.count)));
      }
      items.add(const SizedBox(height: 16));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Day-wise')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _date.isAfter(_oldest)
                      ? () => _go(_date.subtract(const Duration(days: 1)))
                      : null,
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.calendar_month),
                    label: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _date.isBefore(_today)
                      ? () => _go(_date.add(const Duration(days: 1)))
                      : null,
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Total = ${fmt(total)}   (${byZikir.length} zikir)',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: !_loaded
                ? const SizedBox.shrink()
                : items.isEmpty
                ? const Center(child: Text('Nothing saved on this day.'))
                : ListView(children: items),
          ),
        ],
      ),
    );
  }
}

/// First day of the week containing [d]; weeks start on Saturday.
DateTime weekStart(DateTime d) =>
    DateUtils.dateOnly(d).subtract(Duration(days: (d.weekday + 1) % 7));

/// A row with a title, a total and a bar showing it against the largest row.
class _BarTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int value;
  final int max;
  final VoidCallback? onTap;
  const _BarTile({
    required this.title,
    required this.value,
    required this.max,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: max == 0 ? 0 : value / max,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                fmt(value),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: onTap == null ? Colors.transparent : cs.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  final String text;
  const _TotalHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// All total: every month with its count. Tap a month for its weeks.
class MonthsPage extends StatefulWidget {
  const MonthsPage({super.key});

  @override
  State<MonthsPage> createState() => _MonthsPageState();
}

class _MonthsPageState extends State<MonthsPage> {
  List<(String, int)> _months = [];
  int _total = 0;
  int _week = 0;
  int _month = 0;
  String? _lastDate;
  int _lastTotal = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = ymd(now);
    final months = await Db.monthTotals();
    final total = await Db.grandTotal();
    final week = await Db.rangeTotal(ymd(weekStart(now)), today);
    final month = await Db.rangeTotal(
      ymd(DateTime(now.year, now.month, 1)),
      today,
    );
    final lastDate = await Db.lastDayBefore(today);
    final lastTotal = lastDate == null ? 0 : await Db.dayTotal(lastDate);
    setState(() {
      _months = months;
      _total = total;
      _week = week;
      _month = month;
      _lastDate = lastDate;
      _lastTotal = lastTotal;
      _loaded = true;
    });
  }

  Widget _mini(String label, int value, {VoidCallback? onTap}) => Expanded(
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                fmt(value),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final maxValue = _months.fold(0, (m, e) => e.$2 > m ? e.$2 : m);
    final last = _lastDate == null ? null : DateTime.parse(_lastDate!);
    return Scaffold(
      appBar: AppBar(title: const Text('All total')),
      body: ListView(
        children: [
          _TotalHeader('Total zikir = ${fmt(_total)}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _mini(
                  last == null
                      ? 'Last day'
                      : 'Last day · ${DateFormat('d MMM').format(last)}',
                  _lastTotal,
                  onTap: last == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DayPage(date: last),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                _mini('This week', _week),
                const SizedBox(width: 8),
                _mini('This month', _month),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
            child: Text(
              'Month-wise  (tap a month for its weeks)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          if (_loaded && _months.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nothing saved yet.'),
            ),
          for (final m in _months)
            _BarTile(
              title: DateFormat('MMMM yyyy')
                  .format(DateTime.parse('${m.$1}-01')),
              value: m.$2,
              max: maxValue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => WeeksPage(month: m.$1)),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// One month split into weeks (Saturday to Friday, clipped to the month).
class WeeksPage extends StatefulWidget {
  final String month; // 'yyyy-MM'
  const WeeksPage({super.key, required this.month});

  @override
  State<WeeksPage> createState() => _WeeksPageState();
}

class _Week {
  final DateTime from;
  final DateTime to;
  int total = 0;
  _Week(this.from, this.to);
}

class _WeeksPageState extends State<WeeksPage> {
  List<_Week> _weeks = [];
  int _total = 0;

  late final DateTime _first = DateTime.parse('${widget.month}-01');
  // the current month stops at today instead of listing days that haven't happened
  late final DateTime _last = () {
    final end = DateTime(_first.year, _first.month + 1, 0);
    final today = DateUtils.dateOnly(DateTime.now());
    return end.isAfter(today) ? today : end;
  }();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final daily = await Db.dailyTotals(ymd(_first), ymd(_last));
    final weeks = <_Week>[];
    var start = _first;
    while (!start.isAfter(_last)) {
      var end = weekStart(start).add(const Duration(days: 6));
      if (end.isAfter(_last)) end = _last;
      final w = _Week(start, end);
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        w.total += daily[ymd(d)] ?? 0;
      }
      weeks.add(w);
      start = end.add(const Duration(days: 1));
    }
    setState(() {
      _weeks = weeks;
      _total = daily.values.fold(0, (a, b) => a + b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = _weeks.fold(0, (m, w) => w.total > m ? w.total : m);
    final f = DateFormat('d MMM');
    final numbered = [
      for (var i = 0; i < _weeks.length; i++) (i + 1, _weeks[i]),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(DateFormat('MMMM yyyy').format(_first))),
      body: ListView(
        children: [
          _TotalHeader('Month total = ${fmt(_total)}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Text(
              'Week-wise  (tap a week for its days)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          for (final (n, w) in numbered.reversed)
            _BarTile(
              title: 'Week $n',
              subtitle: '${f.format(w.from)} – ${f.format(w.to)}',
              value: w.total,
              max: maxValue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DaysListPage(title: 'Week $n', from: w.from, to: w.to),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// The days of one week with their counts; tap a day for its zikirs.
class DaysListPage extends StatefulWidget {
  final String title;
  final DateTime from;
  final DateTime to;
  const DaysListPage({
    super.key,
    required this.title,
    required this.from,
    required this.to,
  });

  @override
  State<DaysListPage> createState() => _DaysListPageState();
}

class _DaysListPageState extends State<DaysListPage> {
  Map<String, int> _daily = {};

  @override
  void initState() {
    super.initState();
    Db.dailyTotals(
      ymd(widget.from),
      ymd(widget.to),
    ).then((d) => setState(() => _daily = d));
  }

  @override
  Widget build(BuildContext context) {
    final days = <DateTime>[];
    for (
      var d = widget.to;
      !d.isBefore(widget.from);
      d = d.subtract(const Duration(days: 1))
    ) {
      days.add(d);
    }
    final maxValue = _daily.values.fold(0, (m, v) => v > m ? v : m);
    final total = _daily.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        children: [
          _TotalHeader('Week total = ${fmt(total)}'),
          for (final d in days)
            _BarTile(
              title: DateFormat('EEEE').format(d),
              subtitle: DateFormat('d MMM yyyy').format(d),
              value: _daily[ymd(d)] ?? 0,
              max: maxValue,
              onTap: (_daily[ymd(d)] ?? 0) == 0
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DayPage(date: d)),
                    ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Backfill history: add the same per-day counts to every day of a date range.
class BulkImportPage extends StatefulWidget {
  const BulkImportPage({super.key});

  @override
  State<BulkImportPage> createState() => _BulkImportPageState();
}

class _BulkImportPageState extends State<BulkImportPage> {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late DateTime _from = () {
    final sep20 = DateTime(_today.year, 9, 20);
    return sep20.isAfter(_today) ? DateTime(_today.year - 1, 9, 20) : sep20;
  }();
  late DateTime _to = _today;
  List<Category> _cats = [];
  List<Prayer> _prayers = [];
  final _ctl = <int, TextEditingController>{};
  final _on = <int, bool>{};
  String _prayer = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await Db.categories();
    final prayers = await Db.prayers();
    for (final c in cats) {
      final n = defaultBulkCount(c.name);
      _ctl[c.id] = TextEditingController(text: n > 0 ? '$n' : '');
      _on[c.id] = n > 0;
    }
    setState(() {
      _cats = cats;
      _prayers = prayers;
    });
  }

  int get _days =>
      DateTime.utc(
        _to.year,
        _to.month,
        _to.day,
      ).difference(DateTime.utc(_from.year, _from.month, _from.day)).inDays +
      1;

  Map<int, int> get _counts => {
    for (final c in _cats)
      if (_on[c.id] == true && (int.tryParse(_ctl[c.id]!.text) ?? 0) > 0)
        c.id: int.parse(_ctl[c.id]!.text),
  };

  Future<void> _pickDate({required bool from}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = DateUtils.dateOnly(d);
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = DateUtils.dateOnly(d);
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _import() async {
    final counts = _counts;
    final perDay = counts.values.fold(0, (a, b) => a + b);
    final total = perDay * _days;
    final f = DateFormat('d MMM yyyy');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to history?'),
        content: Text(
          '${counts.length} zikirs \u00d7 $_days days '
          '(${f.format(_from)} \u2013 ${f.format(_to)})\n'
          'Total to add: ${fmt(total)}\n\n'
          'This is added on top of anything already saved on those days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await Db.bulkAdd(_from, _to, counts, _prayer);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${fmt(total)} to the history')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final perDay = counts.values.fold(0, (a, b) => a + b);
    final f = DateFormat('d MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk import')),
      body: _cats.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Every selected zikir gets its count on every day of the range.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(from: true),
                          icon: const Icon(Icons.event),
                          label: Text('From  ${f.format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(from: false),
                          icon: const Icon(Icons.event),
                          label: Text('To  ${f.format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: DropdownButtonFormField<String>(
                    initialValue: _prayer,
                    decoration: const InputDecoration(
                      labelText: 'Save under prayer time',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('None')),
                      for (final p in _prayers)
                        DropdownMenuItem(value: p.name, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _prayer = v ?? ''),
                  ),
                ),
                const _SectionHeader('Zikir  \u2013  count per day', ''),
                for (final c in _cats)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 4, right: 16),
                    leading: Checkbox(
                      value: _on[c.id],
                      onChanged: (v) => setState(() => _on[c.id] = v ?? false),
                    ),
                    title: Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: SizedBox(
                      width: 84,
                      child: TextField(
                        controller: _ctl[c.id],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {
                          if ((int.tryParse(v) ?? 0) > 0) _on[c.id] = true;
                        }),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${counts.length} zikirs \u00d7 $_days days\n'
                  'Total ${fmt(perDay * _days)}',
                ),
              ),
              FilledButton.icon(
                onPressed: (_saving || counts.isEmpty) ? null : _import,
                icon: const Icon(Icons.playlist_add),
                label: const Text('Add to history'),
              ),
            ],
          ),
        ),
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
    final goal = TextEditingController(
      text: (c?.goal ?? 0) > 0 ? '${c!.goal}' : '',
    );
    final beep = TextEditingController(
      text: (c?.beepEvery ?? 0) > 0 ? '${c!.beepEvery}' : '',
    );
    final meaning = TextEditingController(text: c?.meaning);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c == null ? 'Add zikir' : 'Edit zikir'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: meaning,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'অর্থ (meaning)',
                  hintText: 'Shown under the zikir on the counter',
                ),
              ),
              TextField(
                controller: goal,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Target count (optional)',
                  hintText: 'e.g. 100',
                  helperText: 'Beep + long vibration when you reach it',
                ),
              ),
              TextField(
                controller: beep,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Beep every (optional)',
                  hintText: 'e.g. 20',
                  helperText: 'A short beep after every N counts',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final g = int.tryParse(goal.text) ?? 0;
      final b = int.tryParse(beep.text) ?? 0;
      if (c == null) {
        await Db.addCategory(
          name.text,
          target: g > 0 ? '$g' : '',
          meaning: meaning.text,
          goal: g,
          beepEvery: b,
        );
      } else {
        // keep a non-numeric note like "1-100" when no numeric goal is set
        final note = int.tryParse(c.target) == null ? c.target : '';
        await Db.updateCategory(
          c.id,
          name.text,
          g > 0 ? '$g' : note,
          meaning.text,
          g,
          b,
        );
      }
      _load();
    }
  }

  Future<void> _delete(Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'All saved counts in this category will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
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
              'Drag to set the order. After you reset, the next zikir in this list is selected.',
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _cats.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(
                  () => _cats.insert(newIndex, _cats.removeAt(oldIndex)),
                );
                Db.reorder(_cats.map((c) => c.id).toList());
              },
              itemBuilder: (ctx, i) {
                final c = _cats[i];
                return ListTile(
                  key: ValueKey(c.id),
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(c.name),
                  subtitle: (c.meaning.isEmpty && c.targetLabel.isEmpty)
                      ? null
                      : Text(
                          [
                            if (c.meaning.isNotEmpty) c.meaning,
                            if (c.targetLabel.isNotEmpty)
                              'সংখ্যা: ${c.targetLabel}'
                                  '${c.beepEvery > 0 ? '  •  প্রতি ${c.beepEvery} বারে বিপ' : ''}',
                          ].join('\n'),
                        ),
                  onTap: () => _edit(c),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(c),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
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

  String _label(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  Future<void> _pick(Prayer p, {required bool start}) async {
    final cur = start ? p.startMin : p.endMin;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
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
            child: Text(
              'A count is tagged with the prayer whose window contains the time you '
              'started counting. A window can cross midnight (e.g. Isha 7:30 PM → 2:00 AM). '
              'Times outside every window are saved without a prayer name.',
            ),
          ),
          for (final p in _prayers)
            ListTile(
              title: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Row(
                children: [
                  TextButton(
                    onPressed: () => _pick(p, start: true),
                    child: Text(_label(p.startMin)),
                  ),
                  const Text('→'),
                  TextButton(
                    onPressed: () => _pick(p, start: false),
                    child: Text(_label(p.endMin)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
