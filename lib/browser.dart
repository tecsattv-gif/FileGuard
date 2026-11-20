import 'dart:io';

import 'package:flutter/material.dart';

import 'actions.dart';
import 'fs.dart';
import 'native.dart';
import 'prefs.dart';
import 'scan.dart';
import 'theme.dart';
import 'viewer.dart';

/// Navegador de pastas.
///
/// [root] é o limite do botão Voltar (o armazenamento). Com [pickExt] a
/// tela serve só para escolher um arquivo com essa extensão (restaurar
/// backup) e devolve o caminho.
class BrowserPage extends StatefulWidget {
  final String start;
  final String? root;
  final bool embedded;
  final String? pickExt;
  const BrowserPage(
      {super.key,
      required this.start,
      this.root,
      this.embedded = false,
      this.pickExt});

  @override
  State<BrowserPage> createState() => BrowserPageState();
}

class BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  late String _path = widget.start;
  late final String _root = widget.root ?? _guessRoot(widget.start);
  List<Entry> _items = [];
  bool _loading = true;
  String? _error;
  final _sel = <String>{};
  final _scroll = <String, double>{};
  final _sc = ScrollController();
  bool _searching = false;
  final _q = TextEditingController();
  List<String>? _deep; // resultados da busca em subpastas
  bool _deepLoading = false;

  bool get _picking => widget.pickExt != null;

  static String _guessRoot(String p) {
    for (final r in Native.roots) {
      if (p == r || p.startsWith('$r/')) return r;
    }
    return '/';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Prefs.changed.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Prefs.changed.removeListener(_reload);
    _sc.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _reload();
  }

  void _reload() => _load(keepScroll: true);

  /// Abre uma pasta (usado pela aba Arquivos quando vem de um atalho).
  void go(String path) {
    _scroll[_path] = _sc.hasClients ? _sc.offset : 0.0;
    setState(() {
      _path = path;
      _sel.clear();
      _closeSearch();
    });
    _load();
  }

  Future<void> _load({bool keepScroll = false}) async {
    final want = _path;
    if (!keepScroll && !_loading) setState(() => _loading = true);
    try {
      final l = await listDir(want, hidden: Prefs.showHidden);
      sortEntries(l, Prefs.sortBy, Prefs.sortAsc,
          foldersFirst: Prefs.foldersFirst);
      if (!mounted || want != _path) return;
      setState(() {
        _items = l;
        _error = null;
        _loading = false;
        _sel.removeWhere((p) => !l.any((e) => e.path == p));
      });
      if (!keepScroll) {
        final off = _scroll[want] ?? 0.0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sc.hasClients) {
            _sc.jumpTo(off.clamp(0.0, _sc.position.maxScrollExtent).toDouble());
          }
        });
      }
    } catch (e) {
      final access = await Native.hasAccess();
      if (!mounted || want != _path) return;
      setState(() {
        _items = [];
        _loading = false;
        _error = access
            ? 'Não foi possível abrir esta pasta.'
            : 'Sem permissão. Libere "Acesso a todos os arquivos" na tela Início.';
      });
    }
  }

  bool get _atRoot => _path == _root || _path == '/';

  void _up() {
    if (_atRoot) return;
    final child = _path;
    _scroll.remove(child);
    setState(() {
      _path = parentOf(_path);
      _sel.clear();
    });
    _load();
  }

  void _open(Entry e) {
    if (_sel.isNotEmpty) {
      _toggle(e);
      return;
    }
    if (e.isDir) {
      go(e.path);
      return;
    }
    if (_picking) {
      if (extOf(e.path) == widget.pickExt) {
        Navigator.pop(context, e.path);
      } else {
        snack(context, 'Escolha um arquivo .${widget.pickExt}');
      }
      return;
    }
    openFile(context, e.path,
        siblings: _items.where((x) => !x.isDir).map((x) => x.path).toList(),
        changed: _reload);
  }

  void _toggle(Entry e) {
    if (_picking) return;
    setState(() {
      if (!_sel.remove(e.path)) _sel.add(e.path);
    });
  }

  void _closeSearch() {
    _searching = false;
    _q.clear();
    _deep = null;
    _deepLoading = false;
  }

  Future<void> _deepSearch() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _deepLoading = true);
    final r = await search(_path, q, hidden: Prefs.showHidden);
    if (!mounted) return;
    setState(() {
      _deep = r;
      _deepLoading = false;
    });
  }

  List<Entry> get _visible {
    final q = _q.text.trim().toLowerCase();
    var l = _items;
    if (q.isNotEmpty) {
      l = l.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    if (_picking) {
      l = l.where((e) => e.isDir || extOf(e.path) == widget.pickExt).toList();
    }
    return l;
  }

  // ------------------------------------------------------------ ações

  List<String> get _selected => _sel.toList();

  void _done() => setState(() => _sel.clear());

  Future<void> _sortMenu() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        Widget opt(SortBy s, String label, IconData ic) => ListTile(
              leading: Icon(ic),
              title: Text(label),
              trailing: Prefs.sortBy == s
                  ? Icon(
                      Prefs.sortAsc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: TG.accent)
                  : null,
              onTap: () => Navigator.pop(ctx, s.name),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(
                title: Text('Ordenar por',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            opt(SortBy.name, 'Nome', Icons.sort_by_alpha_rounded),
            opt(SortBy.date, 'Data', Icons.schedule_rounded),
            opt(SortBy.size, 'Tamanho', Icons.data_usage_rounded),
            opt(SortBy.type, 'Tipo', Icons.category_rounded),
            const Divider(),
            SwitchListTile(
              title: const Text('Mostrar arquivos ocultos'),
              value: Prefs.showHidden,
              onChanged: (v) => Navigator.pop(ctx, v ? 'hidden1' : 'hidden0'),
            ),
            SwitchListTile(
              title: const Text('Exibir em grade'),
              value: Prefs.grid,
              onChanged: (v) => Navigator.pop(ctx, v ? 'grid1' : 'grid0'),
            ),
          ]),
        );
      },
    );
    if (r == null) return;
    if (r.startsWith('hidden')) {
      Prefs.showHidden = r == 'hidden1';
    } else if (r.startsWith('grid')) {
      Prefs.grid = r == 'grid1';
    } else {
      final s = SortBy.values.firstWhere((x) => x.name == r);
      if (Prefs.sortBy == s) {
        Prefs.sortAsc = !Prefs.sortAsc;
      } else {
        Prefs.sortBy = s;
        Prefs.sortAsc = s == SortBy.name || s == SortBy.type;
      }
    }
    await Prefs.save();
  }

  Future<void> _more() async {
    final sel = _selected;
    final one = sel.length == 1 ? sel.first : null;
    final oneDir = one != null && FileSystemEntity.isDirectorySync(one);
    final oneArchive = one != null && !oneDir && kindOfFile(one) == Kind.archive;
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        Widget t(String id, IconData ic, String label) => ListTile(
            leading: Icon(ic), title: Text(label), onTap: () => Navigator.pop(ctx, id));
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              t('all', Icons.select_all_rounded, 'Selecionar tudo'),
              if (one != null) t('rename', Icons.drive_file_rename_outline_rounded, 'Renomear'),
              t('zip', Icons.folder_zip_rounded, 'Compactar em ZIP'),
              if (oneArchive) t('extract', Icons.unarchive_rounded, 'Extrair'),
              if (one != null && !oneDir) t('open', Icons.open_in_new_rounded, 'Abrir com outro app'),
              if (oneDir)
                t('fav', Prefs.isFavorite(one!) ? Icons.star_rounded : Icons.star_border_rounded,
                    Prefs.isFavorite(one!) ? 'Tirar dos favoritos' : 'Adicionar aos favoritos'),
              t('info', Icons.info_outline_rounded, 'Propriedades'),
            ]),
          ),
        );
      },
    );
    if (r == null || !mounted) return;
    switch (r) {
      case 'all':
        setState(() => _sel.addAll(_visible.map((e) => e.path)));
        break;
      case 'rename':
        await renamePath(context, one!, changed: _reload);
        _done();
        break;
      case 'zip':
        await compressPaths(context, sel, changed: _reload);
        _done();
        break;
      case 'extract':
        await archiveMenu(context, one!, changed: _reload);
        _done();
        break;
      case 'open':
        await openWithOtherApp(context, one!);
        break;
      case 'fav':
        await Prefs.toggleFavorite(one!);
        if (mounted) {
          snack(context, Prefs.isFavorite(one!) ? 'Adicionado aos favoritos.' : 'Tirado dos favoritos.');
        }
        _done();
        break;
      case 'info':
        await showProperties(context, sel);
        break;
    }
  }

  // ------------------------------------------------------------ tela

  @override
  Widget build(BuildContext context) {
    final selecting = _sel.isNotEmpty;
    final page = Scaffold(
        appBar: selecting ? _selectionBar() : _normalBar(),
        body: Column(children: [
          if (!selecting && !_searching) _breadcrumbs(),
          Expanded(child: _body()),
          ValueListenableBuilder<List<String>>(
            valueListenable: FileClip.items,
            builder: (_, items, __) =>
                items.isEmpty || _picking || selecting ? const SizedBox.shrink() : _pasteBar(items),
          ),
        ]),
        floatingActionButton: selecting || _picking || _searching
            ? null
            : FloatingActionButton(
                tooltip: 'Nova pasta',
                onPressed: () => newFolder(context, _path, changed: _reload),
                child: const Icon(Icons.create_new_folder_rounded),
              ),
        bottomNavigationBar: selecting ? _selectionActions() : null,
      );
    // Na aba Arquivos quem cuida do Voltar é a tela principal (handleBack).
    if (widget.embedded) return page;
    return PopScope(
      canPop: !selecting && !_searching && _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: page,
    );
  }

  /// Botão Voltar: sai da seleção, da busca ou sobe uma pasta.
  /// Devolve false quando não há mais o que voltar.
  bool handleBack() {
    if (_sel.isNotEmpty) {
      _done();
      return true;
    }
    if (_searching) {
      setState(_closeSearch);
      return true;
    }
    if (!_atRoot) {
      _up();
      return true;
    }
    return false;
  }

  PreferredSizeWidget _normalBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(_closeSearch),
        ),
        title: TextField(
          controller: _q,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar nesta pasta',
            isDense: true,
          ),
          onChanged: (_) => setState(() => _deep = null),
          onSubmitted: (_) => _deepSearch(),
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar também nas subpastas',
            icon: const Icon(Icons.manage_search_rounded),
            onPressed: _deepSearch,
          ),
        ],
      );
    }
    final title = _picking
        ? 'Escolha o arquivo .${widget.pickExt}'
        : (_path == _root ? _rootName() : baseName(_path));
    return AppBar(
      automaticallyImplyLeading: !widget.embedded || !_atRoot,
      leading: !_atRoot
          ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _up)
          : null,
      title: Text(title, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Buscar',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _searching = true),
        ),
        IconButton(
          tooltip: 'Ordenar e exibir',
          icon: const Icon(Icons.sort_rounded),
          onPressed: _sortMenu,
        ),
      ],
    );
  }

  String _rootName() {
    if (_root == Native.internal) return 'Armazenamento interno';
    if (_root == '/') return 'Raiz';
    return 'Cartão SD';
  }

  PreferredSizeWidget _selectionBar() => AppBar(
        backgroundColor: TG.surfaceHigh,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _done),
        title: Text('${_sel.length} selecionado${_sel.length == 1 ? '' : 's'}'),
        actions: [
          IconButton(
            tooltip: 'Selecionar tudo',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: () => setState(() => _sel.addAll(_visible.map((e) => e.path))),
          ),
        ],
      );

  Widget _selectionActions() {
    final sel = _selected;
    final hasDir = sel.any((p) => FileSystemEntity.isDirectorySync(p));
    Widget b(IconData ic, String label, VoidCallback onTap, {Color? color}) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(ic, color: color),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color)),
              ]),
            ),
          ),
        );
    return Material(
      color: TG.surface,
      child: SafeArea(
        top: false,
        child: Row(children: [
          b(Icons.copy_rounded, 'Copiar', () {
            FileClip.set(sel, move: false);
            _done();
            snack(context, 'Abra a pasta de destino e toque em Colar.');
          }),
          b(Icons.drive_file_move_rounded, 'Mover', () {
            FileClip.set(sel, move: true);
            _done();
            snack(context, 'Abra a pasta de destino e toque em Colar.');
          }),
          if (!hasDir)
            b(Icons.share_rounded, 'Enviar', () => shareFiles(sel)),
          b(Icons.delete_outline_rounded, 'Apagar', () async {
            await deletePaths(context, sel, changed: _reload);
            _done();
          }, color: TG.danger),
          b(Icons.more_horiz_rounded, 'Mais', _more),
        ]),
      ),
    );
  }

  Widget _pasteBar(List<String> items) => Material(
        color: TG.surfaceHigh,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Icon(FileClip.cut ? Icons.drive_file_move_rounded : Icons.copy_rounded,
                  color: TG.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${FileClip.cut ? 'Mover' : 'Copiar'} ${items.length} ${items.length == 1 ? 'item' : 'itens'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(onPressed: FileClip.clear, child: const Text('Cancelar')),
              FilledButton(
                onPressed: () => pasteInto(context, _path, changed: _reload),
                child: const Text('Colar aqui'),
              ),
            ]),
          ),
        ),
      );

  Widget _breadcrumbs() {
    final parts = <String>[];
    var p = _path;
    while (true) {
      parts.insert(0, p);
      if (p == _root || p == '/') break;
      p = parentOf(p);
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: parts.length,
        separatorBuilder: (_, __) =>
            const Icon(Icons.chevron_right_rounded, size: 18, color: TG.muted),
        itemBuilder: (_, i) {
          final x = parts[parts.length - 1 - i];
          final last = x == _path;
          final label = x == _root ? (x == '/' ? '/' : _rootName()) : baseName(x);
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: last ? null : () => go(x),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(label,
                    style: TextStyle(
                        color: last ? TG.accent : TG.muted,
                        fontWeight: last ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center, style: const TextStyle(color: TG.muted)),
        ),
      );
    }
    if (_deepLoading) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Buscando nas subpastas…', style: TextStyle(color: TG.muted)),
      ]));
    }
    if (_deep != null) return _deepList(_deep!);
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open_rounded, size: 64, color: TG.line),
          const SizedBox(height: 10),
          Text(_q.text.isEmpty ? 'Pasta vazia' : 'Nada com esse nome aqui',
              style: const TextStyle(color: TG.muted)),
          if (_q.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _deepSearch,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('Buscar nas subpastas'),
            ),
          ],
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(keepScroll: true),
      child: Prefs.grid ? _grid(items) : _list(items),
    );
  }

  Widget _list(List<Entry> items) => ListView.builder(
        controller: _sc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final e = items[i];
          final sel = _sel.contains(e.path);
          return ListTile(
            selected: sel,
            selectedTileColor: TG.accent.withValues(alpha: 0.10),
            leading: sel
                ? const CircleAvatar(
                    backgroundColor: TG.accent,
                    child: Icon(Icons.check_rounded, color: Colors.black))
                : FileThumb(e),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              e.isDir ? fmtDate(e.modified) : '${fmtSize(e.size)}  ·  ${fmtDate(e.modified)}',
              style: const TextStyle(color: TG.muted, fontSize: 12),
            ),
            trailing: e.isDir && Prefs.isFavorite(e.path)
                ? const Icon(Icons.star_rounded, color: TG.warn, size: 18)
                : null,
            onTap: () => _open(e),
            onLongPress: () => _toggle(e),
          );
        },
      );

  Widget _grid(List<Entry> items) => LayoutBuilder(builder: (_, c) {
        final cols = (c.maxWidth / 110).floor().clamp(3, 10).toInt();
        return GridView.builder(
          controller: _sc,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols, childAspectRatio: 0.82, mainAxisSpacing: 6, crossAxisSpacing: 6),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final e = items[i];
            final sel = _sel.contains(e.path);
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(e),
              onLongPress: () => _toggle(e),
              child: Container(
                decoration: BoxDecoration(
                  color: sel ? TG.accent.withValues(alpha: 0.15) : null,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? TG.accent : Colors.transparent),
                ),
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Expanded(child: Center(child: FileThumb(e, size: 64))),
                  const SizedBox(height: 4),
                  Text(e.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            );
          },
        );
      });

  Widget _deepList(List<String> paths) {
    if (paths.isEmpty) {
      return const Center(
          child: Text('Nada encontrado nas subpastas.', style: TextStyle(color: TG.muted)));
    }
    return ListView.builder(
      itemCount: paths.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
                '${paths.length}${paths.length >= 500 ? '+' : ''} resultado(s) em ${baseName(_path)} e subpastas',
                style: const TextStyle(color: TG.muted)),
          );
        }
        final p = paths[i - 1];
        final isDir = FileSystemEntity.isDirectorySync(p);
        return ListTile(
          leading: KindIcon(isDir ? Kind.folder : kindOfFile(p), size: 40),
          title: Text(baseName(p), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(parentOf(p).replaceFirst(_root, '').isEmpty ? '/' : parentOf(p).replaceFirst(_root, ''),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: TG.muted, fontSize: 12)),
          onTap: () {
            if (isDir) {
              go(p);
            } else if (_picking) {
              if (extOf(p) == widget.pickExt) Navigator.pop(context, p);
            } else {
              openFile(context, p, changed: _reload);
            }
          },
          onLongPress: isDir || _picking ? null : () => go(parentOf(p)),
        );
      },
    );
  }
}

/// Miniatura: foto de verdade para imagens, ícone para o resto.
class FileThumb extends StatelessWidget {
  final Entry e;
  final double size;
  const FileThumb(this.e, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    if (e.kind == Kind.image) {
      final px = (size * MediaQuery.of(context).devicePixelRatio).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.file(
          File(e.path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: px,
          errorBuilder: (_, __, ___) => KindIcon(Kind.image, size: size),
        ),
      );
    }
    return KindIcon(e.kind, size: size);
  }
}
