import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'browser.dart';
import 'cleanup.dart';
import 'fs.dart';
import 'home.dart';
import 'native.dart';
import 'picker.dart';
import 'prefs.dart';
import 'settings.dart';
import 'theme.dart';
import 'update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.load();
  // Aberto por outro app para escolher arquivo? Então só o seletor.
  final pick = await Native.pickRequest();
  if (pick != null) {
    await Native.volumes();
    runApp(PickerApp(request: pick));
    return;
  }
  runApp(const FileGuardApp());
}

class FileGuardApp extends StatelessWidget {
  const FileGuardApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FileGuard',
        debugShowCheckedModeBanner: false,
        theme: TG.theme(),
        home: const SplashScreen(),
      );
}

/// Abertura: ícone, nome, versão e créditos.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), _go);
    // A versão vem do APK instalado: muda sozinha a cada atualização.
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }).catchError((_) {});
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => const HomeShell(),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TG.bg,
      body: SafeArea(
        child: Column(children: [
          const Spacer(flex: 3),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image.asset('assets/icon.png', width: 132, height: 132),
            ),
          ),
          const SizedBox(height: 22),
          const Text('FileGuard',
              style: TextStyle(
                  color: TG.text, fontSize: 38, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Seus arquivos, organizados e seguros',
              style: TextStyle(color: TG.muted, fontSize: 15)),
          const Spacer(flex: 4),
          if (_version.isNotEmpty)
            Text('Versão $_version',
                style: const TextStyle(
                    color: TG.accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Criado por Luiz Alberto Cardoso',
              style: TextStyle(color: TG.muted)),
          const Text('tecsattv@gmail.com',
              style: TextStyle(color: TG.muted, fontSize: 12)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

/// Início, Arquivos, Limpeza e Ajustes. Com o telefone deitado ou no tablet
/// o menu fica na lateral.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _filesKey = GlobalKey<BrowserPageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Native.volumes();
      // Lixeira: apaga sozinho o que passou de 30 dias.
      purgeOldTrash(Native.roots);
      if (mounted) UpdateService.autoCheck(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) {
      UpdateService.autoCheck(context, resumed: true);
    }
  }

  static const _dest = [
    (Icons.home_outlined, Icons.home_rounded, 'Início'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Arquivos'),
    (Icons.cleaning_services_outlined, Icons.cleaning_services_rounded, 'Limpeza'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final side = size.width > size.height || size.shortestSide >= 600;
    final pages = [
      const HomePage(),
      BrowserPage(key: _filesKey, start: Native.internal, root: Native.internal, embedded: true),
      const CleanupPage(),
      const SettingsPage(),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    void select(int i) => setState(() => _tab = i);

    return PopScope(
      // Voltar: na aba Arquivos sobe as pastas; fora do Início volta para o
      // Início; no Início fecha o app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab == 1 && (_filesKey.currentState?.handleBack() ?? false)) return;
        if (_tab != 0) {
          select(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: side
          ? Scaffold(
              body: SafeArea(
                child: Row(children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: select,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset('assets/icon.png', width: 36, height: 36),
                      ),
                    ),
                    destinations: [
                      for (final d in _dest)
                        NavigationRailDestination(
                            icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ]),
              ),
            )
          : Scaffold(
              body: body,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: select,
                destinations: [
                  for (final d in _dest)
                    NavigationDestination(
                        icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
                ],
              ),
            ),
    );
  }
}
