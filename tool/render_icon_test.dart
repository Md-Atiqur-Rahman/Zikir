// Draws the app icon and writes the PNG files in assets/icon/.
//
// Run (it is a "test" only because that is the easy way to get Flutter's
// drawing engine without a phone):
//
//   flutter test tool/render_icon_test.dart
//
// then generate the Android sizes from the PNGs:
//
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _hand = ui.Color(0xFF2A3F5A);
const _beads = ui.Color(0xFF1C80C8);

// The picture is drawn in a 220-unit space; these are the edges of the artwork.
const _artCenter = ui.Offset(91, 128.5);
const _artHeight = 171.0;

void _drawArt(ui.Canvas canvas, {ui.Color? hand, ui.Color? beads}) {
  final handPaint = ui.Paint()
    ..color = hand ?? _hand
    ..isAntiAlias = true;
  final beadPaint = ui.Paint()
    ..color = beads ?? _beads
    ..isAntiAlias = true;
  final gap = ui.Paint()
    ..blendMode = ui.BlendMode.clear
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;

  // Everything lives in one layer so the thin "cut" lines can erase pixels.
  canvas.saveLayer(null, ui.Paint());

  // ---- the string of beads (drawn first: it goes behind the hand) ----
  final string = ui.Path()
    ..moveTo(133, 52)
    ..cubicTo(172, 62, 170, 148, 127, 177)
    ..cubicTo(114, 172, 103, 146, 101, 108);
  final contours = string.computeMetrics().toList();
  for (var i = 0; i < contours.length; i++) {
    final m = contours[i];
    double radius(double t) =>
        i == 0 ? 4.4 + 2.7 * math.pow(t, 1.25).toDouble() : 7.1 - 0.9 * t;
    // the second strand starts one bead after the first one ended
    var d = i == 0 ? 0.0 : 2 * radius(0) + 1.4;
    while (d <= m.length) {
      final r = radius(d / m.length);
      canvas.drawCircle(m.getTangentForOffset(d)!.position, r, beadPaint);
      d += 2 * r + 1.4;
    }
  }

  // ---- the tassel under the lowest bead ----
  canvas.drawCircle(const ui.Offset(127, 187), 3.4, beadPaint);
  canvas.drawPath(
    ui.Path()
      ..moveTo(123.2, 190)
      ..lineTo(130.8, 190)
      ..lineTo(137, 215)
      ..lineTo(117, 215)
      ..close(),
    beadPaint,
  );
  gap.strokeWidth = 1.7;
  canvas.drawLine(
    const ui.Offset(125.2, 197),
    const ui.Offset(123.6, 215),
    gap,
  );
  canvas.drawLine(
    const ui.Offset(128.8, 197),
    const ui.Offset(130.4, 215),
    gap,
  );

  // ---- the hand: arm, back of the hand, thumb, four curled fingers ----
  void bar(double cx, double cy, double w, double h, double r, double deg) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(deg * math.pi / 180);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(center: ui.Offset.zero, width: w, height: h),
        ui.Radius.circular(r),
      ),
      handPaint,
    );
    canvas.restore();
  }

  // forearm: widens towards the hand, cut at an angle at the wrist
  final arm = ui.Path()
    ..moveTo(26, 90)
    ..lineTo(86, 50)
    ..lineTo(104, 50)
    ..lineTo(104, 114)
    ..lineTo(88, 116)
    ..lineTo(40, 112)
    ..close();
  canvas.drawPath(arm, handPaint);
  canvas.drawPath(
    arm,
    ui.Paint()
      ..color = hand ?? _hand
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = ui.StrokeJoin.round
      ..isAntiAlias = true,
  );
  bar(92, 90, 50, 60, 15, 0); // fist body
  bar(109, 51.5, 42, 17, 8.5, 0); // thumb on top

  // fingers, stacked
  final fingers = <ui.Rect>[
    const ui.Rect.fromLTWH(92, 62, 40, 14.5),
    const ui.Rect.fromLTWH(92, 77.5, 38, 13.5),
    const ui.Rect.fromLTWH(92, 92, 36, 13.5),
    const ui.Rect.fromLTWH(93, 106.5, 30, 12.5),
  ];
  for (final f in fingers) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(f, const ui.Radius.circular(6.7)),
      handPaint,
    );
  }
  // thin cuts: between thumb and first finger, then between the fingers
  gap.strokeWidth = 1.9;
  canvas.drawLine(const ui.Offset(97, 61), const ui.Offset(118, 61), gap);
  for (var i = 0; i < 3; i++) {
    final y = fingers[i].bottom + 0.5;
    canvas.drawLine(ui.Offset(98, y), ui.Offset(fingers[i].right - 6, y), gap);
  }

  canvas.restore();
}

/// [fraction] is how much of the picture's height the artwork may use.
Future<void> _render(
  String path, {
  required double fraction,
  ui.Color? background,
  ui.Color? hand,
  ui.Color? beads,
}) async {
  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (background != null) {
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = background,
    );
  }
  canvas.save();
  canvas.translate(size / 2, size / 2);
  final s = fraction * size / _artHeight;
  canvas.scale(s);
  canvas.translate(-_artCenter.dx, -_artCenter.dy);
  _drawArt(canvas, hand: hand, beads: beads);
  canvas.restore();

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render the icon files', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      const white = ui.Color(0xFFFFFFFF);
      // old phones: the whole square, white behind the artwork
      await _render('assets/icon/icon.png', fraction: 0.80, background: white);
      // new phones: artwork only. flutter_launcher_icons adds a 16% margin on every
      // side (x0.68), so 0.76 lands at ~0.52 of the layer: well inside the safe circle.
      await _render('assets/icon/icon_foreground.png', fraction: 0.76);
      // Android 13 "themed icons": one colour, the launcher tints it
      const black = ui.Color(0xFF000000);
      await _render(
        'assets/icon/icon_monochrome.png',
        fraction: 0.76,
        hand: black,
        beads: black,
      );
    });
  });
}
