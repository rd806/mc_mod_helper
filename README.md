# MC Mod Helper

我的第一个 flutter 项目： 简易的 Minecraft 模组浏览应用，从模组站点
* [MC百科](https://www.mcmod.cn)
* [Modrinth](https://modrinth.com/)

获取模组信息。

> [!Note]
> 因为 MC百科 没有公开的官方 API，所以本应用通过模拟 HTTP 请求获取网页内容并转换为可读界面。
> 
> 开发时使用了 AI 辅助，仅用于学习交流。

## 功能

- [x] 浏览模组
- [x] 搜索模组
- [x] 查看模组详情与版本信息
- [ ] 收藏常用模组
- [ ] 多来源管理

因为 flutter 的 `flutter_widget_from_html` 插件在处理 MC百科 的HTML文本时会出现调试断言错误影响开发，因此使用了重写的 `html_content.dart`。

> 所以可支持的格式并不完全，但兼容性和观感较好。
> 
> 更多的格式以后应该会逐步补全。

## 说明

`mc_mod_helper.json` 是来自 [Ico moon](https://icomoon.io/app/#/select) 的图标文件集合。

