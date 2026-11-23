import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/minecraft_skin.dart';
import '../../../core/models/figure.dart';
import '../../../core/models/segment.dart';
import '../../../core/svg_import.dart';
import '../widgets/minecraft_skin_dialog.dart';
import 'editor_controller.dart';

extension EditorControllerSvgX on EditorController {
  /// Picks a Minecraft skin PNG, shows a settings dialog with a live preview,
  /// then imports the projected character as separate image-segment parts.
  Future<String?> importMinecraftSkin(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.bytes == null) return null;
      final pngBytes = file.bytes!;

      final codec = await ui.instantiateImageCodec(pngBytes);
      final frame = await codec.getNextFrame();
      final skin = frame.image;

      if (!context.mounted) {
        skin.dispose();
        codec.dispose();
        return null;
      }
      final settings = await showDialog<McSkinSettings>(
        context: context,
        useSafeArea: true,
        builder: (_) => DialogTheme(
          data: DialogThemeData(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          ),
          child: MinecraftSkinDialog(skin: skin),
        ),
      );
      skin.dispose();
      codec.dispose();
      if (settings == null) return null;

      final imported = await buildMinecraftSkinFigure(
        pngBytes,
        yawDeg: settings.yawDeg,
        includeOuter: settings.includeOuter,
      );
      if (imported.figure.points.isEmpty) {
        return 'No visible parts in that skin';
      }
      mergeImportedFigure(imported.figure);
      return 'Imported Minecraft skin (${imported.partNames.join(', ')})';
    } catch (e) {
      return 'Minecraft skin import failed: $e';
    }
  }
  Future<String?> importSvg() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.bytes == null) return null;
      final svgText = String.fromCharCodes(file.bytes!);
      if (svgText.isEmpty) return null;

      final src = parseSvgFigure(
        svgText,
        canvasWidth: figure.canvasWidth,
        canvasHeight: figure.canvasHeight,
      );
      if (src.points.isEmpty) {
        return 'No drawable shapes found in the SVG';
      }
      mergeImportedFigure(src);
      return 'Imported ${src.rootIndices.length} layer(s) from SVG';
    } catch (e) {
      return 'SVG import failed: $e';
    }
  }

  Future<String?> importSvgAsImage() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.bytes == null) return null;
      final svgText = String.fromCharCodes(file.bytes!);
      if (svgText.isEmpty) return null;

      final src = await parseSvgFigureAsAssets(
        svgText,
        canvasWidth: figure.canvasWidth,
        canvasHeight: figure.canvasHeight,
      );
      if (src.points.isEmpty) {
        return 'No drawable shapes found in the SVG';
      }
      mergeImportedFigure(src);
      return 'Imported ${src.rootIndices.length} layer(s) as images';
    } catch (e) {
      return 'SVG import failed: $e';
    }
  }

  void mergeImportedFigure(Figure src) {
    final srcPts = src.points;
    final xs = srcPts.map((p) => p.x).toList();
    final ys = srcPts.map((p) => p.y).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final curMaxX = figure.points.isEmpty
        ? -100
        : figure.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final offsetX = curMaxX + 100 - minX;
    final offsetY = -((minY + maxY) / 2);

    final indexMap = <int, int>{};
    final base = figure.points.length;
    for (var i = 0; i < srcPts.length; i++) {
      indexMap[i] = base + i;
      figure.points.add(Point2(srcPts[i].x + offsetX, srcPts[i].y + offsetY));
    }
    final roots = figure.rootIndices;
    final newRoots = <int>[];
    for (final r in src.rootIndices) {
      final mapped = indexMap[r];
      if (mapped == null) continue;
      newRoots.add(mapped);
      if (!roots.contains(mapped)) roots.add(mapped);
    }
    if (isAnimateMode) {
      for (final r in newRoots) {
        if (currentTime > 0.001) {
          figure.setFigureVisibility(r, 0, false);
        }
        figure.setFigureVisibility(r, currentTime, true);
      }
    }
    for (final s in src.segments) {
      final p1 = indexMap[s.point1Index];
      final p2 = indexMap[s.point2Index];
      if (p1 == null || p2 == null) continue;
      final ns = s.clone();
      ns.point1Index = p1;
      ns.point2Index = p2;
      ns.layer = ns.layer + figure.segments.length;
      figure.segments.add(ns);
    }
    mergeGroupsFrom(src);
    forceUpdate();
    pushHistory();
  }

  void mergeGroupsFrom(Figure src) {
    final present = {for (final s in figure.segments) s.id};
    for (final g in src.groups) {
      if (g.id == Figure.defaultGroupId) continue;
      final ids = g.segmentIds.where(present.contains).toList();
      if (ids.isEmpty) continue;
      figure.groups.add(LayerGroup(
        name: g.name,
        segmentIds: ids,
        visible: g.visible,
        locked: g.locked,
      ));
    }
    figure.ensureDefaultGroup();
    figure.ensureSegmentsInDefaultGroup();
  }
}
