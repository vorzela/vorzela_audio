import 'package:flutter/material.dart';

import '../vorzela_audio_controller.dart';

class VorzelaAudioTimeLabel extends StatelessWidget {
  const VorzelaAudioTimeLabel({
    super.key,
    required this.controller,
  });

  final VorzelaAudioController controller;

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Text(
          '${_fmt(controller.position)} / ${_fmt(controller.duration)}',
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}
