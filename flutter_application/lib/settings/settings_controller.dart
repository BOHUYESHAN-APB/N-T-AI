import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';
import '../services/ai_client.dart';

class SettingsController extends ChangeNotifier {
  static const _kThemeMode = 'settings.themeMode';
  static const _kDensity = 'settings.density';
  static const _kTextScale = 'settings.textScale';
  static const _kChatBg = 'settings.chatBg';
  static const _kAiProvider = 'settings.ai.provider';
  static const _kAiBaseUrl = 'settings.ai.baseUrl';
  static const _kAiApiKey = 'settings.ai.apiKey';
  static const _kAiModel = 'settings.ai.model';
  static const _kAiProviders = 'settings.ai.providers';
  static const _kAiActiveId = 'settings.ai.activeId';
  static const _kAiRotationEnabled = 'settings.ai.rotationEnabled';
  static const _kPalette = 'settings.ui.palette';
  // Legacy font mode key (for migration only)
  static const _kFontMode = 'settings.ui.fontMode';
  // New font settings keys
  static const _kBaseFontMode = 'settings.ui.baseFontMode';
  static const _kDecoFamily = 'settings.ui.decoFamily';
  static const _kDecoUseTitles = 'settings.ui.decoUseTitles';
  static const _kDecoUseBubbles = 'settings.ui.decoUseBubbles';
  static const _kUiMode = 'settings.ui.uiMode';

  late SharedPreferences _prefs;
  AppSettings _settings = const AppSettings();
  int _rotationIndex = 0; // 内存轮换游标

  AppSettings get settings => _settings;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final themeIdx = _prefs.getInt(_kThemeMode);
    final densityIdx = _prefs.getInt(_kDensity);
    final textScale = _prefs.getDouble(_kTextScale) ?? 1.0;
    final chatBgIdx = _prefs.getInt(_kChatBg);
  final paletteIdx = _prefs.getInt(_kPalette);
  final aiProviderIdx = _prefs.getInt(_kAiProvider);
    // New font settings
    final baseFontIdx = _prefs.getInt(_kBaseFontMode);
    final decoFamilyIdx = _prefs.getInt(_kDecoFamily);
    final decoUseTitles = _prefs.getBool(_kDecoUseTitles);
    final decoUseBubbles = _prefs.getBool(_kDecoUseBubbles);
    // Legacy font mode (to migrate)
    final legacyFontModeIdx = _prefs.getInt(_kFontMode);
    // UI mode
    final uiModeIdx = _prefs.getInt(_kUiMode);
    final aiBaseUrl = _prefs.getString(_kAiBaseUrl) ?? '';
    final aiApiKey = _prefs.getString(_kAiApiKey) ?? '';
    final aiModel = _prefs.getString(_kAiModel) ?? '';

    // load legacy single-AI settings then attempt to load providers list
    final providersRaw = _prefs.getString(_kAiProviders);
    final activeId = _prefs.getString(_kAiActiveId);
  final rotationEnabled = _prefs.getBool(_kAiRotationEnabled) ?? false;

    List<AiProviderConfig> providers = [];
    if (providersRaw != null && providersRaw.isNotEmpty) {
      try {
        final List data = jsonDecode(providersRaw) as List;
        providers = data.map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        providers = [];
      }
    }

    // If no providers persisted, migrate legacy single ai settings into a default provider
    if (providers.isEmpty) {
      // Seed common presets to reduce user errors
      providers = [
        AiProviderConfig(id: 'openai', name: 'OpenAI', kind: AiProvider.openai, baseUrl: 'https://api.openai.com/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'deepseek', name: 'DeepSeek', kind: AiProvider.custom, baseUrl: 'https://api.deepseek.com/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'glm_cn', name: 'GLM · 智谱 (中国)', kind: AiProvider.custom, baseUrl: 'https://open.bigmodel.cn/api/paas/v4', isRoot: true, enabled: true),
        AiProviderConfig(id: 'glm_global', name: 'GLM · Z.ai (全球)', kind: AiProvider.custom, baseUrl: 'https://api.z.ai/api/paas/v4', isRoot: true, enabled: true),
        AiProviderConfig(id: 'openrouter', name: 'OpenRouter', kind: AiProvider.custom, baseUrl: 'https://openrouter.ai/api/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'groq', name: 'Groq', kind: AiProvider.custom, baseUrl: 'https://api.groq.com/openai/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'lmstudio', name: 'LM Studio (本地)', kind: AiProvider.local, baseUrl: 'http://127.0.0.1:1234/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'ollama', name: 'Ollama (本地)', kind: AiProvider.local, baseUrl: 'http://127.0.0.1:11434/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'together', name: 'Together.ai', kind: AiProvider.custom, baseUrl: 'https://api.together.xyz/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'fireworks', name: 'Fireworks', kind: AiProvider.custom, baseUrl: 'https://api.fireworks.ai/inference/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'siliconflow', name: 'SiliconFlow', kind: AiProvider.custom, baseUrl: 'https://api.siliconflow.cn/v1', isRoot: true, enabled: true),
        AiProviderConfig(id: 'kimi', name: 'Kimi · Moonshot', kind: AiProvider.custom, baseUrl: 'https://api.moonshot.cn/v1', isRoot: true, enabled: true),
      ];

      // If legacy single settings exist, add a migrated entry and set active to it
      String defaultActive = 'openai';
      final hasLegacy = (aiBaseUrl.isNotEmpty || aiApiKey.isNotEmpty || aiModel.isNotEmpty || aiProviderIdx != null);
      if (hasLegacy) {
        final migrated = AiProviderConfig(
          id: 'migrated',
          name: '迁移的配置',
          kind: AiProvider.values[safeIndex(aiProviderIdx, AiProvider.values.length, fallback: AiProvider.local.index)],
          baseUrl: aiBaseUrl,
          apiKey: aiApiKey,
          defaultModel: aiModel,
          isRoot: !(aiBaseUrl.contains('/chat/completions')), // heuristic
          enabled: true,
        );
        providers.insert(0, migrated);
        defaultActive = 'migrated';
      }
      await _prefs.setString(_kAiProviders, jsonEncode(providers.map((p) => p.toJson()).toList()));
      await _prefs.setString(_kAiActiveId, activeId ?? defaultActive);
    }

    // Derive font settings with migration from legacy FontModeOption if needed
    BaseFontModeOption baseFontMode = BaseFontModeOption.values[
      safeIndex(baseFontIdx, BaseFontModeOption.values.length, fallback: BaseFontModeOption.miSansPreferred.index)
    ];
    DecorativeFontFamily decoFamily = DecorativeFontFamily.values[
      safeIndex(decoFamilyIdx, DecorativeFontFamily.values.length, fallback: DecorativeFontFamily.none.index)
    ];
    bool useTitles = decoUseTitles ?? false;
    bool useBubbles = decoUseBubbles ?? false;

    // If only legacy exists, migrate once to the new fields
    final hasNewFontPrefs = baseFontIdx != null || decoFamilyIdx != null || decoUseTitles != null || decoUseBubbles != null;
    if (!hasNewFontPrefs && legacyFontModeIdx != null) {
      // Legacy mapping:
      // 0: system, 1: miSansPreferred, 2: fzgHeadings, 3: nfdcsHeadings
      switch (legacyFontModeIdx) {
        case 0:
          baseFontMode = BaseFontModeOption.system;
          decoFamily = DecorativeFontFamily.none;
          useTitles = false;
          useBubbles = false;
          break;
        case 2:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.fzg;
          useTitles = true;
          useBubbles = true;
          break;
        case 3:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.nfdcs;
          useTitles = true;
          useBubbles = true;
          break;
        case 1:
        default:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.none;
          useTitles = false;
          useBubbles = false;
      }
      // Persist migrated values
      await _prefs.setInt(_kBaseFontMode, baseFontMode.index);
      await _prefs.setInt(_kDecoFamily, decoFamily.index);
      await _prefs.setBool(_kDecoUseTitles, useTitles);
      await _prefs.setBool(_kDecoUseBubbles, useBubbles);
    }

    _settings = AppSettings(
      themeMode: ThemeModeOption.values[safeIndex(themeIdx, ThemeModeOption.values.length, fallback: ThemeModeOption.system.index)],
      density: DensityOption.values[safeIndex(densityIdx, DensityOption.values.length, fallback: DensityOption.normal.index)],
      textScale: textScale.clamp(0.9, 1.4),
  chatBg: ChatBgOption.values[safeIndex(chatBgIdx, ChatBgOption.values.length, fallback: ChatBgOption.none.index)],
      palette: PaletteOption.values[safeIndex(paletteIdx, PaletteOption.values.length, fallback: PaletteOption.neutral.index)],
      uiMode: UIModeOption.values[safeIndex(uiModeIdx, UIModeOption.values.length, fallback: UIModeOption.auto.index)],
      baseFontMode: baseFontMode,
      decoFamily: decoFamily,
      decoUseTitles: useTitles,
      decoUseBubbles: useBubbles,
      ai: AiSettings(
        provider: AiProvider.values[safeIndex(aiProviderIdx, AiProvider.values.length, fallback: AiProvider.local.index)],
        baseUrl: aiBaseUrl,
        apiKey: aiApiKey,
        model: aiModel,
      ),
      providers: providers,
      activeProviderId: activeId ?? providers.first.id,
      rotationEnabled: rotationEnabled,
    );
    notifyListeners();
  }

  Future<void> setUiMode(UIModeOption m) async {
    _settings = _settings.copyWith(uiMode: m);
    await _prefs.setInt(_kUiMode, m.index);
    notifyListeners();
  }

  int safeIndex(int? i, int len, {required int fallback}) {
    if (i == null) return fallback;
    if (i < 0 || i >= len) return fallback;
    return i;
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _prefs.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setDensity(DensityOption d) async {
    _settings = _settings.copyWith(density: d);
    await _prefs.setInt(_kDensity, d.index);
    notifyListeners();
  }

  Future<void> setTextScale(double s) async {
    _settings = _settings.copyWith(textScale: s);
    await _prefs.setDouble(_kTextScale, s);
    notifyListeners();
  }

  Future<void> setChatBg(ChatBgOption b) async {
    _settings = _settings.copyWith(chatBg: b);
    await _prefs.setInt(_kChatBg, b.index);
    notifyListeners();
  }

  Future<void> setPalette(PaletteOption p) async {
    _settings = _settings.copyWith(palette: p);
    await _prefs.setInt(_kPalette, p.index);
    notifyListeners();
  }

  Future<void> setBaseFontMode(BaseFontModeOption m) async {
    _settings = _settings.copyWith(baseFontMode: m);
    await _prefs.setInt(_kBaseFontMode, m.index);
    notifyListeners();
  }

  Future<void> setDecoFamily(DecorativeFontFamily f) async {
    _settings = _settings.copyWith(decoFamily: f);
    await _prefs.setInt(_kDecoFamily, f.index);
    notifyListeners();
  }

  Future<void> setDecoUseTitles(bool v) async {
    _settings = _settings.copyWith(decoUseTitles: v);
    await _prefs.setBool(_kDecoUseTitles, v);
    notifyListeners();
  }

  Future<void> setDecoUseBubbles(bool v) async {
    _settings = _settings.copyWith(decoUseBubbles: v);
    await _prefs.setBool(_kDecoUseBubbles, v);
    notifyListeners();
  }

  Future<void> setAiProvider(AiProvider p) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(provider: p));
    await _prefs.setInt(_kAiProvider, p.index);
    notifyListeners();
  }

  Future<void> setAiBaseUrl(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(baseUrl: v));
    await _prefs.setString(_kAiBaseUrl, v);
    notifyListeners();
  }

  Future<void> setAiApiKey(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(apiKey: v));
    await _prefs.setString(_kAiApiKey, v);
    notifyListeners();
  }

  Future<void> setAiModel(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(model: v));
    await _prefs.setString(_kAiModel, v);
    notifyListeners();
  }

  ThemeMode get themeMode => _settings.materialThemeMode;

  // Providers management
  List<AiProviderConfig> get providers => _settings.providers;
  String? get activeProviderId => _settings.activeProviderId;
  bool get rotationEnabled => _settings.rotationEnabled;

  Future<void> _saveProviders(List<AiProviderConfig> list, {String? activeId}) async {
    final data = list.map((p) => p.toJson()).toList();
    await _prefs.setString(_kAiProviders, jsonEncode(data));
    if (activeId != null) await _prefs.setString(_kAiActiveId, activeId);
    _settings = _settings.copyWith(providers: list, activeProviderId: activeId ?? _settings.activeProviderId);
    notifyListeners();
  }

  Future<void> setActiveProvider(String id) async {
    await _prefs.setString(_kAiActiveId, id);
    _settings = _settings.copyWith(activeProviderId: id);
    notifyListeners();
  }

  Future<void> setRotationEnabled(bool enabled) async {
    await _prefs.setBool(_kAiRotationEnabled, enabled);
    _settings = _settings.copyWith(rotationEnabled: enabled);
    notifyListeners();
  }

  AiProviderConfig? get activeProviderConfig {
    final id = _settings.activeProviderId;
    if (id == null) {
      return _settings.providers.isNotEmpty ? _settings.providers.first : null;
    }
    for (final p in _settings.providers) {
      if (p.id == id) return p;
    }
    return _settings.providers.isNotEmpty ? _settings.providers.first : null;
  }

  AiSettings resolveActiveAi() {
    final p = activeProviderConfig;
    if (p == null) return _settings.ai;
    return AiSettings(
      provider: p.kind,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.defaultModel.isNotEmpty ? p.defaultModel : _settings.ai.model,
    );
  }

  Future<void> addOrUpdateProvider(AiProviderConfig cfg) async {
    final list = [..._settings.providers];
    final idx = list.indexWhere((p) => p.id == cfg.id);
    if (idx == -1) list.add(cfg); else list[idx] = cfg;
    await _saveProviders(list, activeId: _settings.activeProviderId ?? cfg.id);
  }

  Future<void> removeProvider(String id) async {
    final list = _settings.providers.where((p) => p.id != id).toList();
    await _saveProviders(list, activeId: list.isNotEmpty ? list.first.id : null);
  }

  Future<void> setProviderEnabled(String id, bool enabled) async {
    final idx = _settings.providers.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final updated = _settings.providers[idx].copyWith(enabled: enabled);
    await addOrUpdateProvider(updated);
  }

  Future<void> setProviderField(String id, {String? baseUrl, String? apiKey, String? defaultModel, String? name}) async {
    final idx = _settings.providers.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final cur = _settings.providers[idx];
    final updated = cur.copyWith(
      baseUrl: baseUrl ?? cur.baseUrl,
      apiKey: apiKey ?? cur.apiKey,
      defaultModel: defaultModel ?? cur.defaultModel,
      name: name ?? cur.name,
    );
    await addOrUpdateProvider(updated);
  }

  Future<void> setProviderRotate(String id, bool rotate) async {
    final idx = _settings.providers.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final updated = _settings.providers[idx].copyWith(rotate: rotate);
    await addOrUpdateProvider(updated);
  }

  Future<void> setProviderRpm(String id, int? rpm) async {
    final idx = _settings.providers.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final updated = _settings.providers[idx].copyWith(rpm: rpm);
    await addOrUpdateProvider(updated);
  }

  AiProviderConfig? getProviderById(String id) {
    try {
      return _settings.providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  AiSettings resolveFromConfig(AiProviderConfig p) {
    return AiSettings(
      provider: p.kind,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.defaultModel.isNotEmpty ? p.defaultModel : _settings.ai.model,
    );
  }

  // 根据轮换策略选择下一个平台（若未启用轮换则返回当前激活平台）
  AiProviderConfig? selectProviderForNextCall() {
    if (_settings.rotationEnabled) {
      final pool = _settings.providers.where((p) => p.enabled && p.rotate).toList();
      if (pool.isNotEmpty) {
        _rotationIndex = (_rotationIndex + 1) % pool.length;
        return pool[_rotationIndex];
      }
    }
    return activeProviderConfig;
  }

  // 获取并缓存模型列表
  Future<List<String>> fetchModelsForProvider(String id) async {
    final cfg = getProviderById(id);
    if (cfg == null) return const [];
    final ai = resolveFromConfig(cfg);
    final models = await AiClient.fetchModels(ai: ai, baseUrlIsRoot: cfg.isRoot);
    final updated = cfg.copyWith(
      modelCatalog: models,
      modelCatalogFetchedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await addOrUpdateProvider(updated);
    return models;
  }

  Future<String> testProvider(String id) async {
    final cfg = getProviderById(id);
    if (cfg == null) return '未找到配置';
    final ai = resolveFromConfig(cfg);
    final msg = await AiClient.testConnection(ai: ai, baseUrlIsRoot: cfg.isRoot);
    return msg;
  }
}
