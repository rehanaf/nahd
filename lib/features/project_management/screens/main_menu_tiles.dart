part of 'main_menu_screen.dart';

// =========================================================================
// Project & group tiles
// =========================================================================
class _ProjectCardTile extends StatefulWidget {
  final AppPalette palette;
  final ProjectMeta meta;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  const _ProjectCardTile({
    required this.palette,
    required this.meta,
    required this.onOpen,
    required this.onMenu,
  });

  @override
  State<_ProjectCardTile> createState() => _ProjectCardTileState();
}

class _ProjectCardTileState extends State<_ProjectCardTile> {
  Figure? _figure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ProjectStorage.loadProjectData(widget.meta.id);
      if (!mounted) return;
      setState(() => _figure = figureFromProjectData(data?.figure));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final meta = widget.meta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.backgroundElement,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.backgroundSelected),
                  ),
                  child: FigurePreview(figure: _figure),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: widget.onMenu,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0x66000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_vert,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                meta.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupCardTile extends StatefulWidget {
  final AppPalette palette;
  final String label;
  final int count;
  final List<ProjectMeta> members;
  final VoidCallback onOpen;
  final VoidCallback? onMenu;

  const _GroupCardTile({
    required this.palette,
    required this.label,
    required this.count,
    required this.members,
    required this.onOpen,
    this.onMenu,
  });

  @override
  State<_GroupCardTile> createState() => _GroupCardTileState();
}

class _GroupCardTileState extends State<_GroupCardTile> {
  final List<Figure?> _previews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final metas = widget.members.take(4).toList();
    for (final m in metas) {
      try {
        final data = await ProjectStorage.loadProjectData(m.id);
        if (!mounted) return;
        setState(() {
          if (_previews.length < 4) {
            _previews.add(figureFromProjectData(data?.figure));
          }
        });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.backgroundElement,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.backgroundSelected),
                  ),
                  child: _previews.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 26,
                                color: palette.textSecondary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.count} '
                                '${widget.count == 1 ? 'project' : 'projects'}',
                                style: TextStyle(
                                    color: palette.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(4),
                          child: GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 2,
                            crossAxisSpacing: 2,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (var i = 0; i < 4; i++)
                                if (i < _previews.length)
                                  FigurePreview(figure: _previews[i])
                                else
                                  const ColoredBox(color: Colors.white),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            if (widget.onMenu != null)
              Positioned(
                top: 0,
                right: 0,
                child: InkWell(
                  onTap: widget.onMenu,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0x66000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
