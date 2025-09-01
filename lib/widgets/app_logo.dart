import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool showShadow;
  final bool useGradientBackground;

  const AppLogo({
    super.key,
    this.size = 40,
    this.showShadow = false,
    this.useGradientBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    // Make it reactive to theme changes
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildLogo(context),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Use a key to force rebuild when theme changes
    final logoKey = ValueKey('logo_${isDarkMode ? 'dark' : 'light'}');

    Widget logoImage = Image.asset(
      'assets/icons/app_icon.png', // Use single logo for now
      key: logoKey,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return _buildFallbackIcon(context);
      },
    );

    if (useGradientBackground) {
      return Container(
        key: logoKey,
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
          borderRadius: BorderRadius.circular(size / 4),
          boxShadow: showShadow ? [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: size / 4,
              offset: Offset(0, size / 10),
            ),
          ] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Padding(
            padding: EdgeInsets.all(size * 0.15),
            child: logoImage,
          ),
        ),
      );
    }

    return Container(
      key: logoKey,
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 4),
        boxShadow: showShadow ? [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.1),
            blurRadius: size / 8,
            offset: Offset(0, size / 20),
          ),
        ] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: logoImage,
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        size: size * 0.6,
        color: Colors.white,
      ),
    );
  }
}
