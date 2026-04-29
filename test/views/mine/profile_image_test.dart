import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile uses UiImage instead of extended_image directly', () {
    final source = File('lib/views/mine/profile.dart').readAsStringSync();

    expect(source, contains("package:haka_comic/widgets/ui_image.dart"));
    expect(source, contains('UiImage('));
    expect(
      source,
      isNot(contains("package:extended_image/extended_image.dart")),
    );
    expect(source, isNot(contains('ExtendedNetworkImageProvider')));
  });
}
