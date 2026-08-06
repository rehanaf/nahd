import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'json_utils.dart';
import 'project_storage.dart';

const String projectFormat = 'id-animate-project';
const int projectFormatVersion = 1;

class ProjectZipManifest {
  final String format;
  final int version;
  final ProjectType type;
  final String name;
  final String? groupId;
  final bool? predef;
  final String figureFile;
  final String? animationFile;
  final List<String> assets;

  const ProjectZipManifest({
    required this.format,
    required this.version,
    required this.type,
    required this.name,
    this.groupId,
    this.predef,
    this.figureFile = 'figure.json',
    this.animationFile,
    this.assets = const [],
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'type': type.name,
        'name': name,
        if (groupId != null) 'groupId': groupId,
        if (predef != null) 'predef': predef,
        'files': {
          'figure': figureFile,
          if (animationFile != null) 'animation': animationFile,
          'assets': assets,
        },
      };

  factory ProjectZipManifest.fromJson(Map<String, dynamic> json) {
    final files = json['files'];
    Map<String, dynamic> filesMap = {};
    if (files is Map) filesMap = files.cast<String, dynamic>();
    return ProjectZipManifest(
      format: json['format'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      type: json['type'] == 'animation'
          ? ProjectType.animation
          : ProjectType.figure,
      name: json['name'] as String? ?? '',
      groupId: json['groupId'] as String?,
      predef: json['predef'] as bool?,
      figureFile: filesMap['figure'] as String? ?? 'figure.json',
      animationFile: filesMap['animation'] as String?,
      assets: filesMap['assets'] is List
          ? (filesMap['assets'] as List)
              .whereType<String>()
              .toList()
          : const [],
    );
  }
}

class ImportProjectResult {
  final List<ProjectMeta> imported;
  final List<String> skipped;

  const ImportProjectResult({this.imported = const [], this.skipped = const []});
}

String sanitizeFileName(String name) {
  final s = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return s.isEmpty ? 'project' : s;
}

/// Exports [meta] as a `.zip` project file (figure.json + animation.json +
/// project.json manifest), letting the user save/download it.
Future<void> exportProjectZip(ProjectMeta meta) async {
  final data = await ProjectStorage.loadProjectData(meta.id);
  final figure = data?.figure;
  if (figure == null || figure.isEmpty) {
    throw Exception('Project data is empty');
  }
  final anim = data!.animation;

  final archive = Archive();
  archive.addFile(ArchiveFile.string('figure.json', figure));
  final manifest = ProjectZipManifest(
    format: projectFormat,
    version: projectFormatVersion,
    type: meta.type,
    name: meta.name,
    groupId: meta.groupId,
    predef: meta.predef,
    animationFile:
        meta.type == ProjectType.animation && anim != null
            ? 'animation.json'
            : null,
  );
  if (meta.type == ProjectType.animation && anim != null) {
    archive.addFile(ArchiveFile.string('animation.json', anim));
  }

  archive.addFile(
    ArchiveFile.string('project.json', jsonEncodePretty(manifest.toJson())),
  );

  final bytes = ZipEncoder().encodeBytes(archive);
  await FilePicker.saveFile(
    dialogTitle: 'Export project',
    fileName: '${sanitizeFileName(meta.name)}.zip',
    type: FileType.custom,
    allowedExtensions: ['zip'],
    bytes: bytes,
  );
}

/// Picks a `.zip` project file and imports it.
Future<ImportProjectResult> pickAndImportProjectZip() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) {
    return const ImportProjectResult();
  }
  return importProjectZip(bytes);
}

/// Imports an I'd Animate project from the given [bytes] of a `.zip` archive.
Future<ImportProjectResult> importProjectZip(Uint8List bytes) async {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw Exception('File is not a valid ZIP archive');
  }

  String? readEntry(String name) {
    for (final f in archive) {
      if (f.isFile && f.name == name) {
        final b = f.readBytes();
        return b == null ? null : utf8.decode(b, allowMalformed: true);
      }
    }
    return null;
  }

  final projectRaw = readEntry('project.json');
  if (projectRaw == null) {
    throw Exception('Invalid project file: project.json is missing');
  }
  ProjectZipManifest manifest;
  try {
    manifest = ProjectZipManifest.fromJson(
      (jsonDecode(projectRaw) as Map).cast<String, dynamic>(),
    );
  } catch (_) {
    throw Exception('Invalid project file: project.json is not valid JSON');
  }
  if (manifest.format != projectFormat) {
    throw Exception("Not an I'd Animate project file");
  }

  final type = manifest.type;
  final figureStr = readEntry(manifest.figureFile);
  if (figureStr == null) {
    throw Exception('Invalid project file: figure data is missing');
  }
  try {
    jsonDecode(figureStr);
  } catch (_) {
    throw Exception('Invalid project file: figure data is not valid JSON');
  }
  final animStr = readEntry(manifest.animationFile ?? '');

  ProjectMeta meta;
  if (manifest.predef == true && manifest.groupId != null) {
    final id = predefProjectId(type, manifest.groupId!, manifest.name);
    meta = await ProjectStorage.upsertProjectData(
      ProjectMeta(
        id: id,
        name: manifest.name,
        type: type,
        createdAt: 0,
        updatedAt: 0,
        groupId: manifest.groupId,
        predef: true,
      ),
      ProjectData(figure: figureStr, animation: animStr),
    );
  } else {
    meta = await ProjectStorage.createProject(type, manifest.name);
    await ProjectStorage.saveProjectData(
      meta.id,
      ProjectData(figure: figureStr, animation: animStr),
    );
  }

  return ImportProjectResult(imported: [meta]);
}
