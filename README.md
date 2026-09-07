# MC Mod Helper

我的第一个 flutter 项目：简易的 Minecraft 模组浏览应用，从模组站点获取模组信息。

当前支持的站点：
* [MC百科](https://www.mcmod.cn)
* [Modrinth](https://modrinth.com/)

页面布局参考了 Modrinth 官网。

> [!Note]
> 因为 MC百科 没有公开的官方 API，所以本应用通过模拟 HTTP 请求获取网页内容并转换为可读界面。
> 
> 由于 CurseForge 的 API 需要申请 API key，因此暂不真正实现，仅保留选项接口。
> 
> 开发时使用了 AI（没错，就是蓝色大肥鱼 DeepSeek！）辅助，仅用于学习交流。

## 功能

- [x] 浏览模组
- [x] 搜索模组（允许聚合搜索）
- [x] 查看模组详情：版本信息，加载环境，开发团队，支持版本，详细描述
- [x] 验证处理
- [x] 收藏模组（数据存储在本地）
- [ ] 来源管理

## 页面渲染实现

因为尚未找到符合要求的通用渲染方法：
* `flutter_html` 暂不兼容当前的 flutter 版本。
* `flutter_widget_from_html` 插件在处理 **MC百科** 的 HTML 文本时会出现调试断言错误影响开发。 
* `flutter_markdown_plus` 无法处理 HTML 标签。

同时又不想内嵌一个浏览器。

> 核心是难以处理表格（带图片的表格，合并单元格的表格）内容。如有更好的方法，欢迎提出 issue！

所以暂时使用以下替代方法（可以在设置中切换）：

### 默认

使用了一个重写的轻量 HTML 渲染器（位于 `render/default_render/` ），支持的格式并不完全，但兼容性和观感较好。

> 现已实现：
> * 图片表格（画廊）的较好渲染（DeepSeek NB！）。
> * 含合并单元格表格的正确处理。
> 
> 更多的格式以后应该会逐步补充。

### Hyper

直接调用 `HyperViewer` 的渲染方法，虽然格式更全面但存在兼容性问题（如表头格式异常，单元格内的超链接失效？...）。

## 构建方法

克隆本仓库到本地，使用

```shell
# 构建 Windows 端应用
flutter build windows

# 构建 Android 应用
flutter build apk
```

构建应用。

> [!Note]
> 如果遇到构建失败错误，可能是因为在联网下载 sqlite 库时网络不通畅，可通过使用代理或手动下载库文件解决。

另外，`test/` 文件夹中包含若干测试文件（出自DeepSeek），可使用 

```shell
flutter test
```

进行全量测试。

## 说明

* `mc_mod_helper.json` 是来自 [Ico moon](https://icomoon.io/new-app/) 的图标文件集合。
* `UPDATE.md` 存放更新描述。

