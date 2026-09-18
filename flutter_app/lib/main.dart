import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/services/hive_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/fcm_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'cubits/graph/graph_cubit.dart';
import 'cubits/graph/graph_state.dart';
import 'cubits/library/library_cubit.dart';
import 'cubits/notification/notification_cubit.dart';
import 'cubits/notification/notification_state.dart';
import 'cubits/paper_details/paper_details_cubit.dart';
import 'cubits/search/search_cubit.dart';
import 'cubits/theme/theme_cubit.dart';
import 'cubits/theme/theme_state.dart';
import 'providers/auth_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/papers_provider.dart';
import 'views/splash/splash_view.dart';
import 'views/widgets/error_boundary.dart';
import 'views/widgets/notification_toast_overlay.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Hive local database
  await HiveService.init();

  await LocalNotificationService.init(
    onNotificationTap: FcmNotificationService.handleLocalNotificationTap,
  );
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FcmNotificationService.initialize(_rootNavigatorKey);
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  // Graceful fallback for unexpected framework exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(
      'Captured unhandled framework error: ${details.exceptionAsString()}',
    );
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return GlobalErrorDisplay(details: details);
  };

  runApp(const PaperGraphApp());
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class PaperGraphApp extends StatelessWidget {
  const PaperGraphApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<SearchCubit>(create: (_) => SearchCubit()),
        BlocProvider<PaperDetailsCubit>(create: (_) => PaperDetailsCubit()),
        BlocProvider<LibraryCubit>(create: (_) => LibraryCubit()),
        BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
        BlocProvider<GraphCubit>(
          create: (_) => GraphCubit(resumePendingJob: true),
        ),
      ],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PapersProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<GraphCubit, GraphState>(
              listener: (context, state) {
                if (state is GraphLoaded && state.isNewlyGenerated) {
                  if (state.isPersisted) {
                    context.read<LibraryCubit>().loadLibrary();
                    LocalNotificationService.onGraphCompleted(
                      graphId: state.snapshot.graphId,
                      nodeCount: state.snapshot.nodes.length,
                      isPartial: state.isPartial,
                      notificationCubit: context.read<NotificationCubit>(),
                    );
                  } else {
                    context.read<NotificationCubit>().notify(
                      title: 'Graph ready, but not saved',
                      message:
                          state.persistenceWarning ??
                          'Keep the graph open and try saving it again.',
                      type: NotificationType.error,
                    );
                  }
                } else if (state is GraphError && state.graphId != null) {
                  LocalNotificationService.onGraphFailed(
                    graphId: state.graphId!,
                    error: state.message,
                    notificationCubit: context.read<NotificationCubit>(),
                  );
                }
              },
            ),
          ],
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, themeState) {
              return MaterialApp(
                title: 'PaperGraph',
                navigatorKey: _rootNavigatorKey,
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeState.themeMode,
                builder: (context, child) {
                  return NotificationToastOverlay(
                    child: child ?? const SizedBox.shrink(),
                  );
                },
                home: const SplashView(),
              );
            },
          ),
        ),
      ),
    );
  }
}
