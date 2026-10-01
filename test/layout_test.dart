import 'package:flutter_test/flutter_test.dart';
import 'package:mc_mod_helper/setting/value/layout.dart';

/// 断言都按两个常量算出来,而不是写死 1280 / 24 ——
/// 以后调上限宽度,测试跟着走,不用改
double get _max => PageLayout.maxContentWidth;
double get _min => PageLayout.minPadding;

/// 临界宽度:再宽一点,多出来的就全给边距;刚好到这里时内容是满宽
double get _critical => _max + _min * 2;

void main() {
  test('paddingFor:内容宽到上限就封顶,多出来的都给边距', () {
    // 超宽屏:内容恒为上限宽,其余全是边距
    expect(PageLayout.paddingFor(_critical + 672), _min + 336);
    expect(PageLayout.paddingFor(_critical + 400), _min + 200);
    // 刚好到最小边距的临界宽度
    expect(PageLayout.paddingFor(_critical), _min);
  });

  test('paddingFor:比临界宽度窄时边距不再减(交给内容去缩)', () {
    for (final width in [_critical - 1, 1100.0, 1000.0, 800.0, 400.0]) {
      expect(PageLayout.paddingFor(width), _min, reason: '$width');
    }
  });

  test('收窄时先减边距:内容先保持上限宽,再往下才跟着缩', () {
    // 从很宽收到临界宽度这一段:边距一路减,内容一直是上限宽
    for (final width in [
      _critical + 400,
      _critical + 200,
      _critical + 1,
      _critical,
    ]) {
      expect(PageLayout.contentWidth(width), _max, reason: '$width');
    }
    // 再窄下去才轮到内容缩:边距已经守住最小,内容 = 宽 - 两边边距
    for (final width in [_critical - 1, 1100.0, 1000.0]) {
      expect(
        PageLayout.contentWidth(width),
        width - _min * 2,
        reason: '$width',
      );
    }
  });

  test('单调性:窗口越宽,边距不减、内容不缩', () {
    var lastPadding = 0.0;
    var lastContent = 0.0;
    for (var width = 320.0; width <= 2400; width += 37) {
      final padding = PageLayout.paddingFor(width);
      final content = PageLayout.contentWidth(width);
      expect(padding, greaterThanOrEqualTo(lastPadding), reason: '$width');
      expect(content, greaterThanOrEqualTo(lastContent), reason: '$width');
      expect(content, lessThanOrEqualTo(_max + 0.001));
      lastPadding = padding;
      lastContent = content;
    }
  });
}
