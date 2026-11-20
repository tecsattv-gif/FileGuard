import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'fs.dart';
import 'native.dart';
import 'theme.dart';

/// Visualizadores dentro do app: imagens, vídeo/áudio, texto e PDF.

Future<void> openWithOtherApp(BuildContext context, String path) async {
  final r = await OpenFilex.open(path);
  if (r.type != ResultType.done && context.mounted) {
    snack(context, 'Nenhum app para abrir este arquivo (${r.message}).');
  }
}

Future<void> shareFiles(List<String> paths) async {
  if (paths.isEmpty) return;
  await SharePlus.instance
      .share(ShareParams(files: paths.map((p) => XFile(p)).toList()));
}

List<Widget> _commonActions(BuildContext context, String path) => [
      IconButton(
        tooltip: 'Compartilhar',
        icon: const Icon(Icons.share_rounded),
        onPressed: () => shareFiles([path]),
      ),
      IconButton(
        tooltip: 'Abrir com outro app',
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: () => openWithOtherApp(context, path),
      ),
    ];

// ---------------------------------------------------------------- Imagens

class ImageViewer extends StatefulWidget {
  final List<String> images;
  final int initial;
  const ImageViewer({super.key, required this.images, this.initial = 0});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  bool _chrome = true;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.images[_i];
    final mq = MediaQuery.of(context);
    // Limita a resolução decodificada (fotos de 50 MP travariam o app).
    final cw = (mq.size.longestSide * mq.devicePixelRatio * 1.5).round();
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              title: Text(
                  '${baseName(path)}  (${_i + 1}/${widget.images.length})',
                  style: const TextStyle(fontSize: 15)),
              actions: _commonActions(context, path),
            )
          : null,
      body: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: PageView.builder(
          controller: _pc,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(
              child: Image.file(
                File(widget.images[i]),
                cacheWidth: cw,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                    'Não foi possível abrir esta imagem',
                    style: TextStyle(color: TG.muted)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Vídeo e áudio

class MediaViewer extends StatefulWidget {
  final String path;
  const MediaViewer({super.key, required this.path});

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final VideoPlayerController _c =
      VideoPlayerController.file(File(widget.path));
  String? _error;
  bool get _isAudio => kindOfFile(widget.path) == Kind.audio;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  String _t(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final pos = v.position, dur = v.duration;
    final max = dur.inMilliseconds.toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(baseName(widget.path), style: const TextStyle(fontSize: 15)),
        actions: _commonActions(context, widget.path),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Este formato não abre no FileGuard.',
                          style: TextStyle(color: TG.muted)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => openWithOtherApp(context, widget.path),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Abrir com outro app'),
                      ),
                    ]),
                  )
                : !v.isInitialized
                    ? const CircularProgressIndicator()
                    : _isAudio
                        ? const KindIcon(Kind.audio, size: 160)
                        : AspectRatio(
                            aspectRatio:
                                v.aspectRatio <= 0 ? 16 / 9 : v.aspectRatio,
                            child: GestureDetector(
                              onTap: _toggle,
                              child: VideoPlayer(_c),
                            ),
                          ),
          ),
        ),
        if (v.isInitialized)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(children: [
                Slider(
                  value: pos.inMilliseconds
                      .toDouble()
                      .clamp(0.0, max <= 0 ? 1.0 : max)
                      .toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: (x) =>
                      _c.seekTo(Duration(milliseconds: x.round())),
                ),
                Row(children: [
                  Text(_t(pos), style: const TextStyle(color: TG.muted)),
                  const Spacer(),
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.replay_10_rounded),
                    onPressed: () =>
                        _c.seekTo(pos - const Duration(seconds: 10)),
                  ),
                  IconButton.filled(
                    iconSize: 40,
                    icon: Icon(v.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: _toggle,
                  ),
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.forward_10_rounded),
                    onPressed: () =>
                        _c.seekTo(pos + const Duration(seconds: 10)),
                  ),
                  const Spacer(),
                  Text(_t(dur), style: const TextStyle(color: TG.muted)),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  void _toggle() {
    if (_c.value.isPlaying) {
      _c.pause();
    } else {
      if (_c.value.position >= _c.value.duration) _c.seekTo(Duration.zero);
      _c.play();
    }
  }
}

// ---------------------------------------------------------------- Texto

/// Arquivos de texto até 2 MB abrem para ler e editar.
const textLimit = 2 * 1024 * 1024;

class TextViewer extends StatefulWidget {
  final String path;
  const TextViewer({super.key, required this.path});

  @override
  State<TextViewer> createState() => _TextViewerState();
}

class _TextViewerState extends State<TextViewer> {
  final _c = TextEditingController();
  String _original = '';
  bool _loading = true, _editing = false, _tooBig = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = File(widget.path);
      if (await f.length() > textLimit) {
        _tooBig = true;
      } else {
        _original = utf8.decode(await f.readAsBytes(), allowMalformed: true);
        _c.text = _original;
      }
    } catch (e) {
      _original = 'Erro ao ler: $e';
      _c.text = _original;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    try {
      await File(widget.path).writeAsString(_c.text);
      _original = _c.text;
      if (!mounted) return;
      setState(() => _editing = false);
      snack(context, 'Arquivo salvo.');
    } catch (e) {
      if (mounted) snack(context, 'Não foi possível salvar: $e');
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_c.text == _original) {
          Navigator.pop(context);
          return;
        }
        final discard = await confirm(context, 'Sair sem salvar?',
            'As alterações neste arquivo serão perdidas.',
            ok: 'Sair', danger: true);
        if (discard && context.mounted) {
          setState(() {
            _c.text = _original;
            _editing = false;
          });
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(baseName(widget.path), style: const TextStyle(fontSize: 16)),
          actions: [
            if (!_loading && !_tooBig)
              _editing
                  ? IconButton(
                      tooltip: 'Salvar',
                      icon: const Icon(Icons.save_rounded, color: TG.accent),
                      onPressed: _save)
                  : IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () => setState(() => _editing = true)),
            ..._commonActions(context, widget.path),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tooBig
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Arquivo grande demais para abrir aqui (mais de 2 MB).',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: TG.muted)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => openWithOtherApp(context, widget.path),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Abrir com outro app'),
                        ),
                      ]),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: TextField(
                      controller: _c,
                      readOnly: !_editing,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13.5, height: 1.4),
                      decoration: InputDecoration(
                        fillColor: _editing ? TG.surfaceHigh : TG.surface,
                      ),
                    ),
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------- PDF

/// PDF desenhado pelo próprio Android (página por página, com zoom).
class PdfViewer extends StatefulWidget {
  final String path;
  const PdfViewer({super.key, required this.path});

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  int _pages = 0, _current = 0;
  String? _error;
  final _cache = <int, Uint8List>{};
  final _pending = <int, Future<Uint8List?>>{};
  // O Android abre um PDF de cada vez: as páginas são pedidas em fila.
  Future<void> _queue = Future.value();

  @override
  void initState() {
    super.initState();
    Native.pdfOpen(widget.path).then((n) {
      if (mounted) setState(() => _pages = n);
    }).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  void dispose() {
    Native.pdfClose();
    super.dispose();
  }

  Future<Uint8List?> _page(int i, int width) {
    if (_cache.containsKey(i)) return Future.value(_cache[i]);
    return _pending[i] ??= () {
      final c = Completer<Uint8List?>();
      _queue = _queue.then((_) async {
        try {
          final b = await Native.pdfPage(i, width);
          if (b != null) {
            _cache[i] = b;
            // Guarda só as páginas perto da atual.
            _cache.removeWhere((k, _) => (k - _current).abs() > 4);
          }
          c.complete(b);
        } catch (e) {
          c.complete(null);
        } finally {
          _pending.remove(i);
        }
      });
      return c.future;
    }();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = (mq.size.width * mq.devicePixelRatio).round().clamp(600, 1800).toInt();
    return Scaffold(
      backgroundColor: const Color(0xFF2A3346),
      appBar: AppBar(
        title: Text(
            _pages > 0
                ? '${baseName(widget.path)}  (${_current + 1}/$_pages)'
                : baseName(widget.path),
            style: const TextStyle(fontSize: 15)),
        actions: _commonActions(context, widget.path),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Não foi possível abrir este PDF (pode ter senha).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: TG.muted)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => openWithOtherApp(context, widget.path),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir com outro app'),
                  ),
                ]),
              ),
            )
          : _pages == 0
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: _pages,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (_, i) => FutureBuilder<Uint8List?>(
                    future: _page(i, width),
                    builder: (_, s) {
                      final b = s.data ?? _cache[i];
                      if (b == null &&
                          s.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (b == null) {
                        return const Center(
                            child: Text('Erro nesta página',
                                style: TextStyle(color: TG.muted)));
                      }
                      return InteractiveViewer(
                        maxScale: 5,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Image.memory(b, gaplessPlayback: true),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
