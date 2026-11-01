import 'package:flutter/material.dart';
import '../settings/settings.dart';
import 'chat_colors.dart';

class AppTheme {
  static ThemeData fromSettings(AppSettings s, {required bool isDark}) {
    // 根据配色方案选择 seedColor 和 ChatColors
    Color seed;
    ChatColors chat;
    switch (s.palette) {
      case PaletteOption.green:
        seed = const Color(0xFF07C160);
        chat = isDark ? ChatColors.greenDark() : ChatColors.greenLight();
        break;
      case PaletteOption.blue:
        seed = const Color(0xFF1C73E8);
        chat = isDark ? ChatColors.blueDark() : ChatColors.blueLight();
        break;
      case PaletteOption.orange:
        seed = const Color(0xFFDB6E00);
        chat = isDark ? ChatColors.orangeDark() : ChatColors.orangeLight();
        break;
      case PaletteOption.neutral:
        seed = const Color(0xFF2B2F36);
        chat = isDark ? ChatColors.neutralDark() : ChatColors.neutralLight();
        break;
    }

    // 字体栈：根据设置选择主字体与回退顺序
    String? primaryFamily;
    List<String> fallback = const [
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans SC',
      'Segoe UI',
      'Roboto',
    ];
    primaryFamily = (s.baseFontMode == BaseFontModeOption.miSansPreferred) ? 'MiSansVF' : null;

    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final scaffoldBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F6F7);

    // 基础 textTheme，应用主字体与回退
    var textTheme = base.textTheme.apply(
      fontFamily: primaryFamily,
      fontFamilyFallback: fallback,
    );

    // 装饰字体用于标题（可选）
    if (s.decoUseTitles && s.decoFamily != DecorativeFontFamily.none) {
      final fam = s.decoFamily == DecorativeFontFamily.fzg ? 'FZG' : 'nfdcs';
      textTheme = textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(fontFamily: fam),
        displayMedium: textTheme.displayMedium?.copyWith(fontFamily: fam),
        headlineLarge: textTheme.headlineLarge?.copyWith(fontFamily: fam),
        titleLarge: textTheme.titleLarge?.copyWith(fontFamily: fam),
      );
    }

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: base.colorScheme.onSurface,
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      extensions: <ThemeExtension<dynamic>>[chat],
    );
  }
}
