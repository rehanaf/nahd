import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/minecraft_skin.dart';
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

}
