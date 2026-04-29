import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/database/images_helper.dart';
import 'package:haka_comic/views/reader/widgets/reader_image.dart';

void main() {
  test('ReaderImage CE uses cached_network_image_ce package fade', () {
    final source = File(
      'lib/views/reader/widgets/reader_image.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("package:cached_network_image_ce/cached_network_image.dart"),
    );
    expect(source, contains('CachedNetworkImage('));
    expect(
      source,
      contains('fadeInDuration: const Duration(milliseconds: 200)'),
    );
    expect(source, isNot(contains('TweenAnimationBuilder')));
    expect(source, isNot(contains('ExtendedImage.network')));
  });

  test('reader preloader uses the same CE network provider', () {
    final source = File(
      'lib/views/reader/utils/image_preload_controller.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("package:cached_network_image_ce/cached_network_image.dart"),
    );
    expect(source, contains('CachedNetworkImageProvider(url)'));
    expect(source, isNot(contains('ExtendedNetworkImageProvider')));
  });

  test('horizontal reader pages use the CE network provider', () {
    final source = File(
      'lib/views/reader/widgets/horizontal_list/horizontal_list.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("package:cached_network_image_ce/cached_network_image.dart"),
    );
    expect(source, contains('CachedNetworkImageProvider(item.url)'));
    expect(source, contains('CachedNetworkImage.evictFromCache(item.url)'));
    expect(source, isNot(contains('ExtendedNetworkImageProvider')));
    expect(source, isNot(contains('clearMemoryImageCache')));
  });

  testWidgets('network ReaderImage keeps the cached aspect placeholder', (
    tester,
  ) async {
    final imageSize = ImageSize(
      width: 300,
      height: 600,
      imageId: 'page-1',
      cid: 'chapter-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderImage(
          url: 'https://example.invalid/page-1.jpg',
          imageSize: imageSize,
          filterQuality: FilterQuality.high,
          onImageSizeChanged: (_, _) {},
        ),
      ),
    );

    final cachedImage = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(cachedImage.fit, BoxFit.contain);
    expect(cachedImage.filterQuality, FilterQuality.high);
    expect(cachedImage.disablePlaceholderOnCacheHit, isFalse);

    final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(aspectRatio.aspectRatio, 0.5);
  });
}
