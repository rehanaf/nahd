import '../project_storage.dart';

/// Predefined scene projects mirroring `scene/` in id-animate-nodes.
///
/// - figure/default/Stickman
/// - animation/default/Bounce Ball
/// - preset/default/Runner
class PredefinedProjects {
  PredefinedProjects._();

  static const String defaultGroup = 'default';

  static const String stickmanFigureJson = '''
{
  "name": "Stickman",
  "points": [
    { "x": 0, "y": -75 },
    { "x": 0, "y": -55 },
    { "x": 0, "y": -15 },
    { "x": -25, "y": -40 },
    { "x": 25, "y": -40 },
    { "x": -12, "y": 25 },
    { "x": 12, "y": 25 }
  ],
  "segments": [
    { "id": "seg_stick_head", "type": "circle", "point1Index": 0, "point2Index": 1, "color": "#111827", "fillColor": "#fca5a5", "width": 4, "lineCap": "round", "layer": 0, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_stick_torso", "type": "line", "point1Index": 1, "point2Index": 2, "color": "#111827", "fillColor": null, "width": 6, "lineCap": "round", "layer": 1, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_stick_arm_l", "type": "line", "point1Index": 1, "point2Index": 3, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 2, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_stick_arm_r", "type": "line", "point1Index": 1, "point2Index": 4, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 3, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_stick_leg_l", "type": "line", "point1Index": 2, "point2Index": 5, "color": "#111827", "fillColor": null, "width": 5, "lineCap": "round", "layer": 4, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_stick_leg_r", "type": "line", "point1Index": 2, "point2Index": 6, "color": "#111827", "fillColor": null, "width": 5, "lineCap": "round", "layer": 5, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null }
  ],
  "animations": [],
  "canvasWidth": 400,
  "canvasHeight": 400,
  "fps": 12,
  "cycleFills": {},
  "rootIndices": [0],
  "visibility": {}
}
''';

  static const String bounceFigureJson = '''
{
  "name": "Bounce Ball",
  "points": [
    { "x": 0, "y": -70 },
    { "x": 0, "y": 50 }
  ],
  "segments": [
    { "id": "seg_bounce_ball", "type": "circle", "point1Index": 0, "point2Index": 1, "color": "#2563eb", "fillColor": "#60a5fa", "width": 3, "lineCap": "round", "layer": 0, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null }
  ],
  "animations": [],
  "canvasWidth": 400,
  "canvasHeight": 400,
  "fps": 12,
  "cycleFills": {},
  "rootIndices": [0],
  "visibility": {}
}
''';

  static const String bounceAnimationJson = '''
{
  "name": "Bounce",
  "duration": 1,
  "tracks": [
    {
      "pointIndex": 0,
      "keyframes": [
        { "time": 0, "x": 0, "y": -70 },
        { "time": 0.33, "x": -120, "y": -70 },
        { "time": 0.66, "x": 120, "y": -70 },
        { "time": 1, "x": 0, "y": -70 }
      ]
    },
    {
      "pointIndex": 1,
      "keyframes": [
        { "time": 0, "x": 0, "y": 50 },
        { "time": 0.33, "x": -120, "y": 50 },
        { "time": 0.66, "x": 120, "y": 50 },
        { "time": 1, "x": 0, "y": 50 }
      ]
    }
  ]
}
''';

  static const String runnerFigureJson = '''
{
  "name": "Runner",
  "points": [
    { "x": 0, "y": -72 },
    { "x": 0, "y": -54 },
    { "x": 0, "y": -12 },
    { "x": -18, "y": -40 },
    { "x": 22, "y": -32 },
    { "x": 22, "y": 28 },
    { "x": -20, "y": 34 },
    { "x": 30, "y": 52 },
    { "x": -32, "y": 52 }
  ],
  "segments": [
    { "id": "seg_runner_head", "type": "circle", "point1Index": 0, "point2Index": 1, "color": "#111827", "fillColor": "#fcd34d", "width": 4, "lineCap": "round", "layer": 0, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_torso", "type": "line", "point1Index": 1, "point2Index": 2, "color": "#111827", "fillColor": null, "width": 6, "lineCap": "round", "layer": 1, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_arm_l", "type": "line", "point1Index": 1, "point2Index": 3, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 2, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_arm_r", "type": "line", "point1Index": 1, "point2Index": 4, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 3, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_thigh_l", "type": "line", "point1Index": 2, "point2Index": 5, "color": "#111827", "fillColor": null, "width": 5, "lineCap": "round", "layer": 4, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_thigh_r", "type": "line", "point1Index": 2, "point2Index": 6, "color": "#111827", "fillColor": null, "width": 5, "lineCap": "round", "layer": 5, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_leg_l", "type": "line", "point1Index": 5, "point2Index": 7, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 6, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null },
    { "id": "seg_runner_leg_r", "type": "line", "point1Index": 6, "point2Index": 8, "color": "#111827", "fillColor": null, "width": 4, "lineCap": "round", "layer": 7, "curved": false, "curvature": 0.3, "hidden": false, "imageData": null, "imageWidth": 100, "imageHeight": "auto", "shapeClosed": true, "filled": true, "controlDX": null, "controlDY": null }
  ],
  "animations": [],
  "canvasWidth": 400,
  "canvasHeight": 400,
  "fps": 12,
  "cycleFills": {},
  "rootIndices": [0],
  "visibility": {}
}
''';

  static List<PredefinedProject> all() => [
        PredefinedProject(
          type: ProjectType.figure,
          group: defaultGroup,
          name: 'Stickman',
          figure: stickmanFigureJson,
          animation: null,
        ),
        PredefinedProject(
          type: ProjectType.animation,
          group: defaultGroup,
          name: 'Bounce Ball',
          figure: bounceFigureJson,
          animation: bounceAnimationJson,
        ),
        PredefinedProject(
          type: ProjectType.preset,
          group: defaultGroup,
          name: 'Runner',
          figure: runnerFigureJson,
          animation: null,
        ),
      ];

  static List<String> getPredefinedGroups([ProjectType? type]) {
    final seen = <String>{};
    for (final p in all()) {
      if (type != null && p.type != type) continue;
      seen.add(p.group);
    }
    return seen.toList();
  }

  static Future<int> importPredefinedProjects() =>
      ProjectStorage.ensurePredefinedProjects(all());

  static Future<int> resetAllProjectData() =>
      ProjectStorage.clearAllData(all());
}
