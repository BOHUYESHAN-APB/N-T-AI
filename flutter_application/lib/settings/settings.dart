import 'package:flutter/material.dart';

enum ThemeModeOption { system, light, dark }

enum DensityOption { compact, normal, spacious }

enum ChatBgOption { none, lavender }

enum AiProvider { local, openai, custom }

// 配色方案：简约（中性）、绿色、蓝色、橙色
enum PaletteOption { neutral, green, blue, orange }

// 对话界面样式：自动（根据设备/尺寸做轻量判断）、气泡（丰富动效与圆角）、简洁（更省资源）
enum UIModeOption { auto, bubble, simple }

// 字体模式：系统默认、优先 MiSans、FZG 用于标题
// 基础字体模式：是否全局优先 MiSans
enum BaseFontModeOption { system, miSansPreferred }

// 装饰字体家族：用于标题/聊天气泡等可选应用
enum DecorativeFontFamily { none, fzg, nfdcs }

class AiSettings {
  final AiProvider provider;
  final String baseUrl; // 对于 openai 可留空（使用默认），custom 需要填写
  final String apiKey; // 对于 local 可留空
  final String model;  // 例如 gpt-4o, llama3.1:8b 等

  const AiSettings({
    this.provider = AiProvider.local,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  AiSettings copyWith({
    AiProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) => AiSettings(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

class AiProviderConfig {
  final String id; // 唯一 id
  final String name; // 显示名称
  final AiProvider kind; // enum for compatibility: local/openai/custom
  final bool enabled; // 是否启用
  final String baseUrl;
  final String apiKey;
  final String defaultModel; // 可选默认模型
  final bool isRoot; // baseUrl 是否为根路径，需要自动追加 /chat/completions
  final bool rotate; // 是否参与轮换
  final int? rpm; // 每分钟请求上限（可选）
  final List<String>? modelCatalog; // 缓存的模型列表
  final int? modelCatalogFetchedAt; // 缓存时间（epochMillis）

  const AiProviderConfig({
    required this.id,
    required this.name,
    this.kind = AiProvider.custom,
    this.enabled = true,
    this.baseUrl = '',
    this.apiKey = '',
    this.defaultModel = '',
    this.isRoot = true,
    this.rotate = false,
    this.rpm = null,
    this.modelCatalog = null,
    this.modelCatalogFetchedAt = null,
  });

  AiProviderConfig copyWith({
    String? id,
    String? name,
    AiProvider? kind,
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? defaultModel,
    bool? isRoot,
    bool? rotate,
    int? rpm,
    List<String>? modelCatalog,
    int? modelCatalogFetchedAt,
  }) => AiProviderConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        defaultModel: defaultModel ?? this.defaultModel,
        isRoot: isRoot ?? this.isRoot,
        rotate: rotate ?? this.rotate,
        rpm: rpm ?? this.rpm,
        modelCatalog: modelCatalog ?? this.modelCatalog,
        modelCatalogFetchedAt: modelCatalogFetchedAt ?? this.modelCatalogFetchedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'enabled': enabled,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'defaultModel': defaultModel,
        'isRoot': isRoot,
        'rotate': rotate,
        'rpm': rpm,
        'modelCatalog': modelCatalog,
        'modelCatalogFetchedAt': modelCatalogFetchedAt,
      };

  static AiProviderConfig fromJson(Map<String, dynamic> j) => AiProviderConfig(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        kind: _kindFrom(j['kind'] as String? ?? 'custom'),
        enabled: j['enabled'] as bool? ?? true,
        baseUrl: j['baseUrl'] as String? ?? '',
        apiKey: j['apiKey'] as String? ?? '',
    defaultModel: j['defaultModel'] as String? ?? '',
    isRoot: j['isRoot'] as bool? ?? true,
    rotate: j['rotate'] as bool? ?? false,
    rpm: j['rpm'] as int?,
    modelCatalog: (j['modelCatalog'] as List?)?.map((e) => e.toString()).toList(),
    modelCatalogFetchedAt: j['modelCatalogFetchedAt'] as int?,
      );

  static AiProvider _kindFrom(String s) {
    switch (s) {
      case 'local':
        return AiProvider.local;
      case 'openai':
        return AiProvider.openai;
      default:
        return AiProvider.custom;
    }
  }
}

class AppSettings {
  final ThemeModeOption themeMode;
  final DensityOption density;
  final double textScale; // 0.9 ~ 1.4
  final ChatBgOption chatBg;
  final PaletteOption palette; // 配色方案
  final UIModeOption uiMode; // 对话界面样式
  // 字体
  final BaseFontModeOption baseFontMode; // 基础字体（是否优先 MiSans）
  final DecorativeFontFamily decoFamily; // 装饰字体家族（FZG / nfdcs / none）
  final bool decoUseTitles;   // 装饰字体用于标题
  final bool decoUseBubbles;  // 装饰字体用于聊天气泡
  final AiSettings ai;
  final List<AiProviderConfig> providers; // 多供应商配置
  final String? activeProviderId; // 选中的 provider id
  final bool rotationEnabled; // 启用多平台轮换

  const AppSettings({
    this.themeMode = ThemeModeOption.system,
    this.density = DensityOption.normal,
    this.textScale = 1.0,
    // 默认关闭紫色背景，采用素雅配色
    this.chatBg = ChatBgOption.none,
  this.palette = PaletteOption.neutral,
    this.uiMode = UIModeOption.auto,
    this.baseFontMode = BaseFontModeOption.miSansPreferred,
    this.decoFamily = DecorativeFontFamily.none,
    this.decoUseTitles = false,
    this.decoUseBubbles = false,
    this.ai = const AiSettings(),
    this.providers = const [],
    this.activeProviderId,
    this.rotationEnabled = false,
  });

  AppSettings copyWith({
    ThemeModeOption? themeMode,
    DensityOption? density,
    double? textScale,
    ChatBgOption? chatBg,
    PaletteOption? palette,
    UIModeOption? uiMode,
    BaseFontModeOption? baseFontMode,
    DecorativeFontFamily? decoFamily,
    bool? decoUseTitles,
    bool? decoUseBubbles,
    AiSettings? ai,
    List<AiProviderConfig>? providers,
    String? activeProviderId,
    bool? rotationEnabled,
  }) => AppSettings(
        themeMode: themeMode ?? this.themeMode,
        density: density ?? this.density,
        textScale: textScale ?? this.textScale,
        chatBg: chatBg ?? this.chatBg,
        palette: palette ?? this.palette,
  uiMode: uiMode ?? this.uiMode,
        baseFontMode: baseFontMode ?? this.baseFontMode,
        decoFamily: decoFamily ?? this.decoFamily,
        decoUseTitles: decoUseTitles ?? this.decoUseTitles,
        decoUseBubbles: decoUseBubbles ?? this.decoUseBubbles,
        ai: ai ?? this.ai,
        providers: providers ?? this.providers,
        activeProviderId: activeProviderId ?? this.activeProviderId,
        rotationEnabled: rotationEnabled ?? this.rotationEnabled,
      );

  ThemeMode get materialThemeMode => switch (themeMode) {
        ThemeModeOption.light => ThemeMode.light,
        ThemeModeOption.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
