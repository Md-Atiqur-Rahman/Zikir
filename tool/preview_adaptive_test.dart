// Shows how the adaptive launcher icon looks after Android's masks.
//   flutter test tool/preview_adaptive_test.dart   ->  build/icon_preview/adaptive_preview.png (not committed)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _load(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

void main() {
  test('adaptive icon preview', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      const res = 'android/app/src/main/res/';
      final fg = await _load(
        '${res}drawable-xxxhdpi/ic_launcher_foreground.png',
      );
      const layer = 432.0; // the 108 dp layer at xxxhdpi
      const gap = 24.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, layer * 3 + gap * 4, layer + gap * 2),
        ui.Paint()..color = const ui.Color(0xFFB0BEC5),
      );

      void draw(int slot, ui.Path Function(ui.Rect) mask) {
        final left = gap + slot * (layer + gap);
        final box = ui.Rect.fromLTWH(left, gap, layer, layer);
        canvas.save();
        canvas.clipPath(mask(box));
        canvas.drawRect(box, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        // the generated xml insets the foreground by 16% on every side
        final inner = box.deflate(layer * 0.16);
        canvas.drawImageRect(
          fg,
          ui.Rect.fromLTWH(0, 0, fg.width.toDouble(), fg.height.toDouble()),
          inner,
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        canvas.restore();
      }

      // the launcher shows the middle 72 dp (two thirds) through its mask
      ui.Rect visible(ui.Rect b) => b.deflate(layer * 0.167);
      draw(0, (b) => ui.Path()..addOval(visible(b)));
      draw(
        1,
        (b) => ui.Path()
          ..addRRect(
            ui.RRect.fromRectAndRadius(
              visible(b),
              const ui.Radius.circular(70),
            ),
          ),
      );
      draw(2, (b) => ui.Path()..addRect(visible(b)));

      final image = await recorder.endRecording().toImage(
        (layer * 3 + gap * 4).toInt(),
        (layer + gap * 2).toInt(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/icon_preview/adaptive_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
