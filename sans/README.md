# 字体与授权（sans 目录）

本目录包含 3 套字体：

- FZG（FZG_CN.ttf、FZG_HAX.ttf）
  - 授权：SIL Open Font License 1.1（OFL-1.1）
  - 许可文件：`FZG/OFL-1.1.txt`（英文官方），`FZG/OFL-1.1-zh-CN-UNOFFICIAL.md`（非官方中文翻译，供参考）
- Misans（MiSans VF.ttf）
  - 授权：小米《MiSans 字体知识产权许可协议》
  - 许可文件：`Misans/协议`（原文）
- nfdcs（文件位于 `sans/nfdcs/`）
  - 授权：作者声明“基于 MIT 和 ISAS”的自定义许可
  - 许可文件：`nfdcs/LICENSE.txt`

## 字体使用与回退策略

- 默认显示优先使用系统字体，确保系统级字形/Hinting 的一致性与可读性。
- 若遇到字形缺失（Glyph missing），再回退到 MiSans（因其字库更完整）。
- FZG、nfdcs 作为美观性字体参与局部展示（标题/装饰等），不作为通用默认字体，以避免在字符覆盖不足时出现显示不完整的问题。

该回退策略仅描述渲染优先级；实际生效依赖于应用内的字体栈/Theme 配置（例如 Flutter 中的 TextTheme 与字体族注册）。
