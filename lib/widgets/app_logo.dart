import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/constants.dart';

enum AppLogoVariant {
  /// Full logo: teal gradient background + white S glyph. Use on light/neutral surfaces.
  full,

  /// White glyph only (transparent background). Use on teal/dark surfaces.
  white,
}

/// Displays the SmartSplit logo at any size.
///
/// ```dart
/// AppLogo(size: 80)                       // full logo, 80×80
/// AppLogo(size: 48, variant: AppLogoVariant.white)  // white glyph only
/// ```
class AppLogo extends StatelessWidget {
  final double size;
  final AppLogoVariant variant;

  const AppLogo({
    super.key,
    this.size = 64,
    this.variant = AppLogoVariant.full,
  });

  @override
  Widget build(BuildContext context) {
    final asset = variant == AppLogoVariant.white
        ? 'assets/images/logo_white.svg'
        : 'assets/images/logo.svg';

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      semanticsLabel: 'SmartSplit logo',
    );
  }
}

/// Logo + wordmark stacked vertically — used on the login / splash screens.
class AppLogoWithWordmark extends StatelessWidget {
  final double logoSize;
  final Color? textColor;

  const AppLogoWithWordmark({
    super.key,
    this.logoSize = 88,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(height: 16),
        Text(
          AppConstants.appName,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Split bills, not friendships',
          style: TextStyle(
            fontSize: 14,
            color: color.withValues(alpha: 0.6),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// Horizontal logo + wordmark — used in app bars / nav headers.
class AppLogoHorizontal extends StatelessWidget {
  final double logoSize;

  const AppLogoHorizontal({super.key, this.logoSize = 32});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 10),
        Text(
          AppConstants.appName,
          style: TextStyle(
            fontSize: logoSize * 0.56,
            fontWeight: FontWeight.w800,
            color: AppConstants.primaryColor,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
