import 'package:flutter/material.dart';

class ChatColors extends ThemeExtension<ChatColors> {
  final Color mineBubbleBg;
  final Color mineText;
  final Color otherBubbleBg;
  final Color otherText;
  final Color mineBorder;
  final Color otherBorder;
  final Color attachmentMineBg;
  final Color attachmentOtherBg;
  final Color link;
  final Color badgeBg;
  final Color badgeText;
  final Color timeMine;
  final Color timeOther;

  const ChatColors({
    required this.mineBubbleBg,
    required this.mineText,
    required this.otherBubbleBg,
    required this.otherText,
    required this.mineBorder,
    required this.otherBorder,
    required this.attachmentMineBg,
    required this.attachmentOtherBg,
    required this.link,
    required this.badgeBg,
    required this.badgeText,
    required this.timeMine,
    required this.timeOther,
  });

  @override
  ChatColors copyWith({
    Color? mineBubbleBg,
    Color? mineText,
    Color? otherBubbleBg,
    Color? otherText,
    Color? mineBorder,
    Color? otherBorder,
    Color? attachmentMineBg,
    Color? attachmentOtherBg,
    Color? link,
    Color? badgeBg,
    Color? badgeText,
    Color? timeMine,
    Color? timeOther,
  }) => ChatColors(
        mineBubbleBg: mineBubbleBg ?? this.mineBubbleBg,
        mineText: mineText ?? this.mineText,
        otherBubbleBg: otherBubbleBg ?? this.otherBubbleBg,
        otherText: otherText ?? this.otherText,
        mineBorder: mineBorder ?? this.mineBorder,
        otherBorder: otherBorder ?? this.otherBorder,
        attachmentMineBg: attachmentMineBg ?? this.attachmentMineBg,
        attachmentOtherBg: attachmentOtherBg ?? this.attachmentOtherBg,
        link: link ?? this.link,
        badgeBg: badgeBg ?? this.badgeBg,
        badgeText: badgeText ?? this.badgeText,
        timeMine: timeMine ?? this.timeMine,
        timeOther: timeOther ?? this.timeOther,
      );

  @override
  ThemeExtension<ChatColors> lerp(ThemeExtension<ChatColors>? other, double t) {
    if (other is! ChatColors) return this;
    return ChatColors(
      mineBubbleBg: Color.lerp(mineBubbleBg, other.mineBubbleBg, t)!,
      mineText: Color.lerp(mineText, other.mineText, t)!,
      otherBubbleBg: Color.lerp(otherBubbleBg, other.otherBubbleBg, t)!,
      otherText: Color.lerp(otherText, other.otherText, t)!,
      mineBorder: Color.lerp(mineBorder, other.mineBorder, t)!,
      otherBorder: Color.lerp(otherBorder, other.otherBorder, t)!,
      attachmentMineBg: Color.lerp(attachmentMineBg, other.attachmentMineBg, t)!,
      attachmentOtherBg: Color.lerp(attachmentOtherBg, other.attachmentOtherBg, t)!,
      link: Color.lerp(link, other.link, t)!,
      badgeBg: Color.lerp(badgeBg, other.badgeBg, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      timeMine: Color.lerp(timeMine, other.timeMine, t)!,
      timeOther: Color.lerp(timeOther, other.timeOther, t)!,
    );
  }

  // Presets
  static ChatColors neutralLight() => const ChatColors(
        mineBubbleBg: Color(0xFFF6F7F8),
        mineText: Color(0xFF0F1115),
        otherBubbleBg: Colors.white,
        otherText: Color(0xFF0F1115),
    mineBorder: Color(0xFFE5E7EB),
    otherBorder: Color(0xFFE6E8EB),
        attachmentMineBg: Color(0xFFE8EAED),
        attachmentOtherBg: Color(0xFFF3F4F6),
        link: Color(0xFF007AFF),
        badgeBg: Color(0xFFEDEEF0),
        badgeText: Color(0xFF4B5563),
    timeMine: Color(0xFF6B7280),
    timeOther: Color(0xFF6B7280),
      );

  static ChatColors neutralDark() => const ChatColors(
        mineBubbleBg: Color(0xFF1E1F22),
        mineText: Color(0xFFEDEFF2),
        otherBubbleBg: Color(0xFF141516),
        otherText: Color(0xFFEDEFF2),
    mineBorder: Color(0xFF2A2B2E),
    otherBorder: Color(0xFF232427),
        attachmentMineBg: Color(0xFF2A2B2E),
        attachmentOtherBg: Color(0xFF1E1F22),
        link: Color(0xFF5AA8FF),
        badgeBg: Color(0xFF2A2B2E),
        badgeText: Color(0xFFC9CDD2),
    timeMine: Color(0xFF9AA0A6),
    timeOther: Color(0xFF9AA0A6),
      );

  static ChatColors greenLight() => const ChatColors(
        mineBubbleBg: Color(0xFFE6F5EC),
        mineText: Color(0xFF0B2E1D),
        otherBubbleBg: Colors.white,
        otherText: Color(0xFF0F1115),
    mineBorder: Color(0xFFC9E9D7),
    otherBorder: Color(0xFFE6E8EB),
        attachmentMineBg: Color(0xFFD7EEE2),
        attachmentOtherBg: Color(0xFFF3F4F6),
        link: Color(0xFF0FA968),
        badgeBg: Color(0xFFE3F3EA),
        badgeText: Color(0xFF0E7C4D),
    timeMine: Color(0xFF5F7A6D),
    timeOther: Color(0xFF6B7280),
      );

  static ChatColors greenDark() => const ChatColors(
        mineBubbleBg: Color(0xFF163D2A),
        mineText: Color(0xFFD7F2E4),
        otherBubbleBg: Color(0xFF141516),
        otherText: Color(0xFFEDEFF2),
    mineBorder: Color(0xFF1E4A34),
    otherBorder: Color(0xFF232427),
        attachmentMineBg: Color(0xFF214736),
        attachmentOtherBg: Color(0xFF1E1F22),
        link: Color(0xFF43D399),
        badgeBg: Color(0xFF1E4A34),
        badgeText: Color(0xFFC6F1DF),
    timeMine: Color(0xFFA3CDB9),
    timeOther: Color(0xFF9AA0A6),
      );

  static ChatColors blueLight() => const ChatColors(
        mineBubbleBg: Color(0xFFE8F1FD),
        mineText: Color(0xFF0C2544),
        otherBubbleBg: Colors.white,
        otherText: Color(0xFF0F1115),
    mineBorder: Color(0xFFD9E7FB),
    otherBorder: Color(0xFFE6E8EB),
        attachmentMineBg: Color(0xFFDDE9FB),
        attachmentOtherBg: Color(0xFFF3F4F6),
        link: Color(0xFF1C73E8),
        badgeBg: Color(0xFFE5EFFD),
        badgeText: Color(0xFF1C4B8C),
    timeMine: Color(0xFF5C6C84),
    timeOther: Color(0xFF6B7280),
      );

  static ChatColors blueDark() => const ChatColors(
        mineBubbleBg: Color(0xFF0E2843),
        mineText: Color(0xFFD7E6FF),
        otherBubbleBg: Color(0xFF141516),
        otherText: Color(0xFFEDEFF2),
    mineBorder: Color(0xFF173156),
    otherBorder: Color(0xFF232427),
        attachmentMineBg: Color(0xFF18395F),
        attachmentOtherBg: Color(0xFF1E1F22),
        link: Color(0xFF63A6FF),
        badgeBg: Color(0xFF173156),
        badgeText: Color(0xFFCFE2FF),
    timeMine: Color(0xFFA8C5FF),
    timeOther: Color(0xFF9AA0A6),
      );

  static ChatColors orangeLight() => const ChatColors(
        mineBubbleBg: Color(0xFFFFF1E6),
        mineText: Color(0xFF4A260A),
        otherBubbleBg: Colors.white,
        otherText: Color(0xFF0F1115),
    mineBorder: Color(0xFFFFE2CC),
    otherBorder: Color(0xFFE6E8EB),
        attachmentMineBg: Color(0xFFFFE5D2),
        attachmentOtherBg: Color(0xFFF3F4F6),
        link: Color(0xFFDB6E00),
        badgeBg: Color(0xFFFFE9D9),
        badgeText: Color(0xFF9B3E00),
    timeMine: Color(0xFF73543D),
    timeOther: Color(0xFF6B7280),
      );

  static ChatColors orangeDark() => const ChatColors(
        mineBubbleBg: Color(0xFF3E2410),
        mineText: Color(0xFFFFE5D2),
        otherBubbleBg: Color(0xFF141516),
        otherText: Color(0xFFEDEFF2),
    mineBorder: Color(0xFF4A2B12),
    otherBorder: Color(0xFF232427),
        attachmentMineBg: Color(0xFF4B2B13),
        attachmentOtherBg: Color(0xFF1E1F22),
        link: Color(0xFFFFA45C),
        badgeBg: Color(0xFF4A2B12),
        badgeText: Color(0xFFFFE0CC),
    timeMine: Color(0xFFF4C7A6),
    timeOther: Color(0xFF9AA0A6),
      );
}
