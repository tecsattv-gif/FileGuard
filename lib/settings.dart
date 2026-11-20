import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'browser.dart';
import 'fs.dart';
import 'native.dart';
import 'prefs.dart';
import 'theme.dart';
import 'update_service.dart';
import 'viewer.dart';

/// Backup dos ajustes e favoritos. Fica sempre no mesmo arquivo (o novo
/// substitui o anterior), em Download/FileGuard.
const backupDir = '${Native.internal}/Download/FileGuard';
const backupFile = '$backupDir/fileguard-backup.json';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    });
  }

  Future<void> _set(VoidCallback f) async {
    setState(f);
    await Prefs.save();
  }

  Future<String> _writeBackup() async {
    await Directory(backupDir).create(recursive: true);
    final data = {
      'app': 'FileGuard',
      'version': _version,
      'saved': DateTime.now().toIso8601String(),
      'prefs': Prefs.toJson(),
    };
    await File(backupFile)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return backupFile;
  }

  Future<void> _backup() async {
    final p = await busy(context, 'Salvando backup…', _writeBackup);
    if (p != null && mounted) {
      snack(context, 'Backup salvo em Download/FileGuard (substitui o anterior).');
    }
  }

  Future<void> _shareBackup() async {
    final p = await busy(context, 'Preparando backup…', _writeBackup);
    if (p != null) await shareFiles([p]);
  }

  Future<void> _restore() async {
    final start = Directory(backupDir).existsSync() ? backupDir : '${Native.internal}/Download';
    final path = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => BrowserPage(start: start, root: Native.internal, pickExt: 'json')));
    if (path == null || !mounted) return;
    try {
      final m = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      if (m['app'] != 'FileGuard' || m['prefs'] is! Map) {
        throw const FormatException('não é um backup do FileGuard');
      }
      if (!mounted) return;
      final ok = await confirm(context, 'Restaurar backup?',
          'Os ajustes e favoritos atuais serão trocados pelos do backup de ${_date(m['saved'])}.',
          ok: 'Restaurar');
      if (!ok) return;
      Prefs.fromJson(Map<String, dynamic>.from(m['prefs'] as Map));
      await Prefs.save();
      if (mounted) {
        setState(() {});
        snack(context, 'Backup restaurado.');
      }
    } catch (e) {
      if (mounted) snack(context, 'Arquivo inválido: $e');
    }
  }

  String _date(Object? iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? '?' : fmtDate(d);
  }

  @override
  Widget build(BuildContext context) {
    const sorts = {
      SortBy.name: 'Nome',
      SortBy.date: 'Data',
      SortBy.size: 'Tamanho',
      SortBy.type: 'Tipo',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const SectionTitle('EXIBIÇÃO'),
          FCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                title: const Text('Mostrar arquivos ocultos'),
                subtitle: const Text('Nomes que começam com ponto'),
                value: Prefs.showHidden,
                onChanged: (v) => _set(() => Prefs.showHidden = v),
              ),
              SwitchListTile(
                title: const Text('Pastas primeiro'),
                value: Prefs.foldersFirst,
                onChanged: (v) => _set(() => Prefs.foldersFirst = v),
              ),
              SwitchListTile(
                title: const Text('Exibir em grade'),
                subtitle: const Text('Em vez de lista'),
                value: Prefs.grid,
                onChanged: (v) => _set(() => Prefs.grid = v),
              ),
              ListTile(
                title: const Text('Ordenar por'),
                trailing: DropdownButton<SortBy>(
                  value: Prefs.sortBy,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final e in sorts.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) _set(() => Prefs.sortBy = v);
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Ordem crescente'),
                subtitle: Text(Prefs.sortAsc ? 'A → Z, mais antigo primeiro, menor primeiro'
                    : 'Z → A, mais novo primeiro, maior primeiro'),
                value: Prefs.sortAsc,
                onChanged: (v) => _set(() => Prefs.sortAsc = v),
              ),
            ]),
          ),
          const SectionTitle('APAGAR'),
          FCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Mandar para a Lixeira'),
              subtitle: Text(Prefs.useTrash
                  ? 'Dá para restaurar em até $trashDays dias'
                  : 'Desligado: apaga de vez, sem volta'),
              value: Prefs.useTrash,
              onChanged: (v) => _set(() => Prefs.useTrash = v),
            ),
          ),
          const SectionTitle('BACKUP'),
          FCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.save_rounded, color: TG.accent),
                title: const Text('Salvar backup no telefone'),
                subtitle: const Text('Download/FileGuard (ajustes e favoritos)',
                    style: TextStyle(color: TG.muted, fontSize: 12)),
                onTap: _backup,
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: TG.accent),
                title: const Text('Compartilhar backup'),
                subtitle: const Text('Google Drive, WhatsApp, e-mail…',
                    style: TextStyle(color: TG.muted, fontSize: 12)),
                onTap: _shareBackup,
              ),
              ListTile(
                leading: const Icon(Icons.restore_rounded, color: TG.accent),
                title: const Text('Restaurar backup'),
                onTap: _restore,
              ),
            ]),
          ),
          const SectionTitle('PERMISSÃO'),
          FCard(
            padding: EdgeInsets.zero,
            child: FutureBuilder<bool>(
              future: Native.hasAccess(),
              builder: (_, s) => ListTile(
                leading: Icon(
                    s.data == true ? Icons.verified_rounded : Icons.lock_rounded,
                    color: s.data == true ? TG.ok : TG.warn),
                title: const Text('Acesso a todos os arquivos'),
                subtitle: Text(s.data == true ? 'Liberado' : 'Não liberado: toque para abrir',
                    style: const TextStyle(color: TG.muted, fontSize: 12)),
                onTap: Native.requestAccess,
              ),
            ),
          ),
          const SectionTitle('ATUALIZAÇÃO'),
          FCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.system_update_rounded, color: TG.accent),
              title: const Text('Procurar atualização'),
              subtitle: Text('Versão instalada: $_version',
                  style: const TextStyle(color: TG.muted, fontSize: 12)),
              onTap: () => UpdateService.manualCheck(context),
            ),
          ),
          const SectionTitle('SOBRE'),
          FCard(
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/icon.png', width: 56, height: 56),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('FileGuard $_version',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Criado por Luiz Alberto Cardoso',
                      style: TextStyle(color: TG.muted)),
                  const Text('tecsattv@gmail.com', style: TextStyle(color: TG.muted)),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
