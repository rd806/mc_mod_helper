/// 页面内容宽度策略,照 Modrinth 网页的做法:
/// **内容宽到 [maxContentWidth] 就封顶**,再宽出来的部分全给左右边距;
/// 反过来,窗口收窄时**先减边距**,减到 [minPadding] 之后内容才跟着缩。
///
/// 对比按比例算边距(如「宽度的 15%」):那种写法内容永远只占窗口的固定比例,
/// 窗口一收窄,边距和内容一起缩 —— 明明还有富余的横向空间,正文却先挤了。
class PageLayout {
  const PageLayout._();

  /// 内容最大宽度(Modrinth 的 max-w-7xl = 80rem = 1280,这里取得略窄)
  static const double maxContentWidth = 1200;

  /// 最小边距:内容缩到上限以下后,边距不再继续减
  static const double minPadding = 24;

  /// 按可用宽度算左右边距。
  ///
  /// - `width >= maxContentWidth + 2 * minPadding`:内容恒为 [maxContentWidth],
  ///   多出来的都给边距;
  /// - 更窄:边距守住 [minPadding],内容 = `width - 2 * minPadding` 跟着缩。
  static double paddingFor(double width) {
    final side = (width - maxContentWidth) / 2;
    return side > minPadding ? side : minPadding;
  }

  /// 内容宽度(可用宽度减去两侧边距)
  static double contentWidth(double width) => width - paddingFor(width) * 2;
}
