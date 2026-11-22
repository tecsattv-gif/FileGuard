import 'dart:io';

import 'package:fileguard/fs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tamanhos legíveis', () {
    expect(fmtSize(0), '0 B');
    expect(fmtSize(1023), '1023 B');
    expect(fmtSize(1536), '1,5 KB');
    expect(fmtSize(5 * 1024 * 1024), '5,0 MB');
    expect(fmtSize(300 * 1024 * 1024), '300 MB');
  });

  test('nomes e pastas', () {
    expect(baseName('/storage/emulated/0/Download/a.pdf'), 'a.pdf');
    expect(baseName('/storage/emulated/0/Download/'), 'Download');
    expect(parentOf('/storage/emulated/0/Download/a.pdf'), '/storage/emulated/0/Download');
    expect(parentOf('/a'), '/');
    expect(extOf('Foto.JPG'), 'jpg');
    expect(extOf('.nomedia'), '');
    expect(extOf('sem_extensao'), '');
  });

  test('tipos de arquivo', () {
    expect(kindOfFile('a.jpg'), Kind.image);
    expect(kindOfFile('a.MP4'), Kind.video);
    expect(kindOfFile('a.mp3'), Kind.audio);
    expect(kindOfFile('a.pdf'), Kind.pdf);
    expect(kindOfFile('a.txt'), Kind.text);
    expect(kindOfFile('a.docx'), Kind.document);
    expect(kindOfFile('a.zip'), Kind.archive);
    expect(kindOfFile('a.apk'), Kind.apk);
    expect(kindOfFile('a.xyz'), Kind.other);
  });

  test('versões', () {
    expect(newerVersion('1.10.0', '1.9.9'), isTrue);
    expect(newerVersion('v1.0.1', '1.0.0'), isTrue);
    expect(newerVersion('1.0.0', '1.0.0'), isFalse);
    expect(newerVersion('1.0.0', '1.2.0'), isFalse);
  });

  test('tipos pedidos por outros apps (MIME)', () {
    expect(mimeOf('foto.JPG'), 'image/jpeg');
    expect(mimeOf('x.qqq'), 'application/octet-stream');
    expect(mimeMatches('foto.jpg', ['*/*']), isTrue);
    expect(mimeMatches('foto.jpg', ['image/*']), isTrue);
    expect(mimeMatches('doc.pdf', ['image/*']), isFalse);
    expect(mimeMatches('doc.pdf', ['image/*', 'application/pdf']), isTrue);
    expect(mimeMatches('musica.mp3', ['audio/*']), isTrue);
    expect(mimeMatches('x.qqq', ['application/octet-stream']), isTrue);
  });

  test('nomes válidos', () {
    expect(validName('Fotos 2026'), isTrue);
    expect(validName('a/b'), isFalse);
    expect(validName('  '), isFalse);
    expect(validName('..'), isFalse);
  });

  group('no disco', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('fg'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('nome repetido vira "nome (1)"', () {
      File('${tmp.path}/a.txt').writeAsStringSync('x');
      expect(uniquePath(tmp.path, 'a.txt'), '${tmp.path}/a (1).txt');
      expect(uniquePath(tmp.path, 'b.txt'), '${tmp.path}/b.txt');
    });

    test('copiar e mover pasta com conteúdo', () async {
      final src = Directory('${tmp.path}/src')..createSync();
      File('${src.path}/x.txt').writeAsStringSync('ola');
      Directory('${src.path}/sub').createSync();
      File('${src.path}/sub/y.txt').writeAsStringSync('mundo');
      final dest = Directory('${tmp.path}/dest')..createSync();

      final c = await copyInto(src.path, dest.path);
      expect(File('$c/sub/y.txt').readAsStringSync(), 'mundo');
      expect(src.existsSync(), isTrue);

      final m = await moveInto(src.path, dest.path);
      expect(m, '${dest.path}/src (1)');
      expect(src.existsSync(), isFalse);
      expect(File('$m/x.txt').readAsStringSync(), 'ola');
    });

    test('não copia pasta para dentro dela mesma', () async {
      final src = Directory('${tmp.path}/src')..createSync();
      final inner = Directory('${src.path}/in')..createSync();
      await expectLater(
          moveInto(src.path, inner.path), throwsA(isA<FileSystemException>()));
    });

    test('lixeira: apagar e restaurar', () async {
      final f = File('${tmp.path}/doc.txt')..writeAsStringSync('importante');
      final t = await moveToTrash(f.path, [tmp.path]);
      expect(f.existsSync(), isFalse);
      final list = await listTrash([tmp.path]);
      expect(list.length, 1);
      expect(list.first.original, f.path);
      final back = await restoreFromTrash(list.first);
      expect(back, f.path);
      expect(File(back).readAsStringSync(), 'importante');
      expect(Directory(t.id).existsSync(), isFalse);
      expect(await listTrash([tmp.path]), isEmpty);
    });

    test('ordenar: pastas primeiro, depois nome', () {
      final now = DateTime(2026);
      final l = [
        Entry('/x/b.txt', false, 5, now),
        Entry('/x/Zeta', true, 0, now),
        Entry('/x/a.txt', false, 9, now),
      ];
      sortEntries(l, SortBy.name, true);
      expect(l.map((e) => e.name).toList(), ['Zeta', 'a.txt', 'b.txt']);
      sortEntries(l, SortBy.size, false);
      expect(l.map((e) => e.name).toList(), ['Zeta', 'a.txt', 'b.txt']);
    });
  });
}
