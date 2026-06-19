import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The "CnC" brand mark. Rounded square, brand-green fill, white bold text.
/// [light] renders white-on-transparent for dark backgrounds (splash).
class BrandLogo extends StatelessWidget {
  final double size;
  final bool light;
  const BrandLogo({super.key, this.size = 40, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.18) : AppColors.brand600,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: light
            ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Text(
        'CnC',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.34,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
