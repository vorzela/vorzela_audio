import 'package:flutter/material.dart';

import '../vorzela_audio_controller.dart';
import 'vorzela_audio_seek_bar.dart';
import 'vorzela_audio_time_label.dart';
import 'vorzela_audio_visualizer.dart';

typedef VorzelaAudioChromeBuilder = Widget Function(
  BuildContext context,
  VorzelaAudioController controller,
);

/// Optional player shell with customizable chrome sections.
class VorzelaAudioPlayerChrome extends StatelessWidget {
  const VorzelaAudioPlayerChrome({
    super.key,
    required this.controller,
    this.headerBuilder,
    this.footerBuilder,
    this.showVisualizer = true,
    this.useWaveSeekBar = false,
  });

  final VorzelaAudioController controller;
  final VorzelaAudioChromeBuilder? headerBuilder;
  final VorzelaAudioChromeBuilder? footerBuilder;
  final bool showVisualizer;
  final bool useWaveSeekBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headerBuilder != null) headerBuilder!(context, controller),
        if (showVisualizer) VorzelaAudioVisualizer(controller: controller),
        if (useWaveSeekBar)
          VorzelaWaveSeekBar(controller: controller)
        else
          VorzelaAudioSeekBar(controller: controller),
        VorzelaAudioTimeLabel(controller: controller),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: controller.pause,
              icon: const Icon(Icons.pause),
            ),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => IconButton(
                onPressed:
                    controller.isPlaying ? controller.pause : controller.play,
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
          ],
        ),
        if (footerBuilder != null) footerBuilder!(context, controller),
      ],
    );
  }
}
