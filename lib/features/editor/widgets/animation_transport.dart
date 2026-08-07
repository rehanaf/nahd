import 'package:flutter/material.dart';

import '../controllers/editor_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'editor_buttons.dart';

/// Transport bar: prev/next frame, frame counter, play/pause.
class AnimationTransport extends StatelessWidget {
  final EditorController controller;

  const AnimationTransport({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).appColors;
    final totalFrames = controller.totalFrames;
    final currentFrame = controller.currentFrame;

    void goPrev() {
      controller.setCurrentTime((controller.currentTime - controller.frameDuration).clamp(0.0, controller.duration));
      controller.applyPose();
    }

    void goNext() {
      final nt = controller.currentTime + controller.frameDuration;
      if (nt > controller.duration) {
        controller.setDuration(nt);
        final anim = controller.ensureAnimation();
        if (nt > anim.duration) anim.duration = nt;
        controller.forceUpdate();
      }
      controller.setCurrentTime(nt);
      controller.applyPose();
    }

    return OverlayCapsule(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorIconButton(
            icon: Icons.skip_previous,
            onTap: goPrev,
          ),
          Text(
            '${currentFrame + 1} / $totalFrames',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          EditorIconButton(
            icon: Icons.skip_next,
            onTap: goNext,
          ),
          Container(width: 1, height: 20, color: palette.border),
          const SizedBox(width: 2),
          Material(
            color: controller.isPlaying
                ? const Color(0xFFEF4444)
                : const Color(0xFF22C55E),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: controller.togglePlay,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
