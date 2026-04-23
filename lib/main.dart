import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:safe_house/injection_container.dart' as di;
import 'core/theme/theme_notifier.dart';
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/cubits/auth_cubit.dart';
import 'features/settings/presentation/cubits/settings_cubit.dart';

import 'features/encryption/domain/entities/encrypted_file.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Lock orientation to portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialise Hive for Flutter (uses app documents directory).
  await Hive.initFlutter();

  // Register Hive type adapters before opening any box. The guard makes
  // hot-restart in development idempotent.
  if (!Hive.isAdapterRegistered(kEncryptedFileTypeId)) {
    Hive.registerAdapter(EncryptedFileAdapter());
  }

  // Boot the service locator.
  await di.init();

  runApp(const SafeHouseApp());
}

class SafeHouseApp extends StatelessWidget {
  const SafeHouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = di.sl<ThemeNotifier>();

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (_) => di.sl<AuthCubit>()..checkAuthStatus(),
        ),
        BlocProvider<SettingsCubit>(create: (_) => di.sl<SettingsCubit>()),
      ],
      child: ValueListenableBuilder<ThemeData>(
        valueListenable: themeNotifier,
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'SafeHouse',
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
