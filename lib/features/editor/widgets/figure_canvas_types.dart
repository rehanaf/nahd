part of 'figure_canvas.dart';

/// Shared drag/pinch state for a single gesture, owned by `_FigureCanvasState`.
class _DragState {
  bool active = false;
  bool isPoint = false;
  int ptIdx = -1;
  bool isSegment = false;
  String? segId;
  bool isPan = false;
  double startPanX = 0;
  double startPanY = 0;
  double startCamX = 0;
  double startCamY = 0;
  double startX = 0;
  double startY = 0;
  double startPtX = 0;
  double startPtY = 0;
  bool creating = false;
  double anchorX = 0;
  double anchorY = 0;
  bool rotating = false;
  bool stretching = false;
  bool curving = false;
  int pivot = -1;
  double pivotCenterX = 0;
  double pivotCenterY = 0;
  List<int> connPts = [];
  List<double> initAngles = [];
  List<double> initDists = [];
  double startAngle = 0;
  double startDist = 0;
  Map<int, Point2> fkInit = {};
  Map<String, _Ctrl> fkCtrl = {};
  int joinPt = -1;
  bool assetDrag = false;
  String assetOp = ''; // 'move' | 'rotate' | 'resize'
  int assetHandle = -1;
  double startOx = 0;
  double startOy = 0;
  double startRot = 0;
  double startW = 0;
  double startH = 0;
  double assetCenterX = 0;
  double assetCenterY = 0;
  bool jointDone = false;
  bool maybeTap = false;
  bool tapWasSelected = false;
  final Map<String, Point2> anchorImgCenter = {};
  final Map<String, double> anchorImgRot = {};
  final Map<String, _SegInitial> initSegs = {};

  void reset() {
    active = false;
    isPoint = false;
    isSegment = false;
    isPan = false;
    creating = false;
    rotating = false;
    stretching = false;
    curving = false;
    segId = null;
    connPts = [];
    initAngles = [];
    initDists = [];
    fkInit = {};
    fkCtrl = {};
    assetDrag = false;
    assetOp = '';
    assetHandle = -1;
    jointDone = false;
    maybeTap = false;
    tapWasSelected = false;
    startX = 0;
    startY = 0;
    startPtX = 0;
    startPtY = 0;
    pivot = -1;
    startAngle = 0;
    startDist = 0;
    anchorImgCenter.clear();
    anchorImgRot.clear();
    initSegs.clear();
  }
}

/// A saved quadratic-bezier control offset (used while rotating/scaling).
class _Ctrl {
  double dx;
  double dy;
  _Ctrl(this.dx, this.dy);
}

class _SegInitial {
  double width;
  double imageWidth;
  double imageHeight;
  _SegInitial({
    required this.width,
    required this.imageWidth,
    required this.imageHeight,
  });
}
