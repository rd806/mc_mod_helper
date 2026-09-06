/// 详情页面渲染方法
enum RenderType { auto, hyper }

class RenderManager {
  /// 字符串转枚举类
  static RenderType displayToString(String? value) {
    return RenderType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RenderType.auto,
    );
  }
}
