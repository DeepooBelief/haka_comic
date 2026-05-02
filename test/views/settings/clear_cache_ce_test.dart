import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clear cache only uses cached_network_image_ce image cache', () {
    final source = File(
      'lib/views/settings/clear_cache.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("package:cached_network_image_ce/cached_network_image.dart"),
    );
    expect(
      source,
      contains('CachedNetworkImageProvider.defaultCacheManager.emptyCache()'),
    );
    expect(source, contains("'cached_network_image_ce'"));
    expect(
      source,
      isNot(contains("package:extended_image/extended_image.dart")),
    );
    expect(source, isNot(contains('cacheImageFolderName')));
  });
}
