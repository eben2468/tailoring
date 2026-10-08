import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Global test setup: a tap that misses its target (e.g. hidden behind the bottom bar) fails the test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
