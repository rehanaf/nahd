part of '../figure_canvas.dart';

extension _AssetTool on _FigureCanvasState {
  void handleAssetStart(Offset w, EditorTool tool, Figure fig) {
    if (tool == EditorTool.asset || widget.controller.isAssetMode) {
      if (_handleAssetStart(w, fig)) return;
    }
  }
}
