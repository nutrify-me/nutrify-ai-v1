import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/sync_status_provider.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(child: child),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/ai-chat'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.smart_toy, color: Colors.white),
        tooltip: 'AI Coach',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _BottomNavigation(),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get current route name from the current location
    final String location = ModalRoute.of(context)?.settings.name ?? '/dashboard';

    int currentIndex = 0;
    switch (location) {
      case '/dashboard':
        currentIndex = 0;
        break;
      case '/nutrition':
        currentIndex = 1;
        break;
      case '/fitness':
        currentIndex = 2;
        break;
      case '/progress':
        currentIndex = 3;
        break;
      case '/runs':
        currentIndex = 4;
        break;
    }

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            context.go('/dashboard');
            break;
          case 1:
            context.go('/nutrition');
            break;
          case 2:
            context.go('/fitness');
            break;
          case 3:
            context.go('/progress');
            break;
          case 4:
            context.go('/runs');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.restaurant_outlined),
          activeIcon: Icon(Icons.restaurant),
          label: 'Nutrition',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.fitness_center_outlined),
          activeIcon: Icon(Icons.fitness_center),
          label: 'Fitness',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.trending_up_outlined),
          activeIcon: Icon(Icons.trending_up),
          label: 'Progress',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_run_outlined),
          activeIcon: Icon(Icons.directions_run),
          label: 'Running',
        ),
      ],
    );
  }
}