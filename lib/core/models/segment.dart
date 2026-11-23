import 'dart:ui';

/// Parses a hex color string into a [Color]. Supported formats:
/// "#rgb", "#argb", "#rrggbb" (opaque), "#aarrggbb" (with alpha).
/// Returns null when [value] is null/empty.
Color? parseHexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  var hex = value.replaceFirst('#', '').trim();
  if (hex.length == 3 || hex.length == 4) {
    hex = hex.split('').map((c) => c * 2).join();
  }
  if (hex.length == 6) {
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
  if (hex.length == 8) {
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    return Color(v);
  }
  return null;
}

/// Formats a [Color] as a hex string. Opaque colors use "#rrggbb" (keeps
/// the original app's format); translucent colors use "#aarrggbb".
String colorToHex(Color? color) {
  if (color == null) return '#d1d5db';
  final a = ((color.a * 255).round() & 0xFF);
  final r = ((color.r * 255).round() & 0xFF);
  final g = ((color.g * 255).round() & 0xFF);
  final b = ((color.b * 255).round() & 0xFF);
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  if (a == 255) return '#${two(r)}${two(g)}${two(b)}';
  return '#${two(a)}${two(r)}${two(g)}${two(b)}';
}

class Point2 {
  double x;
  double y;
  bool isAttached;
  bool isStatic;

  Point2([this.x = 0, this.y = 0, this.isAttached = false, this.isStatic = false]);

  Point2.fromJson(Map<String, dynamic> json)
      : x = (json['x'] as num?)?.toDouble() ?? 0,
        y = (json['y'] as num?)?.toDouble() ?? 0,
        isAttached = json['isAttached'] as bool? ?? false,
        isStatic = json['static'] as bool? ?? false;

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'isAttached': isAttached, 'static': isStatic};

  Point2 clone() => Point2(x, y, isAttached, isStatic);

  @override
  String toString() => '($x, $y)';
}

/// A Segment connects two points (by index) in a [Figure].
///
/// Mirrors `src/core/nodes/Segment.js` (id-animate-nodes) for JSON
/// compatibility with existing projects.
class Segment {
  String id;
  String type; // 'line' | 'circle' | 'image'
  int point1Index;
  int point2Index;
  String color;
  String? fillColor;
  double width;
  String lineCap; // 'round' | 'square' | 'butt'
  String lineJoin; // 'round' | 'miter' | 'bevel'
  int layer;
  bool curved;
  double curvature;
  bool hidden;
  List<String> imageDataList;
  int activeImageIndex;
  dynamic imageObj; // runtime decoded object (unused in Dart)
  dynamic imageWidth; // number or 'auto'
  dynamic imageHeight; // number or 'auto'
  double imageOffsetX;
  double imageOffsetY;
  double imageRotate;
  bool shapeClosed;
  bool filled;
  double? controlDX;
  double? controlDY;
  bool isCollision; // game-dev flag: this part participates in collision

  /// Text shown by a `text` segment (rendered at the segment midpoint and
  /// rotated along the segment angle so it can be animated by its points).
  String? text;
  double textSize;

  static int _counter = 0;

  Segment([this.type = 'line'])
      : id = 'seg_${_randomId()}',
        point1Index = 0,
        point2Index = 1,
        color = '#000000',
        fillColor = null,
        width = 10,
        lineCap = 'round',
        lineJoin = 'round',
        layer = 0,
        curved = false,
        curvature = 0.3,
        hidden = false,
        imageDataList = [],
        activeImageIndex = 0,
        imageObj = null,
        imageWidth = 100,
        imageHeight = 'auto',
        imageOffsetX = 0,
        imageOffsetY = 0,
        imageRotate = 0,
        shapeClosed = true,
        filled = false,
        controlDX = null,
        controlDY = null,
        isCollision = false,
        text = null,
        textSize = 32;

  String? get imageData {
    if (imageDataList.isEmpty) return null;
    if (activeImageIndex < 0 || activeImageIndex >= imageDataList.length) return imageDataList.first;
    return imageDataList[activeImageIndex];
  }
  
  set imageData(String? data) {
    if (data == null) {
      imageDataList.clear();
      activeImageIndex = 0;
    } else {
      imageDataList = [data];
      activeImageIndex = 0;
    }
  }

  static String _randomId() {
    _counter++;
    final stamp = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
    return '${stamp.toRadixString(36)}${_counter.toRadixString(36)}';
  }

  bool get isCircle => type == 'circle';
  bool get isImage => type == 'image';
  bool get isNone => type == 'none';
  bool get isText => type == 'text';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'point1Index': point1Index,
        'point2Index': point2Index,
        'color': color,
        'fillColor': fillColor,
        'width': width,
        'lineCap': lineCap,
        'lineJoin': lineJoin,
        'layer': layer,
        'curved': curved,
        'curvature': curvature,
        'hidden': hidden,
        'imageDataList': imageDataList,
        'activeImageIndex': activeImageIndex,
        'imageData': imageData, // For backwards compatibility when saving
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'imageOffsetX': imageOffsetX,
        'imageOffsetY': imageOffsetY,
        'imageRotate': imageRotate,
        'shapeClosed': shapeClosed,
        'filled': filled,
        'controlDX': controlDX,
        'controlDY': controlDY,
        'isCollision': isCollision,
        'text': text,
        'textSize': textSize,
      };

  factory Segment.fromJson(Map<String, dynamic> data) {
    final seg = Segment(data['type'] as String? ?? 'line');
    seg.id = data['id'] as String? ?? seg.id;
    seg.point1Index = (data['point1Index'] as num?)?.toInt() ?? 0;
    seg.point2Index = (data['point2Index'] as num?)?.toInt() ?? 1;
    seg.color = data['color'] as String? ?? '#000000';
    seg.fillColor = data['fillColor'] as String?;
    seg.width = (data['width'] as num?)?.toDouble() ?? 16;
    seg.lineCap = data['lineCap'] as String? ?? 'round';
    seg.lineJoin = data['lineJoin'] as String? ?? 'round';
    seg.layer = (data['layer'] as num?)?.toInt() ?? 0;
    seg.curved = data['curved'] as bool? ?? false;
    seg.curvature = (data['curvature'] as num?)?.toDouble() ?? 0.3;
    seg.hidden = data['hidden'] as bool? ?? false;
    
    if (data['imageDataList'] != null) {
      seg.imageDataList = List<String>.from(data['imageDataList']);
      seg.activeImageIndex = (data['activeImageIndex'] as num?)?.toInt() ?? 0;
    } else if (data['imageData'] != null) {
      seg.imageDataList = [data['imageData'] as String];
      seg.activeImageIndex = 0;
    }
    
    seg.imageWidth = data['imageWidth'] ?? 100;
    seg.imageHeight = data['imageHeight'] ?? 'auto';
    seg.imageOffsetX = (data['imageOffsetX'] as num?)?.toDouble() ?? 0;
    seg.imageOffsetY = (data['imageOffsetY'] as num?)?.toDouble() ?? 0;
    seg.imageRotate = (data['imageRotate'] as num?)?.toDouble() ?? 0;
    seg.shapeClosed = data['shapeClosed'] as bool? ?? true;
    seg.filled = data['filled'] as bool? ?? (seg.type != 'circle' && seg.type != 'none');
    seg.controlDX = (data['controlDX'] as num?)?.toDouble();
    seg.controlDY = (data['controlDY'] as num?)?.toDouble();
    seg.isCollision = data['isCollision'] as bool? ?? false;
    seg.text = data['text'] as String?;
    seg.textSize = (data['textSize'] as num?)?.toDouble() ?? 32;
    return seg;
  }

  Segment clone() => Segment.fromJson(toJson());
}
