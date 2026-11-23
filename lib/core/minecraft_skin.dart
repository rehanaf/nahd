import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'models/figure.dart';
import 'models/segment.dart';

/// Minecraft skin importer.
///
/// Reads a standard 64x64 player skin (Java-Edition layout), separates the base
/// layer from the outer clothing layer (hat/jacket/sleeves/pants), and builds a
/// flat, riggable [Figure] where every body part is its own image-segment root.
///
/// The character can be projected from any horizontal angle ("yaw"):
///
///   * 0°  (front)      -> F=8, L=0, R=0, B=0
///   * 90° (right side) -> F=0, L=0, R=8, B=0
///   * 45°              -> F=5.5, R=5.5
///
/// A skin pixel maps to `scale` world units (default 8, so the 8x8 head becomes
/// 64x64 world units).

/// One rectangular UV region on the 64x64 atlas, in (x, y, width, height).
class McUv {
  final int x, y, w, h;
  const McUv(this.x, this.y, this.w, this.h);
}

/// One body part: its texel dimensions and the UV rect of each vertical face
/// in the base layer and the outer clothing layer. Faces are keyed by 'front',
/// 'back', 'left', 'right'. (Top/bottom faces are never visible in this flat
/// projection.)
class McPart {
  final String name;
  final double width, depth, height; // texels
  final Map<String, McUv> base;
  final Map<String, McUv> outer;

  const McPart({
    required this.name,
    required this.width,
    required this.depth,
    required this.height,
    required this.base,
    required this.outer,
  });
}

/// One projected (visible) face of a part: the face key, its UV source rects,
/// and the on-screen width at the current yaw (in texels, before scaling).
class McFace {
  final String side;
  final McUv baseUv;
  final McUv? outerUv;
  final double screenW;
  const McFace({
    required this.side,
    required this.baseUv,
    this.outerUv,
    required this.screenW,
  });
}

/// UV coordinates for every body part, in the standard 64x64 Java layout.
const List<McPart> kMcParts = [
  McPart(name: 'Head', width: 8, depth: 8, height: 8,
    base: {'right': McUv(0, 8, 8, 8), 'front': McUv(8, 8, 8, 8), 'left': McUv(16, 8, 8, 8), 'back': McUv(24, 8, 8, 8)},
    outer: {'right': McUv(32, 8, 8, 8), 'front': McUv(40, 8, 8, 8), 'left': McUv(48, 8, 8, 8), 'back': McUv(56, 8, 8, 8)}),
  McPart(name: 'Body', width: 8, depth: 4, height: 12,
    base: {'right': McUv(16, 20, 4, 12), 'front': McUv(20, 20, 8, 12), 'left': McUv(28, 20, 4, 12), 'back': McUv(32, 20, 8, 12)},
    outer: {'right': McUv(16, 36, 4, 12), 'front': McUv(20, 36, 8, 12), 'left': McUv(28, 36, 4, 12), 'back': McUv(32, 36, 8, 12)}),
  McPart(name: 'Right Arm', width: 4, depth: 4, height: 12,
    base: {'right': McUv(40, 20, 4, 12), 'front': McUv(44, 20, 4, 12), 'left': McUv(48, 20, 4, 12), 'back': McUv(52, 20, 4, 12)},
    outer: {'right': McUv(40, 36, 4, 12), 'front': McUv(44, 36, 4, 12), 'left': McUv(48, 36, 4, 12), 'back': McUv(52, 36, 4, 12)}),
  McPart(name: 'Left Arm', width: 4, depth: 4, height: 12,
    base: {'right': McUv(32, 52, 4, 12), 'front': McUv(36, 52, 4, 12), 'left': McUv(40, 52, 4, 12), 'back': McUv(44, 52, 4, 12)},
    outer: {'right': McUv(48, 52, 4, 12), 'front': McUv(52, 52, 4, 12), 'left': McUv(56, 52, 4, 12), 'back': McUv(60, 52, 4, 12)}),
  McPart(name: 'Right Leg', width: 4, depth: 4, height: 12,
    base: {'right': McUv(0, 20, 4, 12), 'front': McUv(4, 20, 4, 12), 'left': McUv(8, 20, 4, 12), 'back': McUv(12, 20, 4, 12)},
    outer: {'right': McUv(0, 36, 4, 12), 'front': McUv(4, 36, 4, 12), 'left': McUv(8, 36, 4, 12), 'back': McUv(12, 36, 4, 12)}),
  McPart(name: 'Left Leg', width: 4, depth: 4, height: 12,
    base: {'right': McUv(16, 52, 4, 12), 'front': McUv(20, 52, 4, 12), 'left': McUv(24, 52, 4, 12), 'back': McUv(28, 52, 4, 12)},
    outer: {'right': McUv(0, 52, 4, 12), 'front': McUv(4, 52, 4, 12), 'left': McUv(8, 52, 4, 12), 'back': McUv(12, 52, 4, 12)}),
];

/// Computes which vertical faces of [part] are visible at [yawDeg] and their
/// on-screen widths (in texels, no scale yet).
///
/// 0° = front, 90° = right side, 180° = back, -90° = left side. Only a single
/// horizontal (yaw) rotation is supported, so top/bottom faces are never
/// visible. At any angle at most two faces are visible: the front/back face
/// (width * |cos|) and one side face (depth * |sin|).
List<McFace> projectPartFaces(McPart part, double yawDeg) {
  final rad = yawDeg * math.pi / 180;
  final cos = math.cos(rad);
  final sin = math.sin(rad);

  final centerSide = cos >= 0 ? 'front' : 'back';
  final sideSide = sin >= 0 ? 'right' : 'left';
  final centerW = part.width * cos.abs();
  final sideW = part.depth * sin.abs();

  final faces = <McFace>[];
  if (sideW > 0.0001) {
    faces.add(McFace(
      side: sideSide,
      baseUv: part.base[sideSide]!,
      outerUv: part.outer[sideSide],
      screenW: sideW,
    ));
  }
  if (centerW > 0.0001) {
    faces.add(McFace(
      side: centerSide,
      baseUv: part.base[centerSide]!,
      outerUv: part.outer[centerSide],
      screenW: centerW,
    ));
  }

  // On-screen left->right order. When turning toward the right (sin >= 0) the
  // center face is leftmost; when turning left the side face is leftmost.
  if (sin < 0) {
    faces.sort((a, b) => a.side == sideSide ? -1 : 1);
  } else {
    faces.sort((a, b) => a.side == centerSide ? -1 : 1);
  }
  return faces;
}

/// Total on-screen width of [part] at [yawDeg], in texels (no scale).
double mcProjectedWidth(McPart part, double yawDeg) {
  final rad = yawDeg * math.pi / 180;
  return part.width * math.cos(rad).abs() + part.depth * math.sin(rad).abs();
}

/// Character layout in texels (y grows downward, feet sit at y = 0).
class McLayout {
  final double cx; // horizontal center
  final double topY; // top edge
  const McLayout(this.cx, this.topY);
}

/// Layout of each body part relative to the character, in texels.
McLayout mcPartLayout(McPart part) {
  switch (part.name) {
    case 'Head':
      return const McLayout(0, -32);
    case 'Body':
      return const McLayout(0, -24);
    case 'Right Arm':
      return const McLayout(6, -24);
    case 'Left Arm':
      return const McLayout(-6, -24);
    case 'Right Leg':
      return const McLayout(2, -12);
    case 'Left Leg':
      return const McLayout(-2, -12);
    default:
      return const McLayout(0, 0);
  }
}

/// Bounding box of the flat projected character in world units. Usable by the
/// import dialog preview to fit the character into a widget.
ui.Rect mcSkinBounds(double yawDeg, double scale) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final part in kMcParts) {
    final layout = mcPartLayout(part);
    final w = mcProjectedWidth(part, yawDeg) * scale;
    final h = part.height * scale;
    final cx = layout.cx * scale;
    final topY = layout.topY * scale;
    final l = cx - w / 2, t = topY, r = cx + w / 2, b = topY + h;
    if (l < minX) minX = l;
    if (t < minY) minY = t;
    if (r > maxX) maxX = r;
    if (b > maxY) maxY = b;
  }
  if (minX > maxX) return ui.Rect.zero;
  return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Composits the visible faces of [part] at [yawDeg] onto a single RGBA PNG
/// whose width equals the projected width and height equals the part height
/// (both texels, scaled by [scale]). The base layer is drawn first and the
/// outer clothing layer on top when [includeOuter] is true.
Future<Uint8List?> projectPartPng(
  ui.Image skin,
  McPart part,
  double yawDeg, {
  required double scale,
  required bool includeOuter,
}) async {
  final faces = projectPartFaces(part, yawDeg);
  if (faces.isEmpty) return null;

  var totalW = 0.0;
  for (final f in faces) {
    totalW += f.screenW;
  }
  final worldW = totalW * scale;
  final h = part.height * scale;
  if (worldW < 1 || h < 1) return null;

  final pixelW = math.max(worldW.round(), 1);
  final pixelH = math.max(h.round(), 1);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.none
    ..isAntiAlias = false;

  var x = 0.0;
  for (final face in faces) {
    final w = face.screenW * scale;
    if (w < 0.5) continue;
    final dst = ui.Rect.fromLTWH(x, 0, w, pixelH.toDouble());
    // The 'right'/'left' side faces are stored in the Java skin layout so that
    // they wrap around the model; viewed straight-on they are mirrored. Flipping
    // them horizontally makes the character face forward instead of backward.
    final flip = mcSideFace(face.side);
    _drawFace(canvas, skin, face.baseUv, dst, paint, flip: flip);
    if (includeOuter && face.outerUv != null) {
      _drawFace(canvas, skin, face.outerUv!, dst, paint, flip: flip);
    }
    x += w;
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelW, pixelH);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return byteData?.buffer.asUint8List();
}

void _drawFace(
  ui.Canvas canvas,
  ui.Image skin,
  McUv uv,
  ui.Rect dst,
  ui.Paint paint, {
  bool flip = false,
}) {
  final src = ui.Rect.fromLTWH(
      uv.x.toDouble(), uv.y.toDouble(), uv.w.toDouble(), uv.h.toDouble());
  if (!flip) {
    canvas.drawImageRect(skin, src, dst, paint);
    return;
  }
  canvas.save();
  canvas.translate(dst.center.dx, dst.center.dy);
  canvas.scale(-1, 1);
  canvas.translate(-dst.center.dx, -dst.center.dy);
  canvas.drawImageRect(skin, src, dst, paint);
  canvas.restore();
}

/// Whether [side] is a horizontal side face ('right'/'left'). In the Java
/// skin layout these faces wrap around the model and are stored mirrored
/// relative to how they appear when viewed straight on.
bool mcSideFace(String side) => side == 'right' || side == 'left';

/// Result of building a character figure from a skin.
class McImportResult {
  final Figure figure;
  final List<String> partNames;
  const McImportResult({required this.figure, required this.partNames});
}

/// Builds a [Figure] from a raw skin PNG.
///
/// * [scale]        - world units per skin pixel (default 8).
/// * [yawDeg]       - horizontal rotation angle (default 0 = front view).
/// * [includeOuter] - draw the clothing/overlay layer on top of the base.
///
/// Every body part becomes its own vertical image segment (baseline pointing
/// straight up, so the segment angle is exactly -90°; `imageRotate` = +90°
/// cancels it and keeps the image upright). Each image is centred exactly on
/// the segment midpoint, i.e. the part's centre.
///
/// The result is a ready-to-pose rig with a single root at the hips:
///
/// * body segment top (neck/shoulder line) -> `none` -> head and both arms;
/// * body root (hips)                        -> `none` -> both legs.
///
/// Every part connects to the torso/body through exactly one invisible `none`
/// segment (none segments are excluded from the -90° orientation rule), so the
/// whole character is ONE connected figure: the body can be moved/scaled as a
/// unit while each limb still rotates around its joint.
Future<McImportResult> buildMinecraftSkinFigure(
  Uint8List pngBytes, {
  double scale = 8,
  double yawDeg = 0,
  bool includeOuter = true,
}) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final skin = frame.image;

  final figure = Figure('Minecraft Character');
  final partNames = <String>[];
  // part name -> [p1 index (bottom), p2 index (top)].
  final partIndices = <String, List<int>>{};

  for (final part in kMcParts) {
    final png = await projectPartPng(
      skin,
      part,
      yawDeg,
      scale: scale,
      includeOuter: includeOuter,
    );
    if (png == null) continue;

    final worldW = mcProjectedWidth(part, yawDeg) * scale;
    final h = part.height * scale;
    final layout = mcPartLayout(part);
    final cx = layout.cx * scale;
    final topY = layout.topY * scale;
    final bottomY = topY + h;

    final startIdx = figure.points.length;
    // Vertical baseline pointing up: p1 = bottom, p2 = top, so the segment
    // angle is exactly -90°. The painter draws image segments rotated by the
    // p1->p2 angle; imageRotate = +90° cancels it and the image renders
    // upright. imageOffset = 0 keeps the image centred exactly on the part's
    // midpoint.
    figure.points.addAll([
      Point2(cx, bottomY),
      Point2(cx, topY),
    ]);

    final seg = Segment('image')
      ..point1Index = startIdx
      ..point2Index = startIdx + 1
      ..imageData = base64Encode(png)
      ..imageWidth = worldW
      ..imageHeight = h
      ..imageOffsetX = 0.0
      ..imageOffsetY = 0.0
      ..imageRotate = 90.0
      ..curved = false
      ..layer = figure.segments.length
      ..hidden = false;
    figure.segments.add(seg);
    partIndices[part.name] = [startIdx, startIdx + 1];
    partNames.add(part.name);
  }

  // Rig wiring. Image segments are vertical (p1 = bottom, p2 = top). The body
  // segment's top point is the neck/shoulder line and its bottom point is the
  // root (hips).
  final head = partIndices['Head'];
  final body = partIndices['Body'];
  final rarm = partIndices['Right Arm'];
  final larm = partIndices['Left Arm'];
  final rleg = partIndices['Right Leg'];
  final lleg = partIndices['Left Leg'];

  if (body == null) {
    if (figure.points.isNotEmpty) figure.rootIndices = [0];
  } else {
    final bodyTop = body[1];
    final bodyRoot = body[0];
    figure.rootIndices = [bodyRoot];
    void addBone(int fromIdx, int toIdx) {
      figure.segments.add(Segment('none')
        ..point1Index = fromIdx
        ..point2Index = toIdx
        ..layer = figure.segments.length
        ..hidden = false);
    }

    // Body segment -> none -> head + arms (join at the neck/shoulder line).
    if (head != null) addBone(bodyTop, head[0]);
    if (rarm != null) addBone(bodyTop, rarm[1]);
    if (larm != null) addBone(bodyTop, larm[1]);
    // Body root -> none -> legs (join at the hips).
    if (rleg != null) addBone(bodyRoot, rleg[1]);
    if (lleg != null) addBone(bodyRoot, lleg[1]);
  }

  skin.dispose();
  codec.dispose();
  figure.ensureDefaultGroup();
  figure.ensureSegmentsInDefaultGroup();
  return McImportResult(figure: figure, partNames: partNames);
}