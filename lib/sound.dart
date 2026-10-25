import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Tone {
  final String id;
  final String label;
  final List<double> Function() build;
  const Tone(this.id, this.label, this.build);
}

/// Tones are generated in code (about 1 second each), so the app needs no sound files.
class Beeper {
  static const _rate = 22050;
  static final _player = AudioPlayer();
  static bool _ready = false;

  static String interval = 'beep'; // "beep every N counts"
  static String done = 'triple'; // target reached
  static final _cache = <String, Uint8List>{};

  static double _edge(double t) => min(1.0, min(t, 1 - t) / 0.02);
  static double _decay(double t) => min(1.0, t / 0.01) * exp(-4 * t);

  static List<double> _tone(
    double f,
    int ms, {
    double Function(double)? env,
    bool square = false,
    double harmonic = 0,
  }) {
    final n = _rate * ms ~/ 1000;
    final e = env ?? _edge;
    return List.generate(n, (i) {
      final ph = 2 * pi * f * i / _rate;
      var v = sin(ph);
      if (square) v = v >= 0 ? 0.7 : -0.7;
      if (harmonic > 0) v = (v + harmonic * sin(2 * ph)) / (1 + harmonic);
      return v * e(i / n);
    });
  }

  static List<double> _sweep(double f0, double f1, int ms) {
    final n = _rate * ms ~/ 1000;
    var ph = 0.0;
    return List.generate(n, (i) {
      final t = i / n;
      ph += 2 * pi * (f0 + (f1 - f0) * t) / _rate;
      return sin(ph) * _edge(t);
    });
  }

  static List<double> _gap(int ms) => List.filled(_rate * ms ~/ 1000, 0.0);

  static final tones = <Tone>[
    Tone('beep', 'Beep', () => _tone(1000, 1000)),
    Tone(
      'double',
      'Double beep',
      () => [..._tone(1000, 400), ..._gap(200), ..._tone(1000, 400)],
    ),
    Tone(
      'triple',
      'Triple beep',
      () => [
        ..._tone(1000, 260),
        ..._gap(110),
        ..._tone(1000, 260),
        ..._gap(110),
        ..._tone(1000, 260),
      ],
    ),
    Tone('bell', 'Bell', () => _tone(880, 1000, env: _decay, harmonic: 0.4)),
    Tone(
      'chime',
      'Chime',
      () => [..._tone(660, 500, env: _decay), ..._tone(880, 500, env: _decay)],
    ),
    Tone('rise', 'Rising', () => _sweep(500, 1200, 1000)),
    Tone('drop', 'Falling', () => _sweep(1200, 500, 1000)),
    Tone(
      'digital',
      'Digital',
      () => [
        for (var i = 0; i < 4; i++) ...[
          ..._tone(800, 125, square: true),
          ..._gap(125),
        ],
      ],
    ),
    Tone('soft', 'Soft', () => _tone(440, 1000, env: (t) => sin(pi * t))),
    Tone(
      'alarm',
      'Alarm',
      () => [for (var i = 0; i < 4; i++) ..._tone(i.isEven ? 900 : 700, 250)],
    ),
  ];

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    interval = p.getString('toneInterval') ?? interval;
    done = p.getString('toneDone') ?? done;
  }

  static Future<void> setInterval(String id) async {
    interval = id;
    (await SharedPreferences.getInstance()).setString('toneInterval', id);
  }

  static Future<void> setDone(String id) async {
    done = id;
    (await SharedPreferences.getInstance()).setString('toneDone', id);
  }

  static Future<void> playInterval() => play(interval);
  static Future<void> playDone() => play(done);

  static Future<void> play(String id) async {
    try {
      final bytes = _cache[id] ??= _wav(
        (tones.firstWhere(
          (t) => t.id == id,
          orElse: () => tones.first,
        )).build(),
      );
      if (!_ready) {
        _ready = true;
        // let the tone play over the user's music instead of pausing it
        await _player.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
              .build(),
        );
      }
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
      // a missing sound must never break counting
    }
  }

  /// 16-bit mono WAV from samples in -1..1.
  static Uint8List _wav(List<double> samples) {
    final dataLen = samples.length * 2;
    final b = ByteData(44 + dataLen);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, _rate, Endian.little);
    b.setUint32(28, _rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      b.setInt16(44 + i * 2, (samples[i] * 0.6 * 32767).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

/// Pick the tone for the "beep every N" alert and for "target reached".
class SoundPage extends StatefulWidget {
  const SoundPage({super.key});

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  Widget _section(
    String title,
    String hint,
    String selected,
    void Function(String) onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Text(hint),
        ),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (v) {
            if (v == null) return;
            onPick(v);
            Beeper.play(v);
          },
          child: Column(
            children: [
              for (final t in Beeper.tones)
                RadioListTile<String>(
                  value: t.id,
                  title: Text(t.label),
                  secondary: IconButton(
                    tooltip: 'Play',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => Beeper.play(t.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sounds')),
      body: ListView(
        children: [
          _section(
            'Beep every N counts',
            'Plays at each interval you set for a zikir.',
            Beeper.interval,
            (id) {
              Beeper.setInterval(id);
              setState(() {});
            },
          ),
          const Divider(),
          _section(
            'Target reached',
            'Plays when you reach the target count (with a long vibration).',
            Beeper.done,
            (id) {
              Beeper.setDone(id);
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
