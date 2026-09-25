import 'package:flutter/material.dart';

import '../vorzela_audio_controller.dart';

class VorzelaAudioSeekBar extends StatelessWidget {
  const VorzelaAudioSeekBar({
    super.key,
    required this.controller,
  });

  final VorzelaAudioController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final maxMs = controller.duration.inMilliseconds;
        final value = maxMs > 0
            ? controller.position.inMilliseconds.clamp(0, maxMs).toDouble()
            : 0.0;
        return Slider(
          value: value,
          max: maxMs > 0 ? maxMs.toDouble() : 1,
          onChanged: maxMs <= 0
              ? null
              : (v) => controller.seek(Duration(milliseconds: v.round())),
        );
      },
    );
  }
}

/// Wave-style seek bar; falls back to a linear [Slider] when no band data.
class VorzelaWaveSeekBar extends StatelessWidget {
  const VorzelaWaveSeekBar({
    super.key,
    required this.controller,
  });

  final VorzelaAudioController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final bands = controller.spectrum?.bands;
        if (bands == null || bands.isEmpty) {
          return VorzelaAudioSeekBar(controller: controller);
        }
        final maxMs = controller.duration.inMilliseconds;
        final progress = maxMs > 0
            ? controller.position.inMilliseconds / maxMs
            : 0.0;
        return Column(
          children: [
            SizedBox(
              height: 32,
              child: CustomPaint(
                painter: _WavePainter(bands: bands, progress: progress),
                size: Size.infinite,
              ),
            ),
            VorzelaAudioSeekBar(controller: controller),
          ],
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.bands, required this.progress});

  final List<double> bands;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blueGrey;
    final played = Paint()..color = Colors.blue;
    final barW = size.width / bands.length;
    for (var i = 0; i < bands.length; i++) {
      final h = (bands[i].clamp(0.0, 1.0) * size.height).clamp(2.0, size.height);
      final x = i * barW;
      final rect = Rect.fromLTWH(x, size.height - h, barW - 1, h);
      canvas.drawRect(
        rect,
        x / size.width <= progress ? played : paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.bands != bands;
}
