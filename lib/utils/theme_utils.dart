import 'package:flutter/material.dart';
import 'app_theme.dart';

extension ContextColors on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceColor => isDarkMode ? AppColors.darkSurface : AppColors.surface;
  Color get surfaceVariantColor => isDarkMode ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant;
  Color get backgroundColor => isDarkMode ? AppColors.darkBackground : AppColors.background;
  Color get borderColor => isDarkMode ? AppColors.darkBorder : AppColors.border;
  Color get dividerColor => isDarkMode ? AppColors.darkDivider : AppColors.divider;

  Color get textPrimaryColor => isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get textSecondaryColor => isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get textHintColor => isDarkMode ? AppColors.darkTextHint : AppColors.textHint;
}
