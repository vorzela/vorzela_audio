import 'package:flutter/material.dart';

import '../vorzela_audio_controller.dart';
import '../vorzela_audio_spectrum.dart';

/// Simple three-band spectrum bars driven by [VorzelaAudioController.spectrum].
class VorzelaAudioVisualizer extends StatelessWidget {
  const VorzelaAudioVisualizer({
    super.key,
    required this.controller,
    this.height = 48,
    this.barColor,
  });

  final VorzelaAudioController controller;
  final double height;
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    final color = barColor ?? Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.spectrum ?? const VorzelaAudioSpectrum();
        return SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(level: s.bass, color: color),
              const SizedBox(width: 4),
              _Bar(level: s.mid, color: color),
              const SizedBox(width: 4),
              _Bar(level: s.high, color: color),
            ],
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = (level.clamp(0.0, 1.0) * constraints.maxHeight)
              .clamp(4.0, constraints.maxHeight);
          return Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 50),
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        },
      ),
    );
  }
}
