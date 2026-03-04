import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/home/dashboard_screen.dart';
import '../screens/nutrition/nutrition_plan_screen.dart';
import '../screens/nutrition/food_scanner_screen.dart';
import '../screens/fitness/fitness_plan_screen.dart';
import '../screens/progress/progress_screen.dart';
import '../screens/progress/add_progress_screen.dart';
import '../screens/ai/ai_chat_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/subscription/subscription_screen.dart';
import '../screens/achievements/achievements_screen.dart';
import '../screens/runs/run_history_screen.dart';
import '../screens/runs/run_tracking_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/main_layout.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final authStatus = authState.status;
      final currentLocation = state.matchedLocation;

      final isSplashPage = currentLocation == '/splash';
      final isAuthPage = currentLocation == '/login' || currentLocation == '/register';
      final isOnboardingPage = currentLocation == '/onboarding';

      // While auth is being determined, stay on splash
      if (authStatus == AuthStatus.unknown) {
        if (!isSplashPage) {
          return '/splash';
        }
        return null; // Stay on splash
      }

      // Auth status is now determined, redirect from splash
      if (isSplashPage) {
        switch (authStatus) {
          case AuthStatus.unauthenticated:
            return '/login';
          case AuthStatus.needsOnboarding:
            return '/onboarding';
          case AuthStatus.authenticated:
            return '/dashboard';
          case AuthStatus.unknown:
            return null; // Stay on splash
        }
      }

      // Not on splash, handle normal redirect logic
      if (authStatus == AuthStatus.unauthenticated) {
        // User not logged in, must go to auth pages
        if (!isAuthPage) {
          return '/login';
        }
      } else if (authStatus == AuthStatus.needsOnboarding) {
        // User logged in but needs onboarding
        if (!isOnboardingPage) {
          return '/onboarding';
        }
      } else if (authStatus == AuthStatus.authenticated) {
        // User fully authenticated, redirect away from auth/onboarding pages
        if (isAuthPage || isOnboardingPage) {
          return '/dashboard';
        }
      }

      return null; // No redirect needed
    },
    routes: [
      // Splash Screen
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      // Authentication Routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Main App Routes (Protected)
      ShellRoute(
        builder: (context, state, child) => MainLayout(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/nutrition',
            name: 'nutrition',
            builder: (context, state) => const NutritionPlanScreen(),
          ),
          GoRoute(
            path: '/fitness',
            name: 'fitness',
            builder: (context, state) => const FitnessPlanScreen(),
          ),
          GoRoute(
            path: '/progress',
            name: 'progress',
            builder: (context, state) => const ProgressScreen(),
          ),
          GoRoute(
            path: '/ai-chat',
            name: 'ai-chat',
            builder: (context, state) => const AiChatScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/subscription',
            name: 'subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          GoRoute(
            path: '/food-scanner',
            name: 'food-scanner',
            builder: (context, state) => const FoodScannerScreen(),
          ),
          GoRoute(
            path: '/add-progress',
            name: 'add-progress',
            builder: (context, state) => const AddProgressScreen(),
          ),
          GoRoute(
            path: '/achievements',
            name: 'achievements',
            builder: (context, state) => const AchievementsScreen(),
          ),
          GoRoute(
            path: '/runs',
            name: 'runs',
            builder: (context, state) => const RunHistoryScreen(),
          ),
          GoRoute(
            path: '/run-tracking',
            name: 'run-tracking',
            builder: (context, state) => const RunTrackingScreen(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Page Not Found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'The page you\'re looking for doesn\'t exist.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
});