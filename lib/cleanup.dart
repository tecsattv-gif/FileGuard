import 'dart:io';

import 'package:flutter/material.dart';

import 'actions.dart';
import 'browser.dart';
import 'fs.dart';
import 'home.dart';
import 'native.dart';
import 'prefs.dart';
import 'scan.dart';
import 'theme.dart';

/// Limpeza: espaço por tipo, arquivos grandes, duplicados, APKs, pastas
/// vazias e Lixeira. O que se apaga aqui sai de vez (para liberar espaço).
class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key});

  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage> {
  bool _running = false;
  int _trashBytes = 0, _trashCount = 0;

  ScanResult? get _r => Scanner.last;

  @override
  void initState() {
    super.initState();
    _trash();
  }

  Future<void> _trash() async {
    await Native.volumes();
    final l = await listTrash(Native.roots);
    var b = 0;
    for (final t in l) {
      b += t.isDir ? (await dirStats(t.stored)).bytes : t.size;
    }
    if (mounted) {
      setState(() {
        _trashBytes = b;
        _trashCount = l.length;
      });
    }
  }

  Future<void> _scan() async {
    setState(() => _running = true);
    try {
      await Native.volumes();
      await Scanner.run(Native.roots, hidden: Prefs.showHidden);
    } catch (e) {
      if (mounted) snack(context, 'Erro na análise: $e');
    }
    await _trash();
    if (mounted) setState(() => _running = false);
  }

  void _push(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
    _trash();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Limpeza')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                r == null
                    ? 'Analise o armazenamento para ver o que ocupa espaço.'
                    : 'Última análise: ${fmtDate(r.when)}  ·  ${fmtSize(r.total)} em arquivos',
                style: const TextStyle(color: TG.muted),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _running ? null : _scan,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar_rounded),
                  label: Text(_running
                      ? 'Analisando… (pode levar 1 minuto)'
                      : (r == null ? 'Analisar armazenamento' : 'Analisar de novo')),
                ),
              ),
            ]),
          ),
          if (r != null) ...[
            const SectionTitle('ESPAÇO POR TIPO'),
            FCard(child: _byKind(r)),
            const SectionTitle('O QUE DÁ PARA LIMPAR'),
            _tile(
              Icons.photo_size_select_large_rounded,
              'Arquivos grandes',
              '${r.big.length} arquivos com mais de ${fmtSize(bigLimit)}  ·  ${fmtSize(_sum(r.big))}',
              () => _push(PickList(
                  title: 'Arquivos grandes', files: r.big, showSizeFirst: true)),
            ),
            _tile(
              Icons.difference_rounded,
              'Duplicados',
              'Arquivos iguais em mais de um lugar',
              () => _push(const DuplicatesPage()),
            ),
            _tile(
              Icons.android_rounded,
              'APKs',
              '${r.of(Kind.apk).length} instaladores  ·  ${fmtSize(_sum(r.of(Kind.apk)))}',
              () => _push(PickList(title: 'APKs', files: r.of(Kind.apk))),
            ),
            _tile(
              Icons.folder_off_rounded,
              'Pastas vazias',
              '${r.emptyDirs.length} pastas',
              () => _push(EmptyDirsPage(dirs: r.emptyDirs)),
            ),
          ],
          const SectionTitle('LIXEIRA'),
          _tile(
            Icons.delete_sweep_rounded,
            'Lixeira',
            _trashCount == 0
                ? 'Vazia'
                : '$_trashCount itens  ·  ${fmtSize(_trashBytes)} que podem ser liberados',
            () => _push(const TrashPage()),
          ),
        ],
      ),
    );
  }

  static int _sum(List<FileInfo> l) => l.fold(0, (a, f) => a + f.size);

  Widget _tile(IconData ic, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: ListTile(
            leading: Icon(ic, color: TG.accent),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(sub, style: const TextStyle(color: TG.muted, fontSize: 12.5)),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      );

  Widget _byKind(ScanResult r) {
    final kinds = r.bytes.keys.toList()
      ..sort((a, b) => (r.bytes[b] ?? 0).compareTo(r.bytes[a] ?? 0));
    final max = kinds.isEmpty ? 1 : (r.bytes[kinds.first] ?? 1);
    return Column(children: [
      for (final k in kinds)
        InkWell(
          onTap: () => _push(CategoryPage(kind: k)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              KindIcon(k, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(TG.label(k))),
                    Text(fmtSize(r.bytes[k] ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  UsageBar((r.bytes[k] ?? 0) / (max == 0 ? 1 : max), color: TG.color(k)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Apaga de vez (limpeza = liberar espaço; a Lixeira não liberaria).
Future<bool> deleteForeverConfirm(BuildContext context, List<String> paths, int bytes) async {
  final ok = await confirm(
    context,
    'Apagar de vez?',
    '${paths.length} ${paths.length == 1 ? 'item' : 'itens'} (${fmtSize(bytes)}) serão apagados para sempre, sem passar pela Lixeira.',
    ok: 'Apagar',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  final detail = ValueNotifier<String>('');
  final r = await busy(context, 'Apagando…', () async {
    for (final p in paths) {
      detail.value = baseName(p);
      await deleteForever(p);
    }
    return true;
  }, detail: detail);
  Native.mediaScan(paths);
  if (r == true && context.mounted) snack(context, '${fmtSize(bytes)} liberados.');
  return r == true;
}

/// Lista com caixas de seleção e botão "Apagar".
class PickList extends StatefulWidget {
  final String title;
  final List<FileInfo> files;
  final bool showSizeFirst;
  const PickList(
      {super.key, required this.title, required this.files, this.showSizeFirst = false});

  @override
  State<PickList> createState() => _PickListState();
}

class _PickListState extends State<PickList> {
  late List<FileInfo> _files =
      widget.files.where((f) => File(f.path).existsSync()).toList();
  final _sel = <String>{};

  int get _selBytes =>
      _files.where((f) => _sel.contains(f.path)).fold(0, (a, f) => a + f.size);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (_sel.length == _files.length) {
                _sel.clear();
              } else {
                _sel.addAll(_files.map((f) => f.path));
              }
            }),
            child: Text(_sel.length == _files.length && _files.isNotEmpty
                ? 'Nenhum'
                : 'Todos'),
          ),
        ],
      ),
      body: _files.isEmpty
          ? const Center(child: Text('Nada aqui.', style: TextStyle(color: TG.muted)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: _files.length,
              itemBuilder: (_, i) {
                final f = _files[i];
                return CheckboxListTile(
                  value: _sel.contains(f.path),
                  onChanged: (v) => setState(
                      () => v == true ? _sel.add(f.path) : _sel.remove(f.path)),
                  secondary: GestureDetector(
                    onTap: () => openFile(context, f.path),
                    child: FileThumb(Entry(f.path, false, f.size, f.modified)),
                  ),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${fmtSize(f.size)}  ·  ${parentOf(f.path).replaceFirst(Native.internal, '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: TG.muted, fontSize: 12)),
                );
              },
            ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: TG.danger,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(50)),
                  onPressed: () async {
                    final paths = _sel.toList();
                    if (await deleteForeverConfirm(context, paths, _selBytes)) {
                      setState(() {
                        _files.removeWhere((f) => paths.contains(f.path));
                        _sel.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: Text('Apagar ${_sel.length} (${fmtSize(_selBytes)})'),
                ),
              ),
            ),
    );
  }
}

/// Grupos de arquivos iguais. "Selecionar cópias" marca todos menos o
/// mais antigo de cada grupo.
class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  List<List<FileInfo>>? _groups;
  final _sel = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = Scanner.last;
    if (r == null) return;
    final all = <FileInfo>[for (final l in r.files.values) ...l];
    final g = await Scanner.duplicates(all);
    if (mounted) setState(() => _groups = g);
  }

  int get _selBytes {
    var b = 0;
    for (final g in _groups ?? const <List<FileInfo>>[]) {
      for (final f in g) {
        if (_sel.contains(f.path)) b += f.size;
      }
    }
    return b;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final waste = groups?.fold<int>(0, (a, g) => a + g.first.size * (g.length - 1)) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicados'),
        actions: [
          if (groups != null && groups.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _sel.clear();
                for (final g in groups) {
                  _sel.addAll(g.skip(1).map((f) => f.path));
                }
              }),
              child: const Text('Selecionar cópias'),
            ),
        ],
      ),
      body: groups == null
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Comparando arquivos…', style: TextStyle(color: TG.muted)),
            ]))
          : groups.isEmpty
              ? const Center(
                  child: Text('Nenhum arquivo duplicado.', style: TextStyle(color: TG.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: groups.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                        child: Text(
                            '${groups.length} grupos  ·  ${fmtSize(waste)} ocupados por cópias',
                            style: const TextStyle(color: TG.muted)),
                      );
                    }
                    final g = groups[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(children: [
                          for (var j = 0; j < g.length; j++)
                            CheckboxListTile(
                              dense: true,
                              value: _sel.contains(g[j].path),
                              onChanged: (v) => setState(() => v == true
                                  ? _sel.add(g[j].path)
                                  : _sel.remove(g[j].path)),
                              secondary: GestureDetector(
                                onTap: () => openFile(context, g[j].path),
                                child: FileThumb(Entry(g[j].path, false, g[j].size, g[j].modified),
                                    size: 40),
                              ),
                              title: Text(g[j].name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${j == 0 ? 'mais antigo  ·  ' : ''}${fmtSize(g[j].size)}  ·  ${parentOf(g[j].path).replaceFirst(Native.internal, '')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: TG.muted, fontSize: 12)),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: TG.danger,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(50)),
                  onPressed: () async {
                    final paths = _sel.toList();
                    // Segurança: nunca apagar todas as cópias de um grupo.
                    for (final g in groups ?? const <List<FileInfo>>[]) {
                      if (g.every((f) => _sel.contains(f.path))) {
                        snack(context,
                            'Deixe pelo menos um arquivo de cada grupo (${g.first.name}).');
                        return;
                      }
                    }
                    if (await deleteForeverConfirm(context, paths, _selBytes)) {
                      setState(() {
                        for (final g in _groups!) {
                          g.removeWhere((f) => paths.contains(f.path));
                        }
                        _groups!.removeWhere((g) => g.length < 2);
                        _sel.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: Text('Apagar ${_sel.length} (${fmtSize(_selBytes)})'),
                ),
              ),
            ),
    );
  }
}

class EmptyDirsPage extends StatefulWidget {
  final List<String> dirs;
  const EmptyDirsPage({super.key, required this.dirs});

  @override
  State<EmptyDirsPage> createState() => _EmptyDirsPageState();
}

class _EmptyDirsPageState extends State<EmptyDirsPage> {
  late final List<String> _dirs = widget.dirs.where((d) {
    try {
      return Directory(d).listSync().isEmpty;
    } catch (_) {
      return false;
    }
  }).toList();
  late final Set<String> _sel = {..._dirs};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pastas vazias')),
      body: _dirs.isEmpty
          ? const Center(child: Text('Nenhuma pasta vazia.', style: TextStyle(color: TG.muted)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                for (final d in _dirs)
                  CheckboxListTile(
                    value: _sel.contains(d),
                    onChanged: (v) =>
                        setState(() => v == true ? _sel.add(d) : _sel.remove(d)),
                    secondary: const KindIcon(Kind.folder, size: 40),
                    title: Text(baseName(d)),
                    subtitle: Text(parentOf(d).replaceFirst(Native.internal, ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: TG.muted, fontSize: 12)),
                  ),
              ],
            ),
      bottomNavigationBar: _sel.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () async {
                    final paths = _sel.toList();
                    if (await deleteForeverConfirm(context, paths, 0)) {
                      setState(() {
                        _dirs.removeWhere(paths.contains);
                        _sel.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: Text('Apagar ${_sel.length} pastas vazias'),
                ),
              ),
            ),
    );
  }
}

/// Abre a pasta de um arquivo (usado por outras telas).
void openContainingFolder(BuildContext context, String path) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BrowserPage(start: parentOf(path))));
}
