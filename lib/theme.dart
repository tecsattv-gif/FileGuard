import 'package:flutter/material.dart';

import 'fs.dart';

/// Cores do FileGuard (tema escuro, no mesmo estilo dos outros apps).
class TG {
  static const bg = Color(0xFF0A111E);
  static const surface = Color(0xFF121C2D);
  static const surfaceHigh = Color(0xFF1A2740);
  static const line = Color(0xFF24324D);
  static const accent = Color(0xFF2DD4BF);
  static const text = Color(0xFFE8EEF8);
  static const muted = Color(0xFF8A9BB5);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(surface: surface, primary: accent);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            TextStyle(color: text, fontSize: 21, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.18),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: text),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static IconData icon(Kind k) {
    switch (k) {
      case Kind.folder:
        return Icons.folder_rounded;
      case Kind.image:
        return Icons.image_rounded;
      case Kind.video:
        return Icons.movie_rounded;
      case Kind.audio:
        return Icons.music_note_rounded;
      case Kind.pdf:
        return Icons.picture_as_pdf_rounded;
      case Kind.text:
        return Icons.description_rounded;
      case Kind.document:
        return Icons.article_rounded;
      case Kind.archive:
        return Icons.folder_zip_rounded;
      case Kind.apk:
        return Icons.android_rounded;
      case Kind.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color color(Kind k) {
    switch (k) {
      case Kind.folder:
        return const Color(0xFF38BDF8);
      case Kind.image:
        return const Color(0xFFA78BFA);
      case Kind.video:
        return const Color(0xFFF472B6);
      case Kind.audio:
        return const Color(0xFFFB923C);
      case Kind.pdf:
        return const Color(0xFFF87171);
      case Kind.text:
        return const Color(0xFF94A3B8);
      case Kind.document:
        return const Color(0xFF60A5FA);
      case Kind.archive:
        return const Color(0xFFFBBF24);
      case Kind.apk:
        return const Color(0xFF34D399);
      case Kind.other:
        return const Color(0xFF8A9BB5);
    }
  }

  static String label(Kind k) {
    switch (k) {
      case Kind.folder:
        return 'Pastas';
      case Kind.image:
        return 'Imagens';
      case Kind.video:
        return 'Vídeos';
      case Kind.audio:
        return 'Áudio';
      case Kind.pdf:
        return 'PDF';
      case Kind.text:
        return 'Textos';
      case Kind.document:
        return 'Documentos';
      case Kind.archive:
        return 'Compactados';
      case Kind.apk:
        return 'APKs';
      case Kind.other:
        return 'Outros';
    }
  }
}

/// Cartão padrão do app.
class FCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const FCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TG.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: TG.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Ícone colorido de um tipo de arquivo.
class KindIcon extends StatelessWidget {
  final Kind kind;
  final double size;
  const KindIcon(this.kind, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = TG.color(kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(TG.icon(kind), color: c, size: size * 0.55),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: TG.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Barra de uso (usado / total).
class UsageBar extends StatelessWidget {
  final double value;
  final Color? color;
  const UsageBar(this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final c = color ?? (v >= 0.9 ? TG.danger : (v >= 0.75 ? TG.warn : TG.accent));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: v,
        minHeight: 8,
        backgroundColor: TG.surfaceHigh,
        color: c,
      ),
    );
  }
}

void snack(BuildContext context, String text,
    {String? actionLabel, VoidCallback? action, int seconds = 4}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    duration: Duration(seconds: seconds),
    action: action == null
        ? null
        : SnackBarAction(
            label: actionLabel ?? 'OK',
            textColor: TG.accent,
            onPressed: action),
  ));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmar', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: TG.danger, foregroundColor: Colors.black)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Pede um nome (nova pasta, renomear, nome do ZIP).
Future<String?> askName(BuildContext context, String title,
    {String initial = '', String ok = 'OK'}) async {
  final c = TextEditingController(text: initial);
  // Seleciona o nome sem a extensão ("foto" em "foto.jpg").
  final dot = initial.lastIndexOf('.');
  c.selection = TextSelection(
      baseOffset: 0, extentOffset: dot > 0 ? dot : initial.length);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
  final v = r?.trim();
  if (v == null || v.isEmpty) return null;
  if (!validName(v)) {
    if (context.mounted) snack(context, 'Nome inválido: não pode ter "/".');
    return null;
  }
  return v;
}

/// Janela de "trabalhando…" enquanto [job] roda. Devolve o resultado ou
/// mostra o erro.
Future<T?> busy<T>(BuildContext context, String title, Future<T> Function() job,
    {ValueNotifier<String>? detail}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (detail != null)
                  ValueListenableBuilder<String>(
                    valueListenable: detail,
                    builder: (_, v, __) => Text(v,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: TG.muted, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    ),
  );
  try {
    final r = await job();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      snack(context, 'Erro: ${_msg(e)}', seconds: 6);
    }
    return null;
  }
}

String _msg(Object e) =>
    e.toString().replaceFirst(RegExp(r'^\w*Exception: ?'), '');
