import 'package:flutter_test/flutter_test.dart';
import 'package:id_animate/core/svg_import.dart';

// Path.flatten via computeMetrics may not be available in a pure Dart VM
// test; it requires the Flutter engine. Guard by running only when metrics
// work (flutter test launches with dart:ui available, but PathMetrics depend
// on the Skia engine). We probe first and skip if unsupported.

void main() {
  group('parseSvgFigure', () {
    test('parses two layers into separate roots', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <g id="head">
    <rect x="10" y="10" width="20" height="20" fill="#ff0000"/>
  </g>
  <g id="body">
    <rect x="10" y="40" width="20" height="30" fill="#00ff00"/>
  </g>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.points.length, greaterThan(0));
      expect(fig.rootIndices.length, 2);
      expect(fig.segments.length, greaterThan(0));
      // Every root is a valid point index.
      for (final r in fig.rootIndices) {
        expect(r, lessThan(fig.points.length));
      }
    });

    test('closed paths produce a closing connector segment', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <polygon points="0,0 10,0 10,10 0,10" fill="#3366ff"/>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.segments.length, greaterThanOrEqualTo(4));
      expect(fig.rootIndices.length, 1);
    });

    test('bounces when the svg has no shapes', () {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
      final fig = parseSvgFigure(svg);
      expect(fig.points.length, 0);
    });

    test('layer fills are copied as segment colors', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <rect x="0" y="0" width="5" height="5" fill="#ff0000"/>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.segments.every((s) => s.color == '#ff0000'), isTrue);
    });

    test('colors inherit from a parent group', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="#00aa33">
  <rect x="0" y="0" width="5" height="5"/>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.segments.isNotEmpty, isTrue);
      expect(
          fig.segments.every((s) => s.color == '#00aa33'), isTrue);
    });

    test('gradient fills resolve to the first stop colour', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <defs>
    <linearGradient id="g1">
      <stop offset="0" stop-color="#123456"/>
      <stop offset="1" stop-color="#ffffff"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="5" height="5" fill="url(#g1)"/>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.segments.every((s) => s.color == '#123456'), isTrue);
    });

    test('named and rgb colors are parsed', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <rect x="0" y="0" width="5" height="5" fill="tomato"/>
  <rect x="5" y="0" width="5" height="5" fill="rgb(1, 2, 3)"/>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.segments.any((s) => s.color == '#ff6347'), isTrue);
      expect(fig.segments.any((s) => s.color == '#010203'), isTrue);
    });

    test('multiple disjoint shapes in one layer are linked with type none', () {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g id="limb">
    <rect x="0" y="0" width="10" height="10" fill="#ff0000"/>
    <rect x="50" y="0" width="10" height="10" fill="#ff0000"/>
  </g>
</svg>
''';
      final fig = parseSvgFigure(svg);
      expect(fig.rootIndices.length, 1);
      final hasNone = fig.segments.any((s) => s.isNone);
      expect(hasNone, isTrue);
    });
  });

  group('parseSvgFigureAsAssets', () {
    test('turns each layer into one image segment with its own root', () async {
      const svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <g id="head">
    <rect x="10" y="10" width="20" height="20" fill="#ff0000"/>
  </g>
  <g id="body">
    <rect x="10" y="40" width="20" height="30" fill="#00ff00"/>
  </g>
</svg>
''';
      final fig = await parseSvgFigureAsAssets(svg);
      expect(fig.rootIndices.length, 2);
      // Two points per layer (anchors), one image segment per layer.
      expect(fig.points.length, 4);
      expect(fig.segments.length, 2);
      expect(fig.segments.every((s) => s.type == 'image'), isTrue);
      expect(fig.segments.every((s) => s.imageData != null), isTrue);
      expect(fig.segments.every((s) => s.imageData!.startsWith('data:image/png;base64,')),
          isTrue);
      for (final r in fig.rootIndices) {
        expect(r, lessThan(fig.points.length));
      }
    });

    test('bounces when the svg has no shapes', () async {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
      final fig = await parseSvgFigureAsAssets(svg);
      expect(fig.points.length, 0);
      expect(fig.segments.length, 0);
    });
  });
}