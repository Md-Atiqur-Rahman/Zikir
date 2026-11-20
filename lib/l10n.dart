import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';

/// Which language the app shows.
///
/// [defaultCode] is the saved setting the app opens in (Bangla until changed).
/// [code] is what is on screen right now: the quick EN / বাং button changes only
/// this, so the next start goes back to the saved default.
class Lang extends ChangeNotifier {
  String _default = 'bn';
  String _current = 'bn';

  String get defaultCode => _default;
  String get code => _current;
  Locale get locale => Locale(_current);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('langDefault');
    _default = saved == 'en' ? 'en' : 'bn';
    _current = _default;
  }

  /// Re-reads the saved default (after a restore) and shows it.
  Future<void> reload() async {
    await load();
    notifyListeners();
  }

  /// Saves the language the app opens in and switches to it now.
  Future<void> setDefault(String code) async {
    _default = code == 'en' ? 'en' : 'bn';
    _current = _default;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString('langDefault', _default);
  }

  /// Quick switch for this session only.
  void toggle() {
    _current = _current == 'bn' ? 'en' : 'bn';
    notifyListeners();
  }

  @visibleForTesting
  void useForTest(String code) {
    _default = code;
    _current = code;
  }
}

final lang = Lang();

const _bnDigits = '০১২৩৪৫৬৭৮৯';

String _toBnDigits(String s) =>
    s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _bnDigits[int.parse(m[0]!)]);

/// 1234567 -> ১২,৩৪,৫৬৭ (lakh / crore grouping, Bangla digits).
String _bnNumber(int v) {
  var d = v.abs().toString();
  if (d.length > 3) {
    final last3 = d.substring(d.length - 3);
    var rest = d.substring(0, d.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    d = '${parts.join(',')},$last3';
  }
  return (v < 0 ? '-' : '') + _toBnDigits(d);
}

const _prayerEn = <String, String>{
  'ফজর': 'Fajr',
  'ইশরাক': 'Ishraq',
  'চাশত': 'Chasht (Duha)',
  'জোহর': 'Zuhr',
  'আসর': 'Asr',
  'মাগরিব': 'Maghrib',
  'ইশা': 'Isha',
  'তাহাজ্জুদ': 'Tahajjud',
};

/// English name and meaning of the 20 built-in zikirs, in the same order as
/// [defaultZikirNames].
const zikirEnglish = <(String, String)>[
  ('Subhanallah', 'Allah is pure.'),
  ('Alhamdulillah', 'All praise is for Allah.'),
  ('Allahu Akbar', 'Allah is the Greatest.'),
  ('La ilaha illallah', 'There is no god but Allah.'),
  ('Astaghfirullah', 'I seek forgiveness from Allah.'),
  (
    "La hawla wa la quwwata illa billahil 'aliyyil 'azim",
    'There is no power to avoid sin and no strength to do good except with '
        'the help of Allah, the Most High, the Mighty.',
  ),
  (
    'Astaghfirullah, innallaha Ghafurur Rahim',
    'I seek forgiveness from Allah; indeed Allah is Most Forgiving, Most Merciful.',
  ),
  (
    "Allahumma salli wa sallim 'ala nabiyyina Muhammad",
    'O Allah, send blessings and peace upon our Prophet Muhammad (ﷺ).',
  ),
  (
    'Rabbi inni lima anzalta ilayya min khayrin faqir',
    'My Lord, I am in need of whatever good You send down to me. '
        '(Surah Al-Qasas 28:24)',
  ),
  (
    "Subhanallahi wa bihamdihi, Subhanallahil 'Azim",
    'Glory be to Allah and praise Him; glory be to Allah, the Most Great.',
  ),
  (
    'La ilaha illa anta subhanaka inni kuntu minaz-zalimin',
    'There is no god but You, glory be to You; indeed I was among the '
        'wrongdoers. (Surah Al-Anbiya 21:87)',
  ),
  (
    'Astaghfirullahal-ladhi la ilaha illa huwal Hayyul Qayyumu wa atubu ilayh',
    'I seek forgiveness from Allah, there is no god but He, the Ever-Living, '
        'the Sustainer of all; and I repent to Him.',
  ),
  (
    "Allahumma salli 'ala Muhammadin sallallahu 'alayhi wa sallam",
    "O Allah, send blessings upon Muhammad; may Allah's blessings and peace "
        'be upon him.',
  ),
  ('Allahummaghfir li', 'O Allah, forgive me.'),
  (
    "Hasbunallahu wa ni'mal wakil",
    'Allah is sufficient for us, and He is the best disposer of affairs.',
  ),
  (
    'Ya Hayyu ya Qayyum ya Dhal-Jalali wal-Ikram',
    'O Ever-Living, O Sustainer of all, O Possessor of Majesty and Honour.',
  ),
  (
    'Allahummarhamni bi-rahmatika ya Arhamar Rahimin',
    'O Allah, have mercy on me by Your mercy, O Most Merciful of the merciful.',
  ),
  (
    'Salamun qawlam mir Rabbir Rahim',
    '"Peace" - a word from a Merciful Lord. (Surah Ya-Sin 36:58)',
  ),
  (
    'Allahumma khairan fi kulli amrin antajiruh',
    'O Allah, grant me good in everything I am waiting for.',
  ),
  (
    'Rabbi anni massaniyad-durru wa anta Arhamur Rahimin',
    'My Lord, hardship has touched me, and You are the Most Merciful of the '
        'merciful. (Surah Al-Anbiya 21:83)',
  ),
];

Map<String, (String, String)>? _zikirEnCache;

Map<String, (String, String)> get _zikirEn => _zikirEnCache ??= {
  for (var i = 0; i < zikirEnglish.length; i++)
    defaultZikirNames[i]: zikirEnglish[i],
};

/// Every piece of text the app shows, in Bangla or English.
///
/// Get it with `S.of(context)`: it follows the app's locale, so a language switch
/// repaints every screen without losing its state.
class S {
  final bool bn;
  const S(this.bn);

  static const en = S(false);
  static const bangla = S(true);

  static S of(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'bn' ? bangla : en;

  String t(String en, String bn) => this.bn ? bn : en;

  // ---------- numbers and dates ----------

  String n(int v) =>
      bn ? _bnNumber(v) : NumberFormat.decimalPattern('en').format(v);

  /// Digits inside free text ("1-100") follow the language too.
  String digits(String s) => bn ? _toBnDigits(s) : s;

  String date(String pattern, DateTime d) {
    try {
      return DateFormat(pattern, bn ? 'bn' : 'en').format(d);
    } catch (_) {
      return DateFormat(pattern).format(d);
    }
  }

  // ---------- data that lives in the database ----------

  String zikirName(String stored) =>
      bn ? stored : (_zikirEn[stored]?.$1 ?? stored);

  /// Built-in zikirs get an English meaning; anything you wrote yourself is shown as written.
  String zikirMeaning(String name, String stored) {
    if (bn || stored.isEmpty) return stored;
    final e = _zikirEn[name];
    if (e != null && stored == defaultMeaningFor(name)) return e.$2;
    return stored;
  }

  String prayer(String stored) =>
      stored.isEmpty || bn ? stored : (_prayerEn[stored] ?? stored);

  // ---------- common ----------

  String get appName => t('Zikir', 'জিকির');
  String get cancel => t('Cancel', 'বাতিল');
  String get close => t('Close', 'বন্ধ করুন');
  String get save => t('Save', 'সংরক্ষণ');
  String get add => t('Add', 'যোগ করুন');
  String get delete => t('Delete', 'মুছুন');
  String get clear => t('Clear', 'মুছুন');
  String get copy => t('Copy', 'কপি');
  String get select => t('Select', 'নির্বাচন');
  String get none => t('None', 'কোনোটি নয়');

  // ---------- counter screen ----------

  String get chooseTime => t('Choose prayer time', 'ওয়াক্ত নির্বাচন করুন');
  String get autoByClock =>
      t('Auto (by clock)', 'স্বয়ংক্রিয় (ঘড়ি অনুযায়ী)');
  String get noPrayerWindow =>
      t('No prayer window now', 'এখন কোনো ওয়াক্তের সময় নয়');
  String get congratsTitle => t('Congratulations!', 'অভিনন্দন!');
  String congratsBody(String prayer, int total) => bn
      ? 'অভিনন্দন! ${prayer.isEmpty ? 'আজকের' : '$prayer-এর'} '
            'সব ${n(total)}টি জিকির সম্পন্ন হয়েছে।'
      : 'All ${n(total)} zikirs completed'
            '${prayer.isEmpty ? '' : ' for $prayer'}.';
  String get congratsButton => t('Alhamdulillah', 'আলহামদুলিল্লাহ');
  String get clearTitle => t('Clear without saving?', 'সংরক্ষণ না করে মুছবেন?');
  String clearBody(int count) => t(
    'The count of ${n(count)} will be lost.',
    '${n(count)} গণনা হারিয়ে যাবে।',
  );
  String get vibrationOn => t('Vibration on', 'কম্পন চালু');
  String get vibrationOff => t('Vibration off', 'কম্পন বন্ধ');
  String get soundOn => t('Sound on', 'শব্দ চালু');
  String get soundOff => t('Sound off', 'শব্দ বন্ধ');
  String get summary => t('Summary', 'সারসংক্ষেপ');
  String get menuZikirList => t('Zikir list', 'জিকিরের তালিকা');
  String get menuPrayerTimes => t('Prayer times', 'নামাজের সময়সূচী');
  String get menuTheme => t('Theme', 'থিম');
  String get menuSounds => t('Sounds', 'শব্দ');
  String get menuBulkImport => t('Bulk import', 'একসাথে ইমপোর্ট');
  String get menuAppLock => t('App lock', 'অ্যাপ লক');
  String get menuUpdate => t('Check for update', 'আপডেট দেখুন');
  String get menuClearRunning => t('Clear running count', 'চলমান গণনা মুছুন');
  String get menuLanguage => t('Language', 'ভাষা');
  String get prayerChipEmpty => t('Time: —', 'সময়: —');
  String doneChip(int done, int total) =>
      t('Done: ${n(done)}/${n(total)}', 'পড়া: ${n(done)}/${n(total)}');
  String countChipGoal(int count, int goal) =>
      t('Count: ${n(count)} / ${n(goal)}', 'সংখ্যা: ${n(count)} / ${n(goal)}');
  String countChip(String target) =>
      t('Count: $target', 'সংখ্যা: ${digits(target)}');
  String get tileToday => t('TODAY', 'আজ');
  String get tileAll => t('ALL TOTAL', 'সর্বমোট');
  String copyright(int year) =>
      t('© $year Zikir', '© ${digits('$year')} জিকির');
  String get email => t('Email', 'ইমেইল');
  String get phone => t('Phone', 'ফোন');
  String copied(String v) => t('Copied $v', 'কপি হয়েছে: $v');

  String get chooseZikir => t('Choose zikir', 'জিকির নির্বাচন করুন');
  String get newZikirName => t('New zikir name', 'নতুন জিকিরের নাম');
  String get meaningOptional => t('Meaning (optional)', 'অর্থ (ঐচ্ছিক)');
  String get targetOptional =>
      t('Target count (optional)', 'লক্ষ্যমাত্রা (ঐচ্ছিক)');
  String get beepOptional =>
      t('Beep every (optional)', 'প্রতি কত বারে বিপ (ঐচ্ছিক)');
  String get plusNew => t('+ New', '+ নতুন');

  // ---------- language ----------

  String get languageTitle => t('Language', 'ভাষা');
  String get languageHint => t(
    'The app opens in this language. The EN / বাং button at the top switches '
        'only for now.',
    'অ্যাপ এই ভাষায় খুলবে। উপরের EN / বাং বোতাম শুধু এখনকার জন্য ভাষা বদলায়।',
  );
  String get langBangla => 'বাংলা';
  String get langEnglish => 'English';

  /// Label of the quick button: it names the language it switches TO.
  String get langToggleLabel => bn ? 'EN' : 'বাং';
  String get langToggleTooltip =>
      t('Switch to Bangla', 'English-এ দেখুন (Switch to English)');

  // ---------- lock ----------

  String get lockWrong =>
      t('Wrong. Here is a new one.', 'ভুল। এই নিন নতুন একটি।');
  String get lockSolveToOpen => t('Solve the sum to open', 'খুলতে যোগটি করুন');
  String get lockSolveToOff =>
      t('Solve to turn the lock off', 'লক বন্ধ করতে যোগটি করুন');
  String get lockTitle => t('App lock', 'অ্যাপ লক');
  String get lockSwitch =>
      t('Ask a sum to open the app', 'অ্যাপ খুলতে যোগ করতে বলবে');
  String get lockHint => t(
    'Keeps children out. Locks again after the app was away for 1 minute.',
    'শিশুদের দূরে রাখে। অ্যাপ ১ মিনিট দূরে থাকলে আবার লক হয়।',
  );

  // ---------- sounds ----------

  String get soundsTitle => t('Sounds', 'শব্দ');
  String get play => t('Play', 'বাজান');
  String get intervalTitle => t('Beep every N counts', 'কয়েক বার পরপর বিপ');
  String get intervalHint => t(
    'Plays at each interval you set for a zikir.',
    'প্রতিটি জিকিরে আপনার দেওয়া বিরতিতে বাজে।',
  );
  String get doneTitle => t('Target reached', 'লক্ষ্যমাত্রা পূরণ');
  String get doneHint => t(
    'Plays when you reach the target count (with a long vibration).',
    'লক্ষ্যমাত্রায় পৌঁছালে বাজে (সঙ্গে লম্বা কম্পন)।',
  );

  String tone(String id) => switch (id) {
    'beep' => t('Beep', 'বিপ'),
    'double' => t('Double beep', 'দুইবার বিপ'),
    'triple' => t('Triple beep', 'তিনবার বিপ'),
    'bell' => t('Bell', 'ঘণ্টা'),
    'chime' => t('Chime', 'ঝংকার'),
    'rise' => t('Rising', 'ক্রমে উঁচু'),
    'drop' => t('Falling', 'ক্রমে নিচু'),
    'digital' => t('Digital', 'ডিজিটাল'),
    'soft' => t('Soft', 'নরম'),
    'alarm' => t('Alarm', 'অ্যালার্ম'),
    _ => id,
  };

  // ---------- theme ----------

  String get themeTitle => t('Theme', 'থিম');
  String get readyMade => t('Ready-made themes', 'তৈরি থিম');
  String makeOwn(String now) =>
      t('Make your own  (now: $now)', 'নিজের মতো করুন  (এখন: $now)');

  String themeColor(int i) {
    const names = [
      ('Background', 'পটভূমি'),
      ('Body (light)', 'শরীর (হালকা)'),
      ('Body (middle)', 'শরীর (মাঝারি)'),
      ('Body (dark)', 'শরীর (গাঢ়)'),
      ('Display frame', 'ডিসপ্লের ফ্রেম'),
      ('Display background', 'ডিসপ্লের পটভূমি'),
      ('Display digits', 'ডিসপ্লের সংখ্যা'),
      ('Count button glow', 'গণনা বোতামের আলো'),
      ('Reset button glow', 'রিসেট বোতামের আলো'),
    ];
    return t(names[i].$1, names[i].$2);
  }

  String themeName(String name) => switch (name) {
    'Classic Blue' => t('Classic Blue', 'ক্লাসিক নীল'),
    'Emerald' => t('Emerald', 'পান্না সবুজ'),
    'Midnight' => t('Midnight', 'মধ্যরাত'),
    'Royal Purple' => t('Royal Purple', 'রাজকীয় বেগুনি'),
    'Golden Sand' => t('Golden Sand', 'সোনালি বালি'),
    'Rose' => t('Rose', 'গোলাপি'),
    'Custom' => t('Custom', 'নিজের মতো'),
    _ => name,
  };

  // ---------- update ----------

  String get updateTitle => t('Check for update', 'আপডেট দেখুন');
  String get updChecking => t('Checking...', 'দেখা হচ্ছে...');
  String get updAsking => t(
    'Asking GitHub for the newest version.',
    'GitHub-এ নতুন সংস্করণ খোঁজা হচ্ছে।',
  );
  String get updUpToDate => t('You are up to date', 'আপনার অ্যাপ হালনাগাদ আছে');
  String updInstalled(int b) =>
      t('Installed: build $b', 'ইনস্টল করা: বিল্ড ${n(b)}');
  String get updAvailable => t('Update available', 'আপডেট পাওয়া গেছে');
  String updNew(int b) => t('New: build $b', 'নতুন: বিল্ড ${n(b)}');
  String updDownloading(int? b) => t(
    'Downloading build ${b ?? ''}...',
    'বিল্ড ${b == null ? '' : n(b)} ডাউনলোড হচ্ছে...',
  );
  String get updOpening => t('Opening the installer', 'ইনস্টলার খোলা হচ্ছে');
  String get updOpeningBody => t(
    'Tap Install on the screen Android shows. Your counts and settings are kept.',
    'অ্যান্ড্রয়েডের পর্দায় "ইনস্টল" চাপুন। আপনার গণনা ও সেটিংস থেকে যাবে।',
  );
  String get updFailed => t('Could not update', 'আপডেট করা যায়নি');
  String get updNow => t('Update now', 'এখনই আপডেট করুন');
  String get updMayAsk => t(
    'Android may ask you to allow Zikir to install apps the first time.',
    'প্রথমবার অ্যান্ড্রয়েড জিকিরকে অ্যাপ ইনস্টলের অনুমতি দিতে বলতে পারে।',
  );
  String get updAgain => t('Check again', 'আবার দেখুন');
  String get updWebOnly => t(
    'Updating works only in the Android app.',
    'আপডেট শুধু অ্যান্ড্রয়েড অ্যাপে কাজ করে।',
  );
  String get updPermission => t(
    'Permission was not given. Allow Zikir to install apps, then try again.',
    'অনুমতি দেওয়া হয়নি। জিকিরকে অ্যাপ ইনস্টলের অনুমতি দিয়ে আবার চেষ্টা করুন।',
  );
  String get updDownloadFailed => t(
    'The download failed. Check your internet and try again.',
    'ডাউনলোড ব্যর্থ হয়েছে। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
  );
  String updInstallFailed(String status) => t(
    'The update could not be installed ($status).',
    'আপডেট ইনস্টল করা যায়নি ($status)।',
  );
  String updHttp(int code) => t(
    'GitHub answered with code $code',
    'GitHub থেকে ত্রুটি এসেছে (কোড ${n(code)})',
  );
  String get updNoApk =>
      t('The latest release has no APK file', 'সর্বশেষ রিলিজে APK ফাইল নেই');
  String get updTimeout => t(
    'No answer from GitHub. Check your internet.',
    'GitHub থেকে সাড়া নেই। ইন্টারনেট দেখুন।',
  );

  // ---------- history pages ----------

  String get dayWise => t('Day-wise', 'দিনভিত্তিক');
  String totalZikir(int v) => t('Total zikir = ${n(v)}', 'মোট জিকির = ${n(v)}');
  String deleteTitle(String name) => t('Delete $name?', '$name মুছবেন?');
  String get deleteBody => t(
    'All saved counts in this category will be removed.',
    'এই জিকিরের সব সংরক্ষিত গণনা মুছে যাবে।',
  );
  String totalN(int v) => t('Total ${n(v)}', 'মোট ${n(v)}');
  String totalCountN(int v) => t('total count ${n(v)}', 'মোট গণনা ${n(v)}');
  String categoryTotal(String name, int v) =>
      t('Total $name count = ${n(v)}', 'মোট $name গণনা = ${n(v)}');
  String get noEntries6 =>
      t('No entries in the last 6 months.', 'গত ৬ মাসে কোনো এন্ট্রি নেই।');
  String get unnamedPrayer =>
      t('Other time (no prayer)', 'অন্য সময় (ওয়াক্ত ছাড়া)');
  String get dayTotalTitle => t('Day total', 'সারাদিনের মোট');
  String get prevDay => t('Previous day', 'আগের দিন');
  String get nextDay => t('Next day', 'পরের দিন');
  String dayHeader(int total, int zikirs) => t(
    'Total = ${n(total)}   (${n(zikirs)} zikir)',
    'মোট = ${n(total)}   (${n(zikirs)}টি জিকির)',
  );
  String readOnly(int days) => t(
    'Older than $days days: view only.',
    '${n(days)} দিনের পুরোনো: শুধু দেখা যাবে।',
  );
  String get nothingOnDay =>
      t('Nothing saved on this day.', 'এই দিনে কিছু সংরক্ষিত নেই।');
  String get less => t('Less', 'কমান');
  String get more => t('More', 'বাড়ান');
  String get savingZero =>
      t('Saving 0 removes this entry.', '০ সংরক্ষণ করলে এই এন্ট্রি মুছে যাবে।');
  String was(int v) => t('Was ${n(v)}', 'আগে ছিল ${n(v)}');

  String get allTotal => t('All total', 'সর্বমোট');
  String get lastDay => t('Last day', 'গত দিন');
  String lastDayOn(String d) => t('Last day · $d', 'গত দিন · $d');
  String get thisWeek => t('This week', 'এই সপ্তাহ');
  String get thisMonth => t('This month', 'এই মাস');
  String get monthWise => t(
    'Month-wise  (tap a month for its weeks)',
    'মাসভিত্তিক  (সপ্তাহ দেখতে মাসে চাপুন)',
  );
  String get nothingYet => t('Nothing saved yet.', 'এখনো কিছু সংরক্ষিত নেই।');
  String monthTotal(int v) => t('Month total = ${n(v)}', 'মাসের মোট = ${n(v)}');
  String get weekWise => t(
    'Week-wise  (tap a week for its days)',
    'সপ্তাহভিত্তিক  (দিন দেখতে সপ্তাহে চাপুন)',
  );
  String week(int i) => t('Week $i', 'সপ্তাহ ${n(i)}');
  String weekTotal(int v) =>
      t('Week total = ${n(v)}', 'সপ্তাহের মোট = ${n(v)}');

  // ---------- bulk import ----------

  String get bulkTitle => t('Bulk import', 'একসাথে ইমপোর্ট');
  String get bulkAskTitle => t('Add to history?', 'ইতিহাসে যোগ করবেন?');
  String bulkSummary(int zikirs, int days, String from, String to) => t(
    '${n(zikirs)} zikirs × ${n(days)} days ($from – $to)',
    '${n(zikirs)}টি জিকির × ${n(days)} দিন ($from – $to)',
  );
  String bulkTotalToAdd(int v) =>
      t('Total to add: ${n(v)}', 'মোট যোগ হবে: ${n(v)}');
  String get bulkOnTop => t(
    'This is added on top of anything already saved on those days.',
    'ওই দিনগুলোতে আগে যা সংরক্ষিত আছে, তার ওপর এটি যোগ হবে।',
  );
  String bulkAdded(int v) =>
      t('Added ${n(v)} to the history', 'ইতিহাসে ${n(v)} যোগ হয়েছে');
  String get bulkIntro => t(
    'Every selected zikir gets its count on every day of the range.',
    'নির্বাচিত প্রতিটি জিকিরের গণনা তারিখ-সীমার প্রতিটি দিনে যোগ হবে।',
  );
  String bulkFrom(String d) => t('From  $d', 'শুরু  $d');
  String bulkTo(String d) => t('To  $d', 'শেষ  $d');
  String get bulkSaveUnder =>
      t('Save under prayer time', 'যে ওয়াক্তে সংরক্ষণ হবে');
  String get bulkSection =>
      t('Zikir  –  count per day', 'জিকির  –  দিনে কত বার');
  String bulkBottom(int zikirs, int days, int total) => t(
    '${n(zikirs)} zikirs × ${n(days)} days\nTotal ${n(total)}',
    '${n(zikirs)}টি জিকির × ${n(days)} দিন\nমোট ${n(total)}',
  );
  String get bulkAddButton => t('Add to history', 'ইতিহাসে যোগ করুন');

  // ---------- zikir list ----------

  String get listTitle => t('Zikir list', 'জিকিরের তালিকা');
  String get addZikir => t('Add zikir', 'জিকির যোগ করুন');
  String get editZikir => t('Edit zikir', 'জিকির সম্পাদনা');
  String get name => t('Name', 'নাম');
  String get meaning => t('Meaning', 'অর্থ');
  String get meaningHint => t(
    'Shown under the zikir on the counter',
    'কাউন্টারে জিকিরের নিচে দেখায়',
  );
  String get targetHint => t('e.g. 100', 'যেমন ১০০');
  String get targetHelper => t(
    'Beep + long vibration when you reach it',
    'লক্ষ্যে পৌঁছালে বিপ ও লম্বা কম্পন',
  );
  String get beepHint => t('e.g. 20', 'যেমন ২০');
  String get beepHelper =>
      t('A short beep after every N counts', 'কয়েক বার গণনার পর পর ছোট বিপ');
  String get dragHint => t(
    'Drag to set the order. After you reset, the next zikir in this list is selected.',
    'ক্রম ঠিক করতে টেনে সরান। রিসেটের পর এই তালিকার পরের জিকির নির্বাচিত হবে।',
  );
  String beepEveryLabel(int v) =>
      t('  •  beep every ${n(v)}', '  •  প্রতি ${n(v)} বারে বিপ');

  // ---------- prayer times ----------

  String get prayerTimesTitle => t('Prayer times', 'নামাজের সময়সূচী');
  String get prayerTimesHelp => t(
    'A count is tagged with the prayer whose window contains the time you '
        'started counting. A window can cross midnight (e.g. Isha 7:30 PM → 2:00 AM). '
        'Times outside every window are saved without a prayer name.',
    'গণনা যে সময়ে শুরু হয়, সেই সময়ের ওয়াক্তের নামে সংরক্ষিত হয়। একটি ওয়াক্ত '
        'মধ্যরাত পেরিয়ে যেতে পারে (যেমন ইশা রাত ৭:৩০ → ২:০০)। কোনো ওয়াক্তের '
        'বাইরের সময়ের গণনা ওয়াক্তের নাম ছাড়া সংরক্ষিত হয়।',
  );

  // ---------- backup ----------

  String get ok => t('OK', 'ঠিক আছে');
  String get menuBackup => t('Backup & restore', 'ব্যাকআপ ও রিস্টোর');
  String get backupTitle => t('Backup & restore', 'ব্যাকআপ ও রিস্টোর');
  String get backupIntro => t(
    'Your counts live only on this phone. If you uninstall the app or lose the '
        'phone they are gone. Save a backup file now and then, for example to '
        'Google Drive.',
    'আপনার গণনা শুধু এই ফোনে আছে। অ্যাপ আনইনস্টল করলে বা ফোন হারালে সব চলে '
        'যাবে। মাঝে মাঝে ব্যাকআপ ফাইল সংরক্ষণ করুন, যেমন Google Drive-এ।',
  );
  String backupNowLine(int zikirs, int total) => t(
    'In the app now: ${n(zikirs)} zikirs, total ${n(total)}',
    'এখন অ্যাপে আছে: ${n(zikirs)}টি জিকির, মোট ${n(total)}',
  );
  String get backupNever =>
      t('No backup saved yet.', 'এখনো কোনো ব্যাকআপ সংরক্ষণ করা হয়নি।');
  String backupLast(String d) => t('Last backup: $d', 'শেষ ব্যাকআপ: $d');
  String get exportTitle => t('Export backup', 'ব্যাকআপ এক্সপোর্ট');
  String get exportHelp => t(
    'Saves your zikirs, all counts and your settings (theme, sounds, language) '
        'into one file.',
    'আপনার জিকির, সব গণনা ও সেটিংস (থিম, শব্দ, ভাষা) একটি ফাইলে সংরক্ষণ করে।',
  );
  String get exportButton => t('Save backup file', 'ব্যাকআপ ফাইল সংরক্ষণ করুন');
  String get restoreTitle => t('Restore from file', 'ফাইল থেকে রিস্টোর');
  String get restoreHelp => t(
    'Brings everything back from a backup file. It replaces what is in the '
        'app now.',
    'ব্যাকআপ ফাইল থেকে সব ফিরিয়ে আনে। এখন অ্যাপে যা আছে তা বদলে যাবে।',
  );
  String get restoreButton => t('Choose backup file', 'ব্যাকআপ ফাইল বাছুন');
  String get backupSaved => t('Backup saved', 'ব্যাকআপ সংরক্ষিত হয়েছে');
  String backupSavedBody(String name) => t(
    'File: $name\nKeep it somewhere safe, for example Google Drive.',
    'ফাইল: $name\nএটি নিরাপদ জায়গায় রাখুন, যেমন Google Drive-এ।',
  );
  String backupFailed(String e) =>
      t('Could not save the backup: $e', 'ব্যাকআপ সংরক্ষণ করা যায়নি: $e');
  String get restoreAskTitle => t('Replace everything?', 'সব বদলে ফেলবেন?');
  String restoreFileLine(
    int zikirs,
    int entries,
    int total,
    String a,
    String b,
  ) => t(
    'In the file: ${n(zikirs)} zikirs, ${n(entries)} saved days, total '
        '${n(total)} ($a \u2013 $b)',
    'ফাইলে আছে: ${n(zikirs)}টি জিকির, ${n(entries)}টি এন্ট্রি, মোট '
        '${n(total)} ($a \u2013 $b)',
  );
  String restoreSavedOn(String d) => t('Made on $d', 'তৈরি হয়েছে: $d');
  String get restoreWarn => t(
    'Everything in the app now will be replaced. This cannot be undone.',
    'এখন অ্যাপে যা আছে সব বদলে যাবে। এটি ফেরানো যাবে না।',
  );
  String get restoreReplace => t('Replace', 'বদলে দিন');
  String get restored => t('Restored', 'রিস্টোর হয়েছে');
  String get restoredBody => t(
    'Your zikirs, counts and settings are back.',
    'আপনার জিকির, গণনা ও সেটিংস ফিরে এসেছে।',
  );
  String restoreFailed(String e) =>
      t('Could not restore: $e', 'রিস্টোর করা যায়নি: $e');
  String get backupNotJson => t(
    'This file is not a readable backup.',
    'এই ফাইলটি পড়ার মতো ব্যাকআপ নয়।',
  );
  String get backupNotZikir =>
      t('This is not a Zikir backup file.', 'এটি জিকিরের ব্যাকআপ ফাইল নয়।');
  String get backupNewer => t(
    'This backup was made by a newer version of the app. Update the app first.',
    'এই ব্যাকআপ অ্যাপের নতুন সংস্করণে তৈরি। আগে অ্যাপ আপডেট করুন।',
  );
  String backupBroken(String what) => t(
    'The backup file is damaged or incomplete ($what).',
    'ব্যাকআপ ফাইলটি নষ্ট বা অসম্পূর্ণ ($what)।',
  );
}

/// Menu entry: choose the language the app opens in (it switches immediately).
Future<void> showLanguageDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LanguageDialog());

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog();

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.languageTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.languageHint),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: lang.defaultCode,
            onChanged: (v) async {
              if (v == null) return;
              await lang.setDefault(v);
              if (mounted) setState(() {});
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  key: const Key('lang-bn'),
                  value: 'bn',
                  title: Text(s.langBangla),
                ),
                RadioListTile<String>(
                  key: const Key('lang-en'),
                  value: 'en',
                  title: Text(s.langEnglish),
                ),
              ],
            ),
          ),
        ],
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
