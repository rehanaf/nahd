# Graph Report - .  (2026-08-04)

## Corpus Check
- Corpus is ~28,110 words - fits in a single context window. You may not need a graph.

## Summary
- 825 nodes · 973 edges · 42 communities (34 shown, 8 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 11 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Editor State & History
- Canvas Drawing Widget
- Main Menu & Groups UI
- Project Storage & Persistence
- Segment Data Model
- Theme & Color Picker
- Project Import/Export
- Figure Data Model
- Segment Inspector Panel
- Editor Screen Shell
- Animation Keyframe Model
- iOS App Delegates
- Frames Timeline Screen
- Project Scaffold & Config
- Figure Preview Rendering
- Editor Buttons
- App Entry & Navigation
- Animation Settings Panel
- Screen Stateful Widgets
- Sheet & Dialog Widgets
- Predefined Projects
- App Settings Controller
- Web Manifest Config
- Import/Export Tests
- Animation Transport Controls
- JSON Utilities
- Model Roundtrip Tests
- App Icons (All Platforms)
- OpenCode Config
- Android MainActivity
- ChangeNotifier Controllers
- Graphify Plugin
- Editor Route
- Editor Tool Enum
- FigureCanvas Widget
- Accordion Widget
- SegmentInspector Widget
- None Bool Type

## God Nodes (most connected - your core abstractions)
1. `id_animate Package Definition` - 14 edges
2. `EditorController` - 9 edges
3. `AppPalette` - 7 edges
4. `AppDelegate` - 5 edges
5. `Figure` - 4 edges
6. `ProjectMeta` - 4 edges
7. `AppController` - 4 edges
8. `Flutter` - 3 edges
9. `RunnerTests` - 3 edges
10. `ProjectType` - 3 edges

## Surprising Connections (you probably didn't know these)
- `flutter_lints Lint Set` --semantically_similar_to--> `flutter_lints Dev Dependency`  [INFERRED] [semantically similar]
  analysis_options.yaml → pubspec.yaml
- `Android App Icon (Flutter Default)` --semantically_similar_to--> `iOS App Icon (Flutter Default)`  [INFERRED] [semantically similar]
  android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png → ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
- `Android App Icon (Flutter Default)` --semantically_similar_to--> `Web PWA Icon (Flutter Default)`  [INFERRED] [semantically similar]
  android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png → web/icons/Icon-512.png
- `iOS App Icon (Flutter Default)` --semantically_similar_to--> `Web PWA Icon (Flutter Default)`  [INFERRED] [semantically similar]
  ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png → web/icons/Icon-512.png
- `id_animate Project Overview` --conceptually_related_to--> `id_animate Package Definition`  [INFERRED]
  README.md → pubspec.yaml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Flutter Project Scaffold** — readme_project_overview, pubspec_id_animate_package, web_index_flutter_web_entry, analysis_options_analyzer_config, ios_runner_assets_xcassets_launchimage_imageset_readme_launch_screen_assets [INFERRED 0.85]
- **Runtime Dependency Set** — pubspec_cupertino_icons, pubspec_shared_preferences, pubspec_file_picker, pubspec_archive, pubspec_flutter_colorpicker [INFERRED 0.85]

## Communities (42 total, 8 thin omitted)

### Community 0 - "Editor State & History"
Cohesion: 0.02
Nodes (90): ../../core/models/figure_animation.dart, dart:async, double get, Figure get, activeTool, _applyAnimationAt, applyPose, autoEasing (+82 more)

### Community 1 - "Canvas Drawing Widget"
Cohesion: 0.02
Nodes (89): int?, active, anchorX, anchorY, _beginPinch, build, c, _canvasSize (+81 more)

### Community 2 - "Main Menu & Groups UI"
Cohesion: 0.03
Nodes (75): ../core/project_io.dart, ../core/scene/predefined_projects.dart, int get, _activeGroup, _addGroupButton, _addGroupPress, app, _appBar (+67 more)

### Community 3 - "Project Storage & Persistence"
Cohesion: 0.03
Nodes (59): animation, _cachedGroups, _cachedIndexList, cleaned, clearAllData, clone, copyProject, createdAt (+51 more)

### Community 4 - "Segment Data Model"
Cohesion: 0.04
Nodes (47): bool get, dart:ui, double?, a, b, clone, color, colorToHex (+39 more)

### Community 5 - "Theme & Color Picker"
Cohesion: 0.05
Nodes (39): AppPalette get, accentPalette, appColors, AppColorsX, applyBrightness, AppPalette, background, backgroundElement (+31 more)

### Community 6 - "Project Import/Export"
Cohesion: 0.05
Nodes (38): Archive, anim, animationFile, animStr, archive, assets, bytes, data (+30 more)

### Community 7 - "Figure Data Model"
Cohesion: 0.05
Nodes (37): addPoint, addSegment, animations, canvasColor, canvasHeight, canvasWidth, childPoints, clone (+29 more)

### Community 8 - "Segment Inspector Panel"
Cohesion: 0.06
Nodes (32): FocusNode, _angleController, _angleFocus, build, _change, child, controller, createState (+24 more)

### Community 9 - "Editor Screen Shell"
Cohesion: 0.06
Nodes (31): frames_screen.dart, GlobalKey, Segment, ProjectMeta, build, _buildDrawer, controller, createState (+23 more)

### Community 10 - "Animation Keyframe Model"
Cohesion: 0.07
Nodes (27): figure.dart, json_utils.dart, addKeyframe, addTrack, applyToFigure, clone, duration, exportToJson (+19 more)

### Community 11 - "iOS App Delegates"
Cohesion: 0.11
Nodes (14): Any, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterSceneDelegate, AppDelegate, Bool (+6 more)

### Community 12 - "Frames Timeline Screen"
Cohesion: 0.11
Nodes (18): EditorController get, build, c, _cache, _cell, controller, createState, FramesScreen (+10 more)

### Community 13 - "Project Scaffold & Config"
Cohesion: 0.14
Nodes (18): Dart Analyzer Configuration, flutter_lints Lint Set, iOS Launch Screen Assets, archive, Cupertino Icons, Dart SDK Environment, file_picker, flutter_colorpicker (+10 more)

### Community 14 - "Figure Preview Rendering"
Cohesion: 0.11
Nodes (17): ../core/models/figure.dart, CustomPainter, dart:math, Figure, FigureCanvasPainter, bgOuter, build, figure (+9 more)

### Community 15 - "Editor Buttons"
Cohesion: 0.12
Nodes (16): BorderRadius, Color?, EdgeInsetsGeometry, IconData, active, borderRadius, build, child (+8 more)

### Community 16 - "App Entry & Navigation"
Cohesion: 0.12
Nodes (16): Brightness, app, brightness, build, _closeEditor, createState, _editor, IdAnimateApp (+8 more)

### Community 17 - "Animation Settings Panel"
Cohesion: 0.12
Nodes (16): ../color_picker_sheet.dart, ../../core/models/segment.dart, AnimationSettingsPanel, _AnimationSettingsPanelState, build, _changeFps, controller, createState (+8 more)

### Community 18 - "Screen Stateful Widgets"
Cohesion: 0.20
Nodes (14): Root, _RootState, EditorScreen, _EditorScreenState, _GroupCardTile, _GroupCardTileState, MainMenuScreen, _MainMenuScreenState (+6 more)

### Community 19 - "Sheet & Dialog Widgets"
Cohesion: 0.14
Nodes (14): _AddFigureSheet, _LineCapButton, _MenuItem, _FrameMenuSheet, _ConfirmSheet, _MenuSheet, _ProfileSheet, _SortSheet (+6 more)

### Community 20 - "Predefined Projects"
Cohesion: 0.17
Nodes (11): all, bounceAnimationJson, bounceFigureJson, defaultGroup, getPredefinedGroups, importPredefinedProjects, PredefinedProjects, resetAllProjectData (+3 more)

### Community 21 - "App Settings Controller"
Cohesion: 0.18
Nodes (10): ../core/project_storage.dart, brightness, isDark, load, _profileName, reset, setProfileName, setThemeMode (+2 more)

### Community 22 - "Web Manifest Config"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 23 - "Import/Export Tests"
Cohesion: 0.22
Nodes (8): dart:typed_data, Exception, package:archive/archive.dart, package:id_animate/core/project_io.dart, package:id_animate/core/project_storage.dart, package:shared_preferences/shared_preferences.dart, figureJson, main

### Community 24 - "Animation Transport Controls"
Cohesion: 0.25
Nodes (7): editor_buttons.dart, AnimationTransport, build, controller, package:flutter/material.dart, ../../state/editor_controller.dart, ../../theme/app_theme.dart

### Community 25 - "JSON Utilities"
Cohesion: 0.33
Nodes (5): dart:convert, convert, encoder, jsonDecodeSafe, jsonEncodePretty

### Community 26 - "Model Roundtrip Tests"
Cohesion: 0.33
Nodes (5): package:flutter_test/flutter_test.dart, package:id_animate/core/models/figure_animation.dart, package:id_animate/core/models/figure.dart, package:id_animate/core/models/segment.dart, main

### Community 27 - "App Icons (All Platforms)"
Cohesion: 0.67
Nodes (4): Android App Icon (Flutter Default), iOS App Icon (Flutter Default), iOS Launch Image (Blank White Splash Screen), Web PWA Icon (Flutter Default)

### Community 28 - "OpenCode Config"
Cohesion: 0.50
Nodes (3): plugin, $schema, .opencode/plugins/graphify.js

### Community 30 - "ChangeNotifier Controllers"
Cohesion: 0.67
Nodes (3): ChangeNotifier, AppController, EditorController

## Knowledge Gaps
- **613 isolated node(s):** `$schema`, `.opencode/plugins/graphify.js`, `XCTest`, `encoder`, `jsonDecodeSafe` (+608 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `EditorController` connect `ChangeNotifier Controllers` to `Editor State & History`, `Canvas Drawing Widget`, `Segment Inspector Panel`, `Editor Screen Shell`, `Frames Timeline Screen`, `App Entry & Navigation`, `Animation Settings Panel`, `Animation Transport Controls`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Why does `ProjectMeta` connect `Editor Screen Shell` to `Main Menu & Groups UI`, `Project Storage & Persistence`, `Project Import/Export`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **Why does `ProjectType` connect `Project Import/Export` to `Main Menu & Groups UI`, `Project Storage & Persistence`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `id_animate Package Definition` (e.g. with `iOS Launch Screen Assets` and `id_animate Project Overview`) actually correct?**
  _`id_animate Package Definition` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `$schema`, `.opencode/plugins/graphify.js`, `XCTest` to the rest of the system?**
  _613 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Editor State & History` be split into smaller, more focused modules?**
  _Cohesion score 0.02197802197802198 - nodes in this community are weakly interconnected._
- **Should `Canvas Drawing Widget` be split into smaller, more focused modules?**
  _Cohesion score 0.022222222222222223 - nodes in this community are weakly interconnected._