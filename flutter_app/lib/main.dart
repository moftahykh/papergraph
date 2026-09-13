import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/services/hive_service.dart';
import 'core/theme/app_theme.dart';
import 'cubits/graph/graph_cubit.dart';
import 'cubits/library/library_cubit.dart';
import 'cubits/notification/notification_cubit.dart';
import 'cubits/paper_details/paper_details_cubit.dart';
import 'cubits/search/search_cubit.dart';
import 'cubits/theme/theme_cubit.dart';
import 'cubits/theme/theme_state.dart';
import 'providers/auth_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/papers_provider.dart';
import 'views/splash/splash_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Hive local database
  await HiveService.init();

  // Initialize Firebase (Auth). Reads android/app/google-services.json added
  // by `flutterfire configure`. Wrapped so the app still runs (and tests
  // still pass) before configuration exists.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  runApp(const PaperGraphApp());
}

class PaperGraphApp extends StatelessWidget {
  const PaperGraphApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<SearchCubit>(create: (_) => SearchCubit()),
        BlocProvider<GraphCubit>(create: (_) => GraphCubit()),
        BlocProvider<PaperDetailsCubit>(create: (_) => PaperDetailsCubit()),
        BlocProvider<LibraryCubit>(create: (_) => LibraryCubit()),
        BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
      ],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PapersProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return MaterialApp(
              title: 'PaperGraph',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeState.themeMode,
              home: const SplashView(),
            );
          },
        ),
      ),
    );
  }
}
