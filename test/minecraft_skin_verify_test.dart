import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:id_animate/core/minecraft_skin.dart';

Rect uvRect(McUv uv) =>
    Rect.fromLTWH(uv.x.toDouble(), uv.y.toDouble(), uv.w.toDouble(), uv.h.toDouble());

/// Draws [src] into [dst], mirroring it horizontally when [flip] is true,
/// matching the production importer's side-face orientation.
void _drawUvTest(Canvas canvas, ui.Image img, Rect src, Rect dst, Paint p,
    {bool flip = false}) {
  if (!flip) {
    canvas.drawImageRect(img, src, dst, p);
    return;
  }
  canvas.save();
  canvas.translate(dst.center.dx, dst.center.dy);
  canvas.scale(-1, 1);
  canvas.translate(-dst.center.dx, -dst.center.dy);
  canvas.drawImageRect(img, src, dst, p);
  canvas.restore();
}

Future<ui.Image> decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Returns the RGBA of pixel (x, y) of [img].
Future<List<int>> pixel(ui.Image img, int x, int y) async {
  final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final off = (y * img.width + x) * 4;
  return [
    d.getUint8(off),
    d.getUint8(off + 1),
    d.getUint8(off + 2),
    d.getUint8(off + 3),
  ];
}

Future<bool> colorsEqual(ui.Image a, int ax, int ay, ui.Image b, int bx, int by) async {
  final pa = await pixel(a, ax, ay);
  final pb = await pixel(b, bx, by);
  return pa[0] == pb[0] && pa[1] == pb[1] && pa[2] == pb[2] && pa[3] == pb[3];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> compositAndWrite({
    required String skinPath,
    required String outName,
    required double scale,
    required double yawDeg,
    required bool includeOuter,
  }) async {
    final bytes = await File(skinPath).readAsBytes();
    final skin = await decodeBytes(bytes);

    final bounds = mcSkinBounds(yawDeg, scale);
    const side = 448.0;
    const pad = 16.0;
    final fitW = (side - pad * 2) / bounds.width;
    final fitH = (side - pad * 2) / bounds.height;
    final fit = fitW < fitH ? fitW : fitH;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, side, side),
      Paint()..color = const Color(0xFF1F2430),
    );
    canvas.save();
    canvas.translate(side / 2, side / 2);
    canvas.scale(fit);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.none
      ..isAntiAlias = false;
    for (final part in kMcParts) {
      final faces = projectPartFaces(part, yawDeg);
      if (faces.isEmpty) continue;
      final layout = mcPartLayout(part);
      final cx = layout.cx * scale;
      final topY = layout.topY * scale;
      final h = part.height * scale;
      var x = cx - (mcProjectedWidth(part, yawDeg) * scale) / 2;
      for (final face in faces) {
        final w = face.screenW * scale;
        if (w < 0.5) continue;
        final dst = Rect.fromLTWH(x, topY, w, h);
        final flip = mcSideFace(face.side);
        _drawUvTest(canvas, skin, uvRect(face.baseUv), dst, paint, flip: flip);
        if (includeOuter && face.outerUv != null) {
          _drawUvTest(canvas, skin, uvRect(face.outerUv!), dst, paint,
              flip: flip);
        }
        x += w;
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(side.toInt(), side.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    skin.dispose();

    final outDir = Directory('build/mc_out')..createSync(recursive: true);
    File('${outDir.path}/$outName')
        .writeAsBytesSync(byteData!.buffer.asUint8List());
  }

  /// Renders one part at an integer scale/yaw and asserts, texel by texel, that
  /// every composed pixel equals the exact source skin texel it maps to
  /// (nearest-neighbour sampling, so this must match bit-for-bit).
  Future<void> verifyPartExact(String skinPath, McPart part, double yawDeg) async {
    const scale = 12.0;
    final bytes = await File(skinPath).readAsBytes();
    final skin = await decodeBytes(bytes);
    final faces = projectPartFaces(part, yawDeg);
    expect(faces, isNotEmpty);

    final png = await projectPartPng(skin, part, yawDeg,
        scale: scale, includeOuter: false);
    expect(png, isNotNull);
    final composed = await decodeBytes(png!);
    final worldW = mcProjectedWidth(part, yawDeg) * scale;
    final h = part.height * scale;
    expect(composed.width, (worldW).round());
    expect(composed.height, (h).round());

    var offsetX = 0.0;
    for (final face in faces) {
      final w = face.screenW * scale;
      final flip = mcSideFace(face.side);
      // Integer scale 12; sample every texel's "top-left" corner block. The
      // side faces are mirrored in the composed image (see mcSideFace).
      for (var ty = 0; ty < part.height.toInt(); ty++) {
        for (var tx = 0; tx < face.screenW.toInt(); tx++) {
          final s = scale.toInt();
          final cx = offsetX.round() +
              (flip ? (face.screenW.toInt() - tx) * s - s : tx * s);
          final cy = ty * s;
          expect(
            await colorsEqual(
              composed, cx, cy, skin, face.baseUv.x + tx, face.baseUv.y + ty),
            isTrue,
            reason: '${part.name} ${face.side} texel ($tx,$ty) at yaw $yawDeg',
          );
        }
      }
      offsetX += w;
    }
    skin.dispose();
    composed.dispose();
  }

  test('Steve: full pipeline sanity + preview PNGs + exact face pixels', () async {
    final bytes = await File('steve.png').readAsBytes();
    final result = await buildMinecraftSkinFigure(
      bytes,
      scale: 12,
      yawDeg: 0,
      includeOuter: true,
    );
    final fig = result.figure;
    expect(fig.points.length, 12); // 6 parts x 2 points
    expect(fig.segments.length, 11); // 6 image parts + 5 'none' rig bones
    expect(fig.rootIndices.length, 1); // single rig root at the hips
    expect(fig.rootIndices.first, 2); // Body bottom point (hips)
    expect(result.partNames,
        ['Head', 'Body', 'Right Arm', 'Left Arm', 'Right Leg', 'Left Leg']);

    // Every non-body part is joined to the torso by exactly one 'none' segment.
    final noneSegs =
        fig.segments.where((s) => s.type == 'none').toList();
    expect(noneSegs.length, 5);
    for (final s in noneSegs) {
      // Each bone anchors on the torso (Body points are indices 2,3).
      final onBody = s.point1Index == 2 || s.point1Index == 3 ||
          s.point2Index == 2 || s.point2Index == 3;
      expect(onBody, isTrue, reason: 'bone must anchor on the torso: ${s.id}');
    }

    // Image segments must be vertical at exactly -90° (p1 bottom -> p2 top),
    // centred exactly on the part, and counter-rotated so they render upright.
    // 'none' connector segments are exempt from the -90° rule.
    for (final s in fig.segments) {
      if (s.type != 'image') continue;
      final p1 = fig.points[s.point1Index];
      final p2 = fig.points[s.point2Index];
      expect(p1.x, closeTo(p2.x, 0.001), reason: 'vertical ${s.id}');
      expect(p2.y, lessThan(p1.y), reason: 'p2 (top) above p1 (bottom)');
      expect(s.imageOffsetX, 0.0);
      expect(s.imageOffsetY, 0.0);
      expect(s.imageRotate, 90.0);
    }

    // Head baseline at scale 12, yaw 0: vertical, bottom (0,-288) -> top (0,-384).
    expect(fig.points[0].x, closeTo(0, 0.001));
    expect(fig.points[0].y, closeTo(-288, 0.001));
    expect(fig.points[1].x, closeTo(0, 0.001));
    expect(fig.points[1].y, closeTo(-384, 0.001));

    for (final entry in {
      'steve_0.png': 0.0,
      'steve_45.png': 45.0,
      'steve_neg45.png': -45.0,
      'steve_90.png': 90.0,
      'steve_180.png': 180.0,
    }.entries) {
      await compositAndWrite(
        skinPath: 'steve.png',
        outName: entry.key,
        scale: 12,
        yawDeg: entry.value,
        includeOuter: true,
      );
    }
    await compositAndWrite(
      skinPath: 'steve.png',
      outName: 'steve_0_noOuter.png',
      scale: 12,
      yawDeg: 0,
      includeOuter: false,
    );

    // Exact pixel verification across parts and angles.
    for (final part in kMcParts) {
      await verifyPartExact('steve.png', part, 0);
      await verifyPartExact('steve.png', part, 90);
    }
    await verifyPartExact('steve.png', kMcParts.first, -90);
  });

  test('Alex: renders without errors (narrow-arm layout)', () async {
    final bytes = await File('alex.png').readAsBytes();
    final result = await buildMinecraftSkinFigure(
      bytes,
      scale: 12,
      yawDeg: 0,
      includeOuter: true,
    );
    expect(result.figure.points.length, 12);
    expect(result.figure.segments.length, 11);

    await compositAndWrite(
      skinPath: 'alex.png',
      outName: 'alex_0.png',
      scale: 12,
      yawDeg: 0,
      includeOuter: true,
    );
    await compositAndWrite(
      skinPath: 'alex.png',
      outName: 'alex_90.png',
      scale: 12,
      yawDeg: 90,
      includeOuter: true,
    );

    // Only head/body/legs sampled exactly (Alex arms use the Alex layout, which
    // the Steve-width UV table does not special-case).
    await verifyPartExact('alex.png', kMcParts[0], 0);
    await verifyPartExact('alex.png', kMcParts[1], 0);
    await verifyPartExact('alex.png', kMcParts[4], 0);
    await verifyPartExact('alex.png', kMcParts[5], 0);
  });
}