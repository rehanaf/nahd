import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:id_animate/core/project_io.dart';
import 'package:id_animate/core/project_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const figureJson =
      '{"name":"Imported","points":[{"x":0,"y":0},{"x":30,"y":0}],'
      '"segments":[],"animations":[],"canvasWidth":800,"canvasHeight":600,'
      '"fps":12,"cycleFills":{},"rootIndices":[0],"visibility":{}}';

  test('importProjectZip imports a figure project', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('figure.json', figureJson))
      ..addFile(ArchiveFile.string(
        'project.json',
        jsonEncode({
          'format': 'id-animate-project',
          'version': 1,
          'type': 'figure',
          'name': 'Imported',
          'files': {'figure': 'figure.json', 'assets': <String>[]},
        }),
      ));

    final result = await importProjectZip(ZipEncoder().encodeBytes(archive));

    expect(result.imported.length, 1);
    final meta = result.imported.first;
    expect(meta.name, 'Imported');
    expect(meta.type, ProjectType.figure);

    final data = await ProjectStorage.loadProjectData(meta.id);
    expect(data?.figure, contains('Imported'));
  });

  test('importProjectZip imports an animation project with animation.json',
      () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('figure.json', figureJson))
      ..addFile(ArchiveFile.string(
          'animation.json', '{"name":"A","duration":1,"tracks":[]}'))
      ..addFile(ArchiveFile.string(
        'project.json',
        jsonEncode({
          'format': 'id-animate-project',
          'version': 1,
          'type': 'animation',
          'name': 'Animated',
          'files': {
            'figure': 'figure.json',
            'animation': 'animation.json',
            'assets': <String>[],
          },
        }),
      ));

    final result = await importProjectZip(ZipEncoder().encodeBytes(archive));

    final meta = result.imported.first;
    expect(meta.type, ProjectType.animation);
    final data = await ProjectStorage.loadProjectData(meta.id);
    expect(data?.animation, contains('"duration":1'));
  });

  test('importProjectZip rejects non-zip bytes', () async {
    expect(
      () => importProjectZip(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<Exception>()),
    );
  });

  test('importProjectZip rejects missing manifest', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('figure.json', figureJson));
    expect(
      () => importProjectZip(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<Exception>()),
    );
  });

  test('sanitizeFileName strips invalid characters', () {
    expect(sanitizeFileName('a/b\\c:d'), 'a_b_c_d');
    expect(sanitizeFileName('   '), 'project');
  });
}
