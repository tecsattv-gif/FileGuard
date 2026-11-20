import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Funções de arquivos sem nada de tela (usadas também nos testes e nas
/// análises que rodam em segundo plano).

enum Kind { folder, image, video, audio, pdf, text, document, archive, apk, other }

const _image = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
const _video = {'mp4', 'mkv', 'avi', 'mov', '3gp', 'webm', 'm4v', 'ts', 'wmv', 'flv'};
const _audio = {'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus', 'amr', 'wma', 'mid'};
const _text = {
  'txt', 'log', 'csv', 'json', 'xml', 'md', 'ini', 'cfg', 'conf', 'yaml',
  'yml', 'html', 'htm', 'css', 'js', 'dart', 'kt', 'java', 'py', 'sh',
  'srt', 'vtt', 'm3u', 'm3u8', 'pls', 'properties', 'gpx', 'kml'
};
const _doc = {
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf',
  'epub'
};
const _archive = {'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'};

/// Formatos que o app sabe extrair.
const extractable = {'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz'};

String baseName(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}

String parentOf(String path) {
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final i = p.lastIndexOf('/');
  if (i <= 0) return '/';
  return p.substring(0, i);
}

/// Extensão em minúsculas, sem o ponto ("Foto.JPG" → "jpg").
String extOf(String path) {
  final n = baseName(path);
  final i = n.lastIndexOf('.');
  if (i <= 0 || i == n.length - 1) return '';
  return n.substring(i + 1).toLowerCase();
}

Kind kindOfFile(String path) {
  final e = extOf(path);
  if (_image.contains(e)) return Kind.image;
  if (_video.contains(e)) return Kind.video;
  if (_audio.contains(e)) return Kind.audio;
  if (e == 'pdf') return Kind.pdf;
  if (_text.contains(e)) return Kind.text;
  if (_doc.contains(e)) return Kind.document;
  if (_archive.contains(e)) return Kind.archive;
  if (e == 'apk' || e == 'xapk' || e == 'apks') return Kind.apk;
  return Kind.other;
}

/// Tamanho legível em português ("1,5 MB").
String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${units[u]}';
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime d) =>
    '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';

/// Item de uma pasta.
class Entry {
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  const Entry(this.path, this.isDir, this.size, this.modified);

  String get name => baseName(path);
  Kind get kind => isDir ? Kind.folder : kindOfFile(path);
  bool get hidden => name.startsWith('.');
}

enum SortBy { name, date, size, type }

/// Lê uma pasta. Ocultos (nome começando com ".") só se [hidden].
Future<List<Entry>> listDir(String path, {bool hidden = false}) async {
  final out = <Entry>[];
  await for (final e in Directory(path).list(followLinks: false)) {
    final n = baseName(e.path);
    if (!hidden && n.startsWith('.')) continue;
    try {
      final st = await e.stat();
      final isDir = st.type == FileSystemEntityType.directory;
      out.add(Entry(e.path, isDir, isDir ? 0 : st.size, st.modified));
    } catch (_) {}
  }
  return out;
}

void sortEntries(List<Entry> list, SortBy by, bool asc,
    {bool foldersFirst = true}) {
  int cmpName(Entry a, Entry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  list.sort((a, b) {
    if (foldersFirst && a.isDir != b.isDir) return a.isDir ? -1 : 1;
    int r;
    switch (by) {
      case SortBy.name:
        r = cmpName(a, b);
        break;
      case SortBy.date:
        r = a.modified.compareTo(b.modified);
        break;
      case SortBy.size:
        r = a.size.compareTo(b.size);
        break;
      case SortBy.type:
        r = extOf(a.path).compareTo(extOf(b.path));
        if (r == 0) r = cmpName(a, b);
        break;
    }
    return asc ? r : -r;
  });
}

/// "foto.jpg" já existe → "foto (1).jpg", "foto (2).jpg"…
String uniquePath(String dir, String name) {
  var p = '$dir/$name';
  if (FileSystemEntity.typeSync(p, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return p;
  }
  final dot = name.lastIndexOf('.');
  final isFileLike = dot > 0;
  final stem = isFileLike ? name.substring(0, dot) : name;
  final ext = isFileLike ? name.substring(dot) : '';
  for (var i = 1; i < 10000; i++) {
    p = '$dir/$stem ($i)$ext';
    if (FileSystemEntity.typeSync(p, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return p;
    }
  }
  return '$dir/$stem (${DateTime.now().millisecondsSinceEpoch})$ext';
}

bool validName(String n) =>
    n.trim().isNotEmpty &&
    n != '.' &&
    n != '..' &&
    !n.contains('/') &&
    !n.contains('\u0000');

/// Copia arquivo ou pasta (com tudo dentro) para dentro de [destDir].
/// Se já existir um com o mesmo nome, cria "nome (1)". Devolve o novo caminho.
Future<String> copyInto(String src, String destDir,
    {void Function(String name)? onFile}) async {
  final target = uniquePath(destDir, baseName(src));
  await _copy(src, target, onFile);
  return target;
}

Future<void> _copy(
    String src, String target, void Function(String name)? onFile) async {
  final t = await FileSystemEntity.type(src, followLinks: false);
  if (t == FileSystemEntityType.directory) {
    if (target == src || target.startsWith('$src/')) {
      throw const FileSystemException('Não é possível copiar uma pasta para dentro dela mesma');
    }
    await Directory(target).create(recursive: true);
    await for (final e in Directory(src).list(followLinks: false)) {
      await _copy(e.path, '$target/${baseName(e.path)}', onFile);
    }
  } else if (t == FileSystemEntityType.link) {
    final l = await Link(src).target();
    await Link(target).create(l);
  } else {
    onFile?.call(baseName(src));
    await File(src).copy(target);
  }
}

/// Move para dentro de [destDir]. No mesmo armazenamento é instantâneo;
/// entre interno e cartão SD copia e depois apaga o original.
Future<String> moveInto(String src, String destDir,
    {void Function(String name)? onFile}) async {
  if (parentOf(src) == destDir) return src;
  if (destDir == src || destDir.startsWith('$src/')) {
    throw const FileSystemException('Não é possível mover uma pasta para dentro dela mesma');
  }
  final target = uniquePath(destDir, baseName(src));
  return moveTo(src, target, onFile: onFile);
}

Future<String> moveTo(String src, String target,
    {void Function(String name)? onFile}) async {
  final t = await FileSystemEntity.type(src, followLinks: false);
  try {
    if (t == FileSystemEntityType.directory) {
      await Directory(src).rename(target);
    } else if (t == FileSystemEntityType.link) {
      await Link(src).rename(target);
    } else {
      await File(src).rename(target);
    }
    return target;
  } on FileSystemException {
    await _copy(src, target, onFile);
    await deleteForever(src);
    return target;
  }
}

Future<void> deleteForever(String path) async {
  final t = await FileSystemEntity.type(path, followLinks: false);
  if (t == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (t == FileSystemEntityType.link) {
    await Link(path).delete();
  } else if (t != FileSystemEntityType.notFound) {
    await File(path).delete();
  }
}

/// Tamanho de uma pasta e quantos arquivos e pastas tem dentro.
class DirStats {
  final int bytes, files, folders;
  const DirStats(this.bytes, this.files, this.folders);
}

DirStats dirStatsSync(String path) {
  var bytes = 0, files = 0, folders = 0;
  void walk(Directory d) {
    List<FileSystemEntity> items;
    try {
      items = d.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final e in items) {
      if (e is Directory) {
        folders++;
        walk(e);
      } else if (e is File) {
        files++;
        try {
          bytes += e.lengthSync();
        } catch (_) {}
      }
    }
  }

  walk(Directory(path));
  return DirStats(bytes, files, folders);
}

/// Busca por nome em todas as subpastas (até [limit] resultados).
List<String> searchSync(String root, String query,
    {bool hidden = false, int limit = 500}) {
  final q = query.toLowerCase();
  final out = <String>[];
  void walk(Directory d) {
    if (out.length >= limit) return;
    List<FileSystemEntity> items;
    try {
      items = d.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final e in items) {
      if (out.length >= limit) return;
      final n = baseName(e.path);
      if (!hidden && n.startsWith('.')) continue;
      if (n.toLowerCase().contains(q)) out.add(e.path);
      if (e is Directory && !_skipDir(e.path)) walk(e);
    }
  }

  walk(Directory(root));
  return out;
}

/// Pastas que o Android 11+ não deixa ler e a própria lixeira do app.
bool _skipDir(String path) =>
    path.endsWith('/Android/data') ||
    path.endsWith('/Android/obb') ||
    path.endsWith('/.FileGuard');

bool skipDir(String path) => _skipDir(path);

// ---------------------------------------------------------------- Lixeira

/// Cada item apagado vai para <armazenamento>/.FileGuard/Lixeira/<id>/
/// junto com um .info.json (caminho original e data). No mesmo
/// armazenamento, mandar para a lixeira é instantâneo.
class TrashItem {
  final String id; // pasta do item na lixeira
  final String stored; // caminho do arquivo dentro da lixeira
  final String original;
  final DateTime deleted;
  final bool isDir;
  final int size;
  const TrashItem(this.id, this.stored, this.original, this.deleted,
      this.isDir, this.size);
  String get name => baseName(original);
}

const trashDays = 30;

String trashRootFor(String path, List<String> roots) {
  var best = roots.isEmpty ? '/storage/emulated/0' : roots.first;
  for (final r in roots) {
    if ((path == r || path.startsWith('$r/')) && r.length >= best.length) {
      best = r;
    }
  }
  return '$best/.FileGuard/Lixeira';
}

Future<TrashItem> moveToTrash(String path, List<String> roots) async {
  final root = trashRootFor(path, roots);
  final rnd = Random().nextInt(1 << 30).toRadixString(16);
  final id = '$root/${DateTime.now().millisecondsSinceEpoch}_$rnd';
  await Directory(id).create(recursive: true);
  final st = await FileStat.stat(path);
  final isDir = st.type == FileSystemEntityType.directory;
  final size = isDir ? 0 : st.size;
  final now = DateTime.now();
  await File('$id/.info.json').writeAsString(jsonEncode({
    'original': path,
    'deleted': now.toIso8601String(),
    'isDir': isDir,
    'size': size,
  }));
  final stored = '$id/${baseName(path)}';
  try {
    await moveTo(path, stored);
  } catch (e) {
    try {
      await Directory(id).delete(recursive: true);
    } catch (_) {}
    rethrow;
  }
  return TrashItem(id, stored, path, now, isDir, size);
}

Future<List<TrashItem>> listTrash(List<String> roots) async {
  final out = <TrashItem>[];
  for (final r in roots) {
    final dir = Directory('$r/.FileGuard/Lixeira');
    if (!await dir.exists()) continue;
    await for (final d in dir.list(followLinks: false)) {
      if (d is! Directory) continue;
      try {
        final info = jsonDecode(await File('${d.path}/.info.json').readAsString())
            as Map<String, dynamic>;
        final orig = info['original'] as String;
        out.add(TrashItem(
          d.path,
          '${d.path}/${baseName(orig)}',
          orig,
          DateTime.tryParse(info['deleted']?.toString() ?? '') ?? DateTime.now(),
          info['isDir'] == true,
          (info['size'] as num?)?.toInt() ?? 0,
        ));
      } catch (_) {}
    }
  }
  out.sort((a, b) => b.deleted.compareTo(a.deleted));
  return out;
}

/// Volta o item para onde estava (se já existir um com o mesmo nome, fica
/// "nome (1)"). Devolve o caminho onde ficou.
Future<String> restoreFromTrash(TrashItem t) async {
  final dir = parentOf(t.original);
  await Directory(dir).create(recursive: true);
  final target = uniquePath(dir, baseName(t.original));
  await moveTo(t.stored, target);
  try {
    await Directory(t.id).delete(recursive: true);
  } catch (_) {}
  return target;
}

Future<void> deleteTrashItem(TrashItem t) async {
  await Directory(t.id).delete(recursive: true);
}

/// Apaga de vez o que está na lixeira há mais de [trashDays] dias.
Future<int> purgeOldTrash(List<String> roots) async {
  var n = 0;
  final limit = DateTime.now().subtract(const Duration(days: trashDays));
  for (final t in await listTrash(roots)) {
    if (t.deleted.isBefore(limit)) {
      try {
        await deleteTrashItem(t);
        n++;
      } catch (_) {}
    }
  }
  return n;
}

// ---------------------------------------------------------------- Versões

/// "1.10.2" > "1.9.9".
bool newerVersion(String a, String b) {
  List<int> p(String v) => v
      .replaceAll(RegExp(r'^[vV]'), '')
      .split('+')
      .first
      .split('.')
      .map((x) => int.tryParse(x) ?? 0)
      .toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final ai = i < x.length ? x[i] : 0, bi = i < y.length ? y[i] : 0;
    if (ai != bi) return ai > bi;
  }
  return false;
}
