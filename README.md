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

## 渲染方法

因为尚未找到符合要求的通用渲染方法：
* flutter 的 `flutter_widget_from_html` 插件在处理 MC百科 的HTML文本时会出现调试断言错误影响开发。 
* flutter 的 `flutter_markdown_plus` 无法处理 HTML 标签。

> 核心是难以处理带图片的表格内容。如有更好的方法欢迎提出 issue！

所以暂时使用以下替代方法，核心思路是将所有文本转换为 HTML 格式。

### 默认管线

使用了重写的 `html_content.dart`，可支持的格式并不完全，但兼容性和观感较好。

> 更多的格式以后应该会逐步补全。

### HyperViewer

直接调用 HyperViewer 的渲染方法，虽然格式更全面但存在兼容性问题（如表格内的超链接打不开）。

## 说明

`mc_mod_helper.json` 是来自 [Ico moon](https://icomoon.io/app/#/select) 的图标文件集合。

