import 'dart:io';

import 'package:flutter/material.dart';

import 'fs.dart';
import 'native.dart';
import 'prefs.dart';
import 'scan.dart';
import 'theme.dart';
import 'viewer.dart';

/// Ações usadas em várias telas (abrir, apagar, compactar, colar…).

/// Área de transferência do app (Copiar / Mover).
class FileClip {
  static final items = ValueNotifier<List<String>>(const []);
  static bool cut = false;

  static void set(List<String> paths, {required bool move}) {
    cut = move;
    items.value = List.unmodifiable(paths);
  }

  static void clear() => items.value = const [];
}

/// Abre o arquivo no visualizador certo. [siblings] = os outros arquivos
/// da mesma pasta (para passar as fotos de lado).
Future<void> openFile(BuildContext context, String path,
    {List<String> siblings = const [], VoidCallback? changed}) async {
  final k = kindOfFile(path);
  Widget? page;
  switch (k) {
    case Kind.image:
      final imgs = siblings.where((p) => kindOfFile(p) == Kind.image).toList();
      if (!imgs.contains(path)) imgs.insert(0, path);
      page = ImageViewer(images: imgs, initial: imgs.indexOf(path));
      break;
    case Kind.video:
    case Kind.audio:
      page = MediaViewer(path: path);
      break;
    case Kind.text:
      page = TextViewer(path: path);
      break;
    case Kind.pdf:
      page = PdfViewer(path: path);
      break;
    case Kind.archive:
      await archiveMenu(context, path, changed: changed);
      return;
    default:
      // APK abre o instalador; Word, Excel etc. abrem no app do telefone.
      await openWithOtherApp(context, path);
      return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
  changed?.call();
}

Future<void> archiveMenu(BuildContext context, String path,
    {VoidCallback? changed}) async {
  final canExtract = extractable.contains(extOf(path));
  final r = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const KindIcon(Kind.archive, size: 40),
          title: Text(baseName(path)),
        ),
        if (canExtract) ...[
          ListTile(
            leading: const Icon(Icons.unarchive_rounded),
            title: Text('Extrair para a pasta "${baseName(extractTarget(path))}"'),
            onTap: () => Navigator.pop(ctx, 'folder'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_folder_upload_rounded),
            title: const Text('Extrair aqui'),
            onTap: () => Navigator.pop(ctx, 'here'),
          ),
        ] else
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('O FileGuard não extrai .rar e .7z'),
            subtitle: Text('Use "Abrir com outro app".'),
          ),
        ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
          title: const Text('Abrir com outro app'),
          onTap: () => Navigator.pop(ctx, 'other'),
        ),
      ]),
    ),
  );
  if (r == null || !context.mounted) return;
  if (r == 'other') return openWithOtherApp(context, path);
  final out = r == 'folder' ? extractTarget(path) : parentOf(path);
  final ok = await busy(context, 'Extraindo…', () async {
    await extractArchive(path, out);
    return true;
  });
  if (ok == true && context.mounted) {
    snack(context, 'Extraído em ${baseName(out)}.');
    Native.mediaScan([out]);
    changed?.call();
  }
}

/// Apaga (para a Lixeira, com DESFAZER por 8 s, ou de vez).
Future<bool> deletePaths(BuildContext context, List<String> paths,
    {VoidCallback? changed}) async {
  if (paths.isEmpty) return false;
  final what = paths.length == 1 ? '"${baseName(paths.first)}"' : '${paths.length} itens';
  final trash = Prefs.useTrash;
  final ok = await confirm(
    context,
    trash ? 'Mandar para a Lixeira?' : 'Apagar de vez?',
    trash
        ? '$what vai para a Lixeira. Você pode restaurar em até $trashDays dias.'
        : '$what será apagado para sempre. Não dá para desfazer.',
    ok: trash ? 'Lixeira' : 'Apagar',
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  final moved = <TrashItem>[];
  final detail = ValueNotifier<String>('');
  final done = await busy(context, trash ? 'Mandando para a Lixeira…' : 'Apagando…',
      () async {
    for (final p in paths) {
      detail.value = baseName(p);
      if (trash) {
        moved.add(await moveToTrash(p, Native.roots));
      } else {
        await deleteForever(p);
      }
    }
    return true;
  }, detail: detail);
  Native.mediaScan(paths);
  changed?.call();
  if (done == true && context.mounted) {
    if (trash) {
      snack(context, '$what na Lixeira.', actionLabel: 'DESFAZER', seconds: 8,
          action: () async {
        for (final t in moved) {
          try {
            await restoreFromTrash(t);
          } catch (_) {}
        }
        Native.mediaScan(paths);
        changed?.call();
      });
    } else {
      snack(context, '$what apagado.');
    }
  }
  return done == true;
}

Future<void> renamePath(BuildContext context, String path,
    {VoidCallback? changed}) async {
  final n = await askName(context, 'Renomear', initial: baseName(path), ok: 'Renomear');
  if (n == null || n == baseName(path) || !context.mounted) return;
  final target = '${parentOf(path)}/$n';
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
      FileSystemEntityType.notFound) {
    snack(context, 'Já existe um item com esse nome.');
    return;
  }
  await busy(context, 'Renomeando…', () => moveTo(path, target));
  Native.mediaScan([path, target]);
  if (Prefs.favorites.contains(path)) {
    Prefs.favorites[Prefs.favorites.indexOf(path)] = target;
    await Prefs.save();
  }
  changed?.call();
}

Future<void> newFolder(BuildContext context, String dir,
    {VoidCallback? changed}) async {
  final n = await askName(context, 'Nova pasta', ok: 'Criar');
  if (n == null || !context.mounted) return;
  final p = '$dir/$n';
  if (FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound) {
    snack(context, 'Já existe um item com esse nome.');
    return;
  }
  await busy(context, 'Criando pasta…', () => Directory(p).create());
  changed?.call();
}

Future<void> compressPaths(BuildContext context, List<String> paths,
    {VoidCallback? changed}) async {
  if (paths.isEmpty) return;
  final dir = parentOf(paths.first);
  final suggestion =
      paths.length == 1 ? '${baseName(paths.first).split('.').first}.zip' : 'arquivos.zip';
  var n = await askName(context, 'Compactar em ZIP',
      initial: suggestion, ok: 'Compactar');
  if (n == null || !context.mounted) return;
  if (!n.toLowerCase().endsWith('.zip')) n = '$n.zip';
  final out = uniquePath(dir, n);
  final r = await busy(context, 'Compactando…', () => zipPaths(paths, out));
  if (r != null && context.mounted) {
    final size = File(r).existsSync() ? fmtSize(File(r).lengthSync()) : '';
    snack(context, '${baseName(r)} criado ($size).');
    changed?.call();
  }
}

/// Cola o que está em [Clip] dentro de [dir].
Future<void> pasteInto(BuildContext context, String dir,
    {VoidCallback? changed}) async {
  final items = FileClip.items.value;
  if (items.isEmpty) return;
  final move = FileClip.cut;
  final detail = ValueNotifier<String>('');
  final ok = await busy(context, move ? 'Movendo…' : 'Copiando…', () async {
    final created = <String>[];
    for (final p in items) {
      detail.value = baseName(p);
      if (move) {
        created.add(await moveInto(p, dir, onFile: (n) => detail.value = n));
      } else {
        created.add(await copyInto(p, dir, onFile: (n) => detail.value = n));
      }
    }
    Native.mediaScan([...items, ...created]);
    return true;
  }, detail: detail);
  if (ok == true) {
    if (move) FileClip.clear();
    if (context.mounted) {
      snack(context, '${items.length} ${items.length == 1 ? 'item' : 'itens'} ${move ? 'movido(s)' : 'copiado(s)'}.');
    }
  }
  changed?.call();
}

/// Propriedades: tamanho (com pastas somadas), data, caminho.
Future<void> showProperties(BuildContext context, List<String> paths) async {
  final st = <String, FileStat>{};
  for (final p in paths) {
    st[p] = await FileStat.stat(p);
  }
  if (!context.mounted) return;
  final single = paths.length == 1 ? paths.first : null;
  final future = () async {
    var bytes = 0, files = 0, folders = 0;
    for (final p in paths) {
      if (st[p]!.type == FileSystemEntityType.directory) {
        final d = await dirStats(p);
        bytes += d.bytes;
        files += d.files;
        folders += d.folders + 1;
      } else {
        bytes += st[p]!.size;
        files++;
      }
    }
    return DirStats(bytes, files, folders);
  }();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: FutureBuilder<DirStats>(
          future: future,
          builder: (_, s) {
            Widget row(String a, String b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 110,
                        child: Text(a, style: const TextStyle(color: TG.muted))),
                    Expanded(child: SelectableText(b)),
                  ]),
                );
            final d = s.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(single != null ? baseName(single) : '${paths.length} itens',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                row('Tamanho',
                    d == null ? 'calculando…' : '${fmtSize(d.bytes)} (${d.bytes} bytes)'),
                if (d != null && (d.folders > 0 || paths.length > 1))
                  row('Conteúdo', '${d.files} arquivos, ${d.folders} pastas'),
                if (single != null) ...[
                  row('Tipo', st[single]!.type == FileSystemEntityType.directory
                      ? 'Pasta'
                      : '${TG.label(kindOfFile(single))} (.${extOf(single)})'),
                  row('Modificado', fmtDate(st[single]!.modified)),
                  row('Local', parentOf(single)),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
