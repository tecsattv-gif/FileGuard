import 'dart:io';

import 'package:flutter/material.dart';

import 'actions.dart';
import 'browser.dart';
import 'fs.dart';
import 'native.dart';
import 'prefs.dart';
import 'scan.dart';
import 'theme.dart';
import 'viewer.dart';

/// Tela Início: permissão, armazenamentos, atalhos, categorias e favoritos.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool? _access;
  List<Volume> _volumes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Prefs.changed.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Prefs.changed.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Voltou da tela de permissão do Android: confere de novo.
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final a = await Native.hasAccess();
    final v = await Native.volumes();
    if (mounted) {
      setState(() {
        _access = a;
        _volumes = v;
      });
    }
  }

  void _openFolder(String path, {String? root}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BrowserPage(start: path, root: root)));
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <(String, IconData, String)>[
      ('Downloads', Icons.download_rounded, '${Native.internal}/Download'),
      ('Câmera', Icons.photo_camera_rounded, '${Native.internal}/DCIM/Camera'),
      ('Imagens', Icons.photo_library_rounded, '${Native.internal}/Pictures'),
      ('Documentos', Icons.folder_copy_rounded, '${Native.internal}/Documents'),
      ('Música', Icons.library_music_rounded, '${Native.internal}/Music'),
      ('Filmes', Icons.video_library_rounded, '${Native.internal}/Movies'),
      ('WhatsApp', Icons.chat_rounded,
          '${Native.internal}/Android/media/com.whatsapp/WhatsApp/Media'),
      ('Telegram', Icons.send_rounded, '${Native.internal}/Download/Telegram'),
    ].where((s) => Directory(s.$3).existsSync()).toList();

    const cats = [
      Kind.image, Kind.video, Kind.audio, Kind.pdf, Kind.document,
      Kind.archive, Kind.apk, Kind.text
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('FileGuard')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (_access == false) _accessCard(),
            for (final v in _volumes) ...[
              _volumeCard(v),
              const SizedBox(height: 10),
            ],
            if (shortcuts.isNotEmpty) ...[
              const SectionTitle('ATALHOS'),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in shortcuts)
                    _chip(s.$1, s.$2, () => _openFolder(s.$3, root: Native.internal)),
                ],
              ),
            ],
            const SectionTitle('CATEGORIAS'),
            LayoutBuilder(builder: (_, c) {
              final cols = (c.maxWidth / 90).floor().clamp(4, 8).toInt();
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
                children: [
                  for (final k in cats)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CategoryPage(kind: k))),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          KindIcon(k, size: 50),
                          const SizedBox(height: 6),
                          Text(TG.label(k),
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                ],
              );
            }),
            SectionTitle('FAVORITOS',
                trailing: Prefs.favorites.isEmpty
                    ? null
                    : const Text('toque longo para tirar',
                        style: TextStyle(color: TG.muted, fontSize: 11))),
            if (Prefs.favorites.isEmpty)
              const FCard(
                child: Text(
                    'Para adicionar uma pasta: toque longo nela → Mais → Adicionar aos favoritos.',
                    style: TextStyle(color: TG.muted)),
              )
            else
              FCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final f in Prefs.favorites)
                    ListTile(
                      leading: const KindIcon(Kind.folder, size: 38),
                      title: Text(baseName(f)),
                      subtitle: Text(f.replaceFirst(Native.internal, ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: TG.muted, fontSize: 12)),
                      onTap: () => _openFolder(f),
                      onLongPress: () async {
                        final ok = await confirm(context, 'Tirar dos favoritos?',
                            baseName(f), ok: 'Tirar');
                        if (ok) await Prefs.toggleFavorite(f);
                      },
                    ),
                ]),
              ),
            const SizedBox(height: 10),
            FCard(
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TrashPage())),
              child: const ListTile(
                leading: Icon(Icons.delete_sweep_rounded, color: TG.muted),
                title: Text('Lixeira'),
                subtitle: Text('Itens apagados ficam $trashDays dias',
                    style: TextStyle(color: TG.muted, fontSize: 12)),
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessCard() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.lock_open_rounded, color: TG.warn),
              SizedBox(width: 10),
              Expanded(
                child: Text('Falta liberar o acesso',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
                'Para ver e mexer em todas as pastas do telefone, o Android pede a permissão "Acesso a todos os arquivos". Toque no botão e ligue a chave do FileGuard.',
                style: TextStyle(color: TG.muted)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: Native.requestAccess,
              icon: const Icon(Icons.check_circle_rounded),
              label: const Text('Permitir acesso'),
            ),
          ]),
        ),
      );

  Widget _volumeCard(Volume v) {
    final frac = v.total > 0 ? v.used / v.total : 0.0;
    return FCard(
      onTap: () => _openFolder(v.path, root: v.path),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(v.removable ? Icons.sd_card_rounded : Icons.smartphone_rounded,
              color: TG.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(v.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (v.total > 0)
            Text('${(frac * 100).round()}%',
                style: const TextStyle(color: TG.muted, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        UsageBar(frac),
        const SizedBox(height: 8),
        if (v.total > 0)
          Text('${fmtSize(v.used)} usados de ${fmtSize(v.total)}  ·  ${fmtSize(v.free)} livres',
              style: const TextStyle(color: TG.muted, fontSize: 12.5)),
      ]),
    );
  }

  Widget _chip(String label, IconData icon, VoidCallback onTap) => Material(
        color: TG.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: TG.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: TG.accent),
              const SizedBox(width: 8),
              Text(label),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------- Categoria

/// Todos os arquivos de um tipo (do mais novo para o mais antigo).
class CategoryPage extends StatefulWidget {
  final Kind kind;
  const CategoryPage({super.key, required this.kind});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List<FileInfo>? _files;
  final _sel = <String>{};

  @override
  void initState() {
    super.initState();
    _load(Scanner.last == null);
  }

  Future<void> _load(bool rescan) async {
    if (rescan || Scanner.last == null) {
      if (_files != null) setState(() => _files = null);
      await Native.volumes();
      await Scanner.run(Native.roots, hidden: Prefs.showHidden);
    }
    if (!mounted) return;
    final all = Scanner.last!.of(widget.kind);
    setState(() {
      _files = all.where((f) => File(f.path).existsSync()).toList();
      _sel.removeWhere((p) => !_files!.any((f) => f.path == p));
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final total = files?.fold<int>(0, (a, f) => a + f.size) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_sel.isEmpty ? TG.label(widget.kind) : '${_sel.length} selecionado(s)'),
        actions: [
          if (_sel.isNotEmpty) ...[
            IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.share_rounded),
              onPressed: () => shareFiles(_sel.toList()),
            ),
            IconButton(
              tooltip: 'Apagar',
              icon: const Icon(Icons.delete_outline_rounded, color: TG.danger),
              onPressed: () async {
                await deletePaths(context, _sel.toList(), changed: () => _load(false));
                setState(() => _sel.clear());
              },
            ),
          ] else
            IconButton(
              tooltip: 'Analisar de novo',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _load(true),
            ),
        ],
      ),
      body: files == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Procurando no armazenamento…', style: TextStyle(color: TG.muted)),
            ]))
          : files.isEmpty
              ? const Center(
                  child: Text('Nenhum arquivo deste tipo.',
                      style: TextStyle(color: TG.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: files.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('${files.length} arquivos  ·  ${fmtSize(total)}',
                            style: const TextStyle(color: TG.muted)),
                      );
                    }
                    final f = files[i - 1];
                    final sel = _sel.contains(f.path);
                    final e = Entry(f.path, false, f.size, f.modified);
                    return ListTile(
                      selected: sel,
                      selectedTileColor: TG.accent.withValues(alpha: 0.10),
                      leading: sel
                          ? const CircleAvatar(
                              backgroundColor: TG.accent,
                              child: Icon(Icons.check_rounded, color: Colors.black))
                          : FileThumb(e),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${fmtSize(f.size)}  ·  ${parentOf(f.path).replaceFirst(Native.internal, '')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: TG.muted, fontSize: 12)),
                      onTap: () {
                        if (_sel.isNotEmpty) {
                          setState(() => sel ? _sel.remove(f.path) : _sel.add(f.path));
                        } else {
                          openFile(context, f.path,
                              siblings: widget.kind == Kind.image
                                  ? files.map((x) => x.path).toList()
                                  : const [],
                              changed: () => _load(false));
                        }
                      },
                      onLongPress: () => setState(
                          () => sel ? _sel.remove(f.path) : _sel.add(f.path)),
                    );
                  },
                ),
    );
  }
}

// ---------------------------------------------------------------- Lixeira

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Native.volumes();
    final l = await listTrash(Native.roots);
    if (mounted) setState(() => _items = l);
  }

  Future<void> _empty() async {
    final ok = await confirm(context, 'Esvaziar a Lixeira?',
        'Tudo o que está na Lixeira será apagado para sempre.',
        ok: 'Esvaziar', danger: true);
    if (!ok || !mounted) return;
    await busy(context, 'Esvaziando…', () async {
      for (final t in _items ?? const <TrashItem>[]) {
        await deleteTrashItem(t);
      }
      return true;
    });
    _load();
  }

  Future<void> _itemMenu(TrashItem t) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Estava em ${parentOf(t.original)}',
                style: const TextStyle(color: TG.muted, fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded, color: TG.accent),
            title: const Text('Restaurar'),
            onTap: () => Navigator.pop(ctx, 'restore'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: TG.danger),
            title: const Text('Apagar de vez'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || r == null) return;
    if (r == 'restore') {
      final p = await busy(context, 'Restaurando…', () => restoreFromTrash(t));
      if (p != null) {
        Native.mediaScan([p]);
        if (mounted) snack(context, 'Restaurado em ${parentOf(p)}.');
      }
    } else {
      final ok = await confirm(context, 'Apagar de vez?', t.name, ok: 'Apagar', danger: true);
      if (!ok || !mounted) return;
      await busy(context, 'Apagando…', () async {
        await deleteTrashItem(t);
        return true;
      });
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lixeira'),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton.icon(
              onPressed: _empty,
              icon: const Icon(Icons.delete_forever_rounded, color: TG.danger),
              label: const Text('Esvaziar', style: TextStyle(color: TG.danger)),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Text('A Lixeira está vazia.', style: TextStyle(color: TG.muted)))
              : ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                            'Toque num item para restaurar. Depois de $trashDays dias ele é apagado sozinho.',
                            style: TextStyle(color: TG.muted)),
                      );
                    }
                    final t = items[i - 1];
                    final left = trashDays - DateTime.now().difference(t.deleted).inDays;
                    return ListTile(
                      leading: KindIcon(t.isDir ? Kind.folder : kindOfFile(t.original), size: 40),
                      title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${t.isDir ? 'Pasta' : fmtSize(t.size)}  ·  apagado ${fmtDate(t.deleted)}  ·  ${left < 0 ? 0 : left} dias',
                          style: const TextStyle(color: TG.muted, fontSize: 12)),
                      onTap: () => _itemMenu(t),
                    );
                  },
                ),
    );
  }
}
