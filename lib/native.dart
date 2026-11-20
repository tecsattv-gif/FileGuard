import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Armazenamento (interno ou cartão SD) com espaço total e livre.
class Volume {
  final String path;
  final bool removable;
  final int total, free;
  const Volume(this.path, this.removable, this.total, this.free);
  int get used => total - free;
  String get name => removable ? 'Cartão SD' : 'Armazenamento interno';
}

/// Ponte com o Android (MainActivity.kt).
class Native {
  static const _ch = MethodChannel('fileguard/native');
  static const internal = '/storage/emulated/0';
  static String? _docs, _temp;
  static List<Volume> _volumes = const [];

  static Future<void> _dirs() async {
    if (_docs != null && _temp != null) return;
    try {
      final m = await _ch.invokeMapMethod<String, String>('dirs');
      _docs = m?['docs'];
      _temp = m?['temp'];
    } catch (_) {}
    _docs ??= '/data/user/0/com.tecsattv.fileguard/app_flutter';
    _temp ??= '/data/user/0/com.tecsattv.fileguard/cache';
  }

  /// Pasta privada do app.
  static Future<Directory> docs() async {
    await _dirs();
    final d = Directory(_docs!);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Cache do app (APKs das atualizações, arquivos temporários).
  static Future<Directory> temp() async {
    await _dirs();
    final d = Directory(_temp!);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<Volume>> volumes() async {
    try {
      final l = await _ch.invokeListMethod<dynamic>('volumes') ?? const [];
      final v = <Volume>[];
      for (final x in l) {
        final m = x as Map;
        v.add(Volume(
          m['path'].toString(),
          m['removable'] == true,
          (m['total'] as num?)?.toInt() ?? 0,
          (m['free'] as num?)?.toInt() ?? 0,
        ));
      }
      if (v.isNotEmpty) _volumes = v;
    } catch (_) {}
    if (_volumes.isEmpty) _volumes = const [Volume(internal, false, 0, 0)];
    return _volumes;
  }

  /// Raízes conhecidas (última leitura). Usado pela lixeira.
  static List<String> get roots => _volumes.isEmpty
      ? const [internal]
      : _volumes.map((v) => v.path).toList();

  static Future<bool> hasAccess() async {
    try {
      return await _ch.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela do Android "Acesso a todos os arquivos".
  static Future<void> requestAccess() async {
    try {
      await _ch.invokeMethod('requestAccess');
    } catch (_) {}
  }

  /// Avisa a Galeria/Música que estes arquivos mudaram.
  static Future<void> mediaScan(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _ch.invokeMethod('scan', {'paths': paths});
    } catch (_) {}
  }

  static Future<int> pdfOpen(String path) async =>
      await _ch.invokeMethod<int>('pdfOpen', {'path': path}) ?? 0;

  static Future<Uint8List?> pdfPage(int index, int width) =>
      _ch.invokeMethod<Uint8List>('pdfPage', {'index': index, 'width': width});

  static Future<void> pdfClose() async {
    try {
      await _ch.invokeMethod('pdfClose');
    } catch (_) {}
  }
}
