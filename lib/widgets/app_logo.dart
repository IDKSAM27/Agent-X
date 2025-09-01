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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    Widget logoImage = Image.asset(
      isDarkMode
          ? 'assets/icons/app_icon_dark.png'
          : 'assets/icons/app_icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to single logo if dark version doesn't exist
        return Image.asset(
          'assets/icons/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Final fallback to gradient icon
            return _buildFallbackIcon(context);
          },
        );
      },
    );

    if (useGradientBackground) {
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
            padding: EdgeInsets.all(size * 0.15), // 15% padding
            child: logoImage,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 4),
        boxShadow: showShadow ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
