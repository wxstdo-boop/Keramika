import 'package:flutter/material.dart';

/// Smooth refresh indicator with fade-in and scale animation for data loading.
/// Provides a very smooth experience when refreshing data across all screens.
class SmoothRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const SmoothRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<SmoothRefresh> createState() => _SmoothRefreshState();
}

class _SmoothRefreshState extends State<SmoothRefresh>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 400),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() => _isRefreshing = false);
          }
        });

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _animController.reset();
    _animController.forward();
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _opacityAnimation,
            child: ScaleTransition(scale: _scaleAnimation, child: child!),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Smooth semi-transparent background with fade-in animation.
/// Makes the theme background visible through cards and surfaces.
class SmoothBackground extends StatelessWidget {
  final Widget child;
  const SmoothBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      opacity: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surfaceContainer.withValues(alpha: 0.7),
              theme.colorScheme.surface.withValues(alpha: 0.9),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Simple wrapper that wraps content with smooth refresh
SmoothRefresh smoothRefresh({
  required Future<void> Function() onRefresh,
  required Widget child,
}) {
  return SmoothRefresh(onRefresh: onRefresh, child: child);
}

/// Wraps a widget with smooth semi-transparent background
SmoothBackground smoothBackground({required Widget child}) {
  return SmoothBackground(child: child);
}
