import 'dart:ui';
import 'package:flutter/material.dart';

// 通用毛玻璃容器（玻璃拟态）
class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final BorderRadius borderRadius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final BoxBorder? border;

  const Glass({
    super.key,
    required this.child,
    this.blur = 18,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.tint,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
  final bg = tint ?? (isDark
    ? Colors.white.withValues(alpha: 0.06)
    : Colors.white.withValues(alpha: 0.55));

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: borderRadius,
            border: border ?? Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
