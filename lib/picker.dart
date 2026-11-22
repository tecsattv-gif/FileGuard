import 'dart:io';

import 'package:flutter/material.dart';

import 'browser.dart';
import 'fs.dart';
import 'native.dart';
import 'prefs.dart';
import 'theme.dart';

/// Seletor de arquivos: abre quando outro app (WhatsApp, Gmail, navegador…)
/// pede um arquivo e você escolhe o FileGuard.
class PickerApp extends StatelessWidget {
  final PickRequest request;
  const PickerApp({super.key, required this.request});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FileGuard',
        debugShowCheckedModeBanner: false,
        theme: TG.theme(),
        home: PickerHome(request: request),
      );
}

class PickerHome extends StatefulWidget {
  final PickRequest request;
  const PickerHome({super.key, required this.request});

  @override
  State<PickerHome> createState() => _PickerHomeState();
}

class _PickerHomeState extends State<PickerHome> with WidgetsBindingObserver {
  bool? _access;
  List<Volume> _volumes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
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

  void _open(String path, {String? root}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BrowserPage(start: path, root: root, pick: widget.request)));
  }

  String get _what {
    final r = widget.request;
    if (r.any) return r.multiple ? 'Escolha um ou mais arquivos' : 'Escolha um arquivo';
    final kinds = <String>{};
    for (final m in r.mimes) {
      if (m.startsWith('image/')) {
        kinds.add('imagem');
      } else if (m.startsWith('video/')) {
        kinds.add('vídeo');
      } else if (m.startsWith('audio/')) {
        kinds.add('áudio');
      } else if (m == 'application/pdf') {
        kinds.add('PDF');
      } else if (m.startsWith('text/')) {
        kinds.add('texto');
      } else {
        kinds.add('documento');
      }
    }
    return 'Escolha: ${kinds.join(', ')}';
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancelar',
          icon: const Icon(Icons.close_rounded),
          onPressed: Native.pickCancel,
        ),
        title: Text(_what),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_access == false)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Falta liberar "Acesso a todos os arquivos" para o FileGuard.',
                      style: TextStyle(color: TG.muted)),
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: Native.requestAccess,
                      child: const Text('Permitir acesso')),
                ]),
              ),
            ),
          if (widget.request.multiple)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Para escolher vários: toque longo no primeiro e depois toque nos outros.',
                  style: TextStyle(color: TG.muted, fontSize: 12.5)),
            ),
          for (final v in _volumes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FCard(
                padding: EdgeInsets.zero,
                onTap: () => _open(v.path, root: v.path),
                child: ListTile(
                  leading: Icon(v.removable ? Icons.sd_card_rounded : Icons.smartphone_rounded,
                      color: TG.accent),
                  title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: v.total > 0
                      ? Text('${fmtSize(v.free)} livres de ${fmtSize(v.total)}',
                          style: const TextStyle(color: TG.muted, fontSize: 12))
                      : null,
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
          if (shortcuts.isNotEmpty) ...[
            const SectionTitle('ATALHOS'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final s in shortcuts)
                ActionChip(
                  avatar: Icon(s.$2, size: 18, color: TG.accent),
                  label: Text(s.$1),
                  onPressed: () => _open(s.$3, root: Native.internal),
                ),
            ]),
          ],
          if (Prefs.favorites.isNotEmpty) ...[
            const SectionTitle('FAVORITOS'),
            FCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final f in Prefs.favorites.where((f) => Directory(f).existsSync()))
                  ListTile(
                    leading: const KindIcon(Kind.folder, size: 38),
                    title: Text(baseName(f)),
                    onTap: () => _open(f),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
