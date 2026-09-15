import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mc_mod_helper/widget/button/color_box.dart';

/// 把 ColorBox 放进最小页面,用 [onSaved] 接住回写值
Widget _wrap({
  Color value = Colors.blue,
  required ValueChanged<Color> onSaved,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ColorBox(title: '颜色种子', value: value, onSaved: onSaved),
    ),
  );
}

void main() {
  group('parseHexColor', () {
    test('接受 #RRGGBB,大小写与井号都可省', () {
      expect(parseHexColor('#3F51B5')?.toARGB32(), 0xFF3F51B5);
      expect(parseHexColor('3F51B5')?.toARGB32(), 0xFF3F51B5);
      expect(parseHexColor('#3f51b5')?.toARGB32(), 0xFF3F51B5);
      expect(parseHexColor('  #3f51b5  ')?.toARGB32(), 0xFF3F51B5);
    });

    test('#RGB 简写按每位重复展开', () {
      expect(parseHexColor('#abc')?.toARGB32(), 0xFFAABBCC);
      expect(parseHexColor('F0A')?.toARGB32(), 0xFFFF00AA);
    });

    test('解析出来的颜色一律不透明', () {
      // 种子色带透明度没有意义(8 位写法也不接受,避免调出"看着没生效"的颜色)
      expect(parseHexColor('#000000')?.a, 1.0);
      expect(parseHexColor('#FFFFFF')?.a, 1.0);
    });

    test('非法输入返回 null', () {
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#'), isNull);
      expect(parseHexColor('#12345'), isNull); // 位数不对
      expect(parseHexColor('#1234567'), isNull);
      expect(parseHexColor('#FF3F51B5'), isNull); // 带透明度的 8 位
      expect(parseHexColor('#gggggg'), isNull);
      expect(parseHexColor('蓝色'), isNull);
    });
  });

  group('formatHexColor', () {
    test('输出大写 #RRGGBB,并丢掉透明度', () {
      expect(formatHexColor(const Color(0xFF3F51B5)), '#3F51B5');
      expect(formatHexColor(const Color(0xFF000000)), '#000000');
      expect(formatHexColor(const Color(0x00FFFFFF)), '#FFFFFF');
      expect(formatHexColor(Colors.red), '#F44336');
    });

    test('与 parseHexColor 往返一致', () {
      for (final hex in ['#3F51B5', '#000000', '#FFFFFF', '#0A0B0C']) {
        expect(formatHexColor(parseHexColor(hex)!), hex);
      }
    });
  });

  group('ColorBox', () {
    testWidgets('行内显示当前色号与圆形色块', (tester) async {
      await tester.pumpWidget(
        _wrap(value: const Color(0xFF3F51B5), onSaved: (_) {}),
      );

      expect(find.text('颜色种子'), findsOneWidget);
      expect(find.text('#3F51B5'), findsOneWidget);
      expect(find.byType(ColorDot), findsOneWidget);
    });

    testWidgets('点击弹出输入框,填合法色号后确定写回', (tester) async {
      final saved = <Color>[];
      await tester.pumpWidget(_wrap(onSaved: saved.add));

      await tester.tap(find.text('颜色种子'));
      await tester.pumpAndSettle();
      // 输入框里预填当前色号
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '#2196F3',
      );

      await tester.enterText(find.byType(TextField), '#3f51b5');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.toARGB32(), 0xFF3F51B5);
      expect(find.byType(TextField), findsNothing); // 已关闭
    });

    testWidgets('色号非法:提示且不关闭、不写回', (tester) async {
      final saved = <Color>[];
      await tester.pumpWidget(_wrap(onSaved: saved.add));

      await tester.tap(find.text('颜色种子'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '#12345');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.textContaining('请输入十六进制色号'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // 对话框还开着
      expect(saved, isEmpty);

      // 改成合法值:提示消失,确定后写回
      await tester.enterText(find.byType(TextField), '3F51B5');
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入十六进制色号'), findsNothing);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(saved.single.toARGB32(), 0xFF3F51B5);
    });

    testWidgets('取消不改动', (tester) async {
      final saved = <Color>[];
      await tester.pumpWidget(_wrap(onSaved: saved.add));

      await tester.tap(find.text('颜色种子'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '#3F51B5');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
