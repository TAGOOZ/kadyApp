import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppShadows.coffeeShadows(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryContainer],
            ),
          ),
          child: Icon(
            Icons.local_cafe,
            size: size * 0.45,
            color: AppColors.parchment,
          ),
        ),
      ),
    );
  }
}
