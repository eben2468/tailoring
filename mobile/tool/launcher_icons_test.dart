// Generates the Android launcher icons from the in-app BrandMark widget (temporary brand mark
// until the final Nutɔfe logo is supplied). Run from mobile/:
//
//   flutter test tool/launcher_icons_test.dart --update-goldens
//
// Writes android/app/src/main/res/mipmap-*/ic_launcher.png (48–192 px). Not part of the normal test run.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/widgets/brand_mark.dart';

const _densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};

void main() {
  setUpAll(() async {
    await (FontLoader('PlusJakartaSans')..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'))).load();
  });

  for (final entry in _densities.entries) {
    testWidgets('ic_launcher ${entry.key} (${entry.value}px)', (tester) async {
      final size = entry.value.toDouble();
      tester.view.physicalSize = Size(size, size);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            child: SizedBox.square(
              dimension: size,
              // ~8% inset like Material launcher icons; transparent corners.
              child: Center(child: BrandMark(size: size * 0.84)),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('../android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png'),
      );
    });
  }
}
