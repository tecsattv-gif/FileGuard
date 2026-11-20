import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart' as ar;
import 'package:crypto/crypto.dart';

import 'fs.dart';

/// Análise do armazenamento (categorias, arquivos grandes, duplicados,
/// APKs e pastas vazias). Roda num isolate para a tela não travar.

class FileInfo {
  final String path;
  final int size;
  final DateTime modified;
  const FileInfo(this.path, this.size, this.modified);
  String get name => baseName(path);
  Kind get kind => kindOfFile(path);
}

class ScanResult {
  final Map<Kind, int> bytes;
  final Map<Kind, List<FileInfo>> files;
  final List<FileInfo> big;
  final List<String> emptyDirs;
  final int total;
  final DateTime when;
  const ScanResult(
      this.bytes, this.files, this.big, this.emptyDirs, this.total, this.when);

  List<FileInfo> of(Kind k) => files[k] ?? const [];
}

/// Arquivos a partir deste tamanho entram em "Arquivos grandes".
const bigLimit = 50 * 1024 * 1024;

class Scanner {
  static ScanResult? last;

  static Future<ScanResult> run(List<String> roots, {bool hidden = false}) async {
    final r = await Isolate.run(() => _scan(roots, hidden));
    last = r;
    return r;
  }

  static Future<List<List<FileInfo>>> duplicates(List<FileInfo> all) =>
      Isolate.run(() => _dups(all));
}

ScanResult _scan(List<String> roots, bool hidden) {
  final bytes = <Kind, int>{};
  final files = <Kind, List<FileInfo>>{};
  final big = <FileInfo>[];
  final empty = <String>[];
  var total = 0;

  /// Devolve true se a pasta está vazia (sem nada dentro).
  bool walk(Directory d, int depth) {
    List<FileSystemEntity> items;
    try {
      items = d.listSync(followLinks: false);
    } catch (_) {
      return false;
    }
    if (items.isEmpty) return true;
    for (final e in items) {
      final n = baseName(e.path);
      if (e is Directory) {
        if (skipDir(e.path)) continue;
        if (!hidden && n.startsWith('.')) continue;
        if (walk(e, depth + 1) && depth >= 0) empty.add(e.path);
      } else if (e is File) {
        if (!hidden && n.startsWith('.')) continue;
        FileStat st;
        try {
          st = e.statSync();
        } catch (_) {
          continue;
        }
        final f = FileInfo(e.path, st.size, st.modified);
        final k = f.kind;
        bytes[k] = (bytes[k] ?? 0) + st.size;
        (files[k] ??= []).add(f);
        total += st.size;
        if (st.size >= bigLimit) big.add(f);
      }
    }
    return false;
  }

  for (final r in roots) {
    walk(Directory(r), 0);
  }
  for (final l in files.values) {
    l.sort((a, b) => b.modified.compareTo(a.modified));
  }
  big.sort((a, b) => b.size.compareTo(a.size));
  empty.sort();
  return ScanResult(bytes, files, big, empty, total, DateTime.now());
}

/// Duplicados: mesmo tamanho → mesmo começo e fim (64 KB) → mesmo
/// conteúdo inteiro (MD5). Arquivos menores que 1 KB ficam de fora.
Future<List<List<FileInfo>>> _dups(List<FileInfo> all) async {
  final bySize = <int, List<FileInfo>>{};
  for (final f in all) {
    if (f.size < 1024) continue;
    (bySize[f.size] ??= []).add(f);
  }
  final out = <List<FileInfo>>[];
  for (final group in bySize.values) {
    if (group.length < 2) continue;
    final byQuick = <String, List<FileInfo>>{};
    for (final f in group) {
      final h = _quickHash(f);
      if (h == null) continue;
      (byQuick[h] ??= []).add(f);
    }
    for (final g in byQuick.values) {
      if (g.length < 2) continue;
      if (g.first.size <= 64 * 1024 * 2) {
        out.add(g);
        continue;
      }
      final byFull = <String, List<FileInfo>>{};
      for (final f in g) {
        try {
          final d = await md5.bind(File(f.path).openRead()).first;
          (byFull[d.toString()] ??= []).add(f);
        } catch (_) {}
      }
      for (final x in byFull.values) {
        if (x.length > 1) out.add(x);
      }
    }
  }
  for (final g in out) {
    // O mais antigo primeiro: é o que fica quando se escolhe "selecionar cópias".
    g.sort((a, b) => a.modified.compareTo(b.modified));
  }
  out.sort((a, b) =>
      (b.first.size * (b.length - 1)).compareTo(a.first.size * (a.length - 1)));
  return out;
}

String? _quickHash(FileInfo f) {
  RandomAccessFile? raf;
  try {
    raf = File(f.path).openSync();
    const chunk = 64 * 1024;
    final head = raf.readSync(chunk);
    List<int> tail = const [];
    if (f.size > chunk) {
      raf.setPositionSync(f.size - chunk);
      tail = raf.readSync(chunk);
    }
    return md5.convert([...head, ...tail]).toString();
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------- ZIP

/// Cria um .zip com os arquivos e pastas escolhidos.
Future<String> zipPaths(List<String> paths, String outPath) =>
    Isolate.run(() => _zip(paths, outPath));

Future<String> _zip(List<String> paths, String outPath) async {
  // "dynamic" para funcionar com qualquer versão 3.x do pacote archive
  // (em umas os métodos devolvem Future, em outras não).
  final dynamic enc = ar.ZipFileEncoder();
  enc.create(outPath);
  for (final p in paths) {
    if (FileSystemEntity.isDirectorySync(p)) {
      await enc.addDirectory(Directory(p));
    } else {
      await enc.addFile(File(p));
    }
  }
  await enc.close();
  return outPath;
}

/// Extrai .zip, .tar, .tar.gz/.tgz, .tar.bz2 e .tar.xz para [outDir].
Future<void> extractArchive(String archive, String outDir) =>
    Isolate.run(() => _extract(archive, outDir));

Future<void> _extract(String archive, String outDir) async {
  Directory(outDir).createSync(recursive: true);
  final dynamic r = Function.apply(ar.extractFileToDisk, [archive, outDir]);
  if (r is Future) await r;
}

/// Pasta para extrair "foto.zip" → "foto" (ou "foto (1)" se já existir).
String extractTarget(String archive) {
  var n = baseName(archive);
  for (final suf in ['.tar.gz', '.tar.bz2', '.tar.xz', '.tgz', '.zip', '.tar', '.gz', '.bz2', '.xz']) {
    if (n.toLowerCase().endsWith(suf)) {
      n = n.substring(0, n.length - suf.length);
      break;
    }
  }
  if (n.isEmpty) n = 'extraido';
  return uniquePath(parentOf(archive), n);
}

// ---------------------------------------------------------------- Diversos

Future<DirStats> dirStats(String path) => Isolate.run(() => dirStatsSync(path));

Future<List<String>> search(String root, String q, {bool hidden = false}) =>
    Isolate.run(() => searchSync(root, q, hidden: hidden));
