import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/project_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/editor/controllers/editor_controller.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/project_management/controllers/app_controller.dart';
import 'features/project_management/screens/main_menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final app = await AppController.load();
  runApp(IdAnimateApp(app: app));
}

class IdAnimateApp extends StatelessWidget {
  final AppController app;

  const IdAnimateApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final themeMode = app.themeMode;
        final brightness = app.brightness(context);
        return MaterialApp(
          title: "I'd Animate",
          debugShowCheckedModeBanner: false,
          themeMode: themeMode == 'light'
              ? ThemeMode.light
              : themeMode == 'dark'
                  ? ThemeMode.dark
                  : ThemeMode.system,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          home: Root(app: app, brightness: brightness),
        );
      },
    );
  }
}

class Root extends StatefulWidget {
  final AppController app;
  final Brightness brightness;

  const Root({super.key, required this.app, required this.brightness});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  EditorController? _editor;
  bool _loadingEditor = false;
  ProjectType _lastTab = ProjectType.animation;

  Future<void> _openProject(String id, ProjectType type) async {
    setState(() => _loadingEditor = true);
    final controller = await EditorController.load(
      mode: type == ProjectType.figure ? EditorMode.figure : EditorMode.animate,
      projectId: id,
    );
    if (!mounted) return;
    setState(() {
      _loadingEditor = false;
      _editor = controller;
    });
  }

  void _closeEditor() {
    final editor = _editor;
    setState(() => _editor = null);
    if (editor != null) {
      editor.disposeSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (_loadingEditor) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (editor != null) {
      return EditorScreen(controller: editor, onBack: _closeEditor);
    }
    return MainMenuScreen(
      app: widget.app,
      onOpenProject: _openProject,
      initialTab: _lastTab,
      onTabChanged: (t) => _lastTab = t,
    );
  }
}
