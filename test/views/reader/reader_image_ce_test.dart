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

  test('horizontal reader avoids duplicate image size writes', () {
    final source = File(
      'lib/views/reader/widgets/horizontal_list/horizontal_list.dart',
    ).readAsStringSync();

    expect(source, contains('final Set<String> _reportedImageSizeIds = {};'));
    expect(source, contains('bool _reportImageSizeOnce('));
    expect(source, contains('_reportImageSizeOnce('));
  });

  test('vertical reader decodes with double-tap zoom clarity headroom', () {
    final source = File(
      'lib/views/reader/widgets/vertical_list/vertical_list.dart',
    ).readAsStringSync();

    expect(source, contains('static const double _zoomClarityScale = 3.0'));
    expect(source, contains('MediaQuery.devicePixelRatioOf(context)'));
    expect(source, contains('cacheWidth: cacheWidth'));
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

  testWidgets('network ReaderImage applies the requested memory cache width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderImage(
          url: 'https://example.invalid/page-1.jpg',
          cacheWidth: 2160,
          onImageSizeChanged: (_, _) {},
        ),
      ),
    );

    final cachedImage = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(cachedImage.memCacheWidth, 2160);
  });

  testWidgets('local ReaderImage applies the requested image cache width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderImage(
          url: 'C:/missing/page-1.jpg',
          cacheWidth: 2160,
          onImageSizeChanged: (_, _) {},
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image).first);
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 2160);
  });

  testWidgets('local ReaderImage automatically retries failed loads twice', (
    tester,
  ) async {
    final missingPath =
        '${Directory.systemTemp.path}/haka_comic_missing_reader_image.jpg';

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderImage(
          url: missingPath,
          timeRetry: const Duration(milliseconds: 100),
          onImageSizeChanged: (_, _) {},
        ),
      ),
    );

    String imageKeyValue() {
      final image = tester.widget<Image>(find.byType(Image).first);
      return (image.key as ValueKey<String>).value;
    }

    expect(imageKeyValue(), endsWith('#0'));
    Future<void> waitForFailureUi() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    await waitForFailureUi();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(imageKeyValue(), endsWith('#1'));
    await waitForFailureUi();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(imageKeyValue(), endsWith('#2'));
    await waitForFailureUi();
    for (
      var i = 0;
      i < 50 && find.byIcon(Icons.refresh).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(imageKeyValue(), endsWith('#2'));
  });
}
