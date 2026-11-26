import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:smooth_corner/smooth_corner.dart';

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
      final t = (controller.currentTime - 1).clamp(0.0, controller.duration);
      controller.setCurrentTime(t);
      controller.ensureAnimation();
      controller.applyPose();
    }

    void goNext() {
      final prevTime = controller.currentTime;
      final next = controller.currentFrame + 1;
      final nt = next.toDouble();
      var extended = false;
      if (nt + 0.001 >= controller.duration) {
        // Extend the timeline so the new frame actually exists.
        controller.setDuration(nt + 1);
        final anim = controller.ensureAnimation();
        if (nt + 1 > anim.duration) anim.duration = nt + 1;
        controller.forceUpdate();
        extended = true;
      }
      controller.setCurrentTime(nt);
      if (extended) {
        // Seed the new frame with the current pose so the timeline
        // continues from the previous frame.
        controller.recordPointsAtCurrentFrame(
          List<int>.generate(controller.figure.points.length, (i) => i),
        );
        // Also carry over segment sprite image indices from the previous frame.
        final authored = controller.figure.authoredFrameTimes();
        for (final seg in controller.figure.segments) {
          final imgIdx = controller.figure.getSegmentImageIndex(seg.id, prevTime) ?? seg.activeImageIndex;
          controller.figure.setSegmentImageIndex(seg.id, nt, imgIdx, authoredTimes: authored);
        }
      }
      controller.applyPose();
    }

    return OverlayCapsule(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          EditorIconButton(icon: LucideIcons.skip_back, onTap: goPrev),
          // Fixed-size slot: keeps the transport capsule from resizing when
          // the frame number gains/loses digits (e.g. 9/10 -> 10/100).
          SizedBox(
            width: 72,
            height: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${currentFrame + 1} / $totalFrames',
                textAlign: TextAlign.center,
                softWrap: false,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          EditorIconButton(icon: LucideIcons.skip_forward, onTap: goNext),
          Container(width: 1, height: 20, color: palette.border),
          const SizedBox(width: 2),
          Material(
            color: controller.isPlaying
                ? const Color(0xFFEF4444)
                : const Color(0xFF22C55E),
            shape: SmoothRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              smoothness: 1.0,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: controller.togglePlay,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  controller.isPlaying ? LucideIcons.pause : LucideIcons.play,
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
