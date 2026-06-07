import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/login/login_screen.dart';
import 'screens/shell/main_shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/app_loading_overlay.dart';

class XinglianApp extends StatelessWidget {
  const XinglianApp({super.key, this.appState});

  final AppState? appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => appState ?? AppState(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: state.strings.appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            locale: state.strings.flutterLocale,
            supportedLocales: const [
              Locale('en'),
              Locale('zh', 'CN'),
              Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final outer = MediaQuery.of(context);
              final scaled = outer.copyWith(
                textScaler: TextScaler.linear(outer.textScaler.scale(1) * 0.92),
              );
              return ColoredBox(
                color: AppColors.bg,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: MediaQuery(
                      data: scaled,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialized =
        context.select<AppState, bool>((s) => s.initialized);
    final isLoggedIn = context.select<AppState, bool>((s) => s.isLoggedIn);
    final body = !initialized
        ? (!kIsWeb && Platform.isWindows
            ? const _BootSplash()
            : const SizedBox.shrink())
        : isLoggedIn
            ? const MainShell()
            : const LoginScreen();

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        const AppLoadingOverlay(),
      ],
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image(
            image: AssetImage('assets/app_icon_store.png'),
            width: 72,
            height: 72,
          ),
          SizedBox(height: 20),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
