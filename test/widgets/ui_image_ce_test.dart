import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/router/route_observer.dart';
import 'package:haka_comic/widgets/ui_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UiImage CE uses CachedNetworkImage fade instead of manual fade', () {
    final source = File('lib/widgets/ui_image.dart').readAsStringSync();

    expect(source, isNot(contains('TweenAnimationBuilder')));
    expect(source, isNot(contains('fadeInDuration: Duration.zero')));
    expect(
      source,
      contains('fadeInDuration: const Duration(milliseconds: 250)'),
    );
  });

  testWidgets(
    'UiImage CE exposes the UiImage constructor and initial placeholder',
    (tester) async {
      const placeholderKey = Key('ui-image-ce-placeholder');

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: Material(
            child: UiImage(
              url: 'https://example.invalid/image.png',
              fit: BoxFit.contain,
              width: 120,
              height: 80,
              cacheWidth: 240,
              cacheHeight: 160,
              shape: BoxShape.rectangle,
              border: Border.all(color: Colors.red),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              clipBehavior: Clip.hardEdge,
              filterQuality: FilterQuality.medium,
              placeholder: const SizedBox(
                key: placeholderKey,
                width: 120,
                height: 80,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(placeholderKey), findsOneWidget);
    },
  );

  testWidgets('UiImage CE frames CachedNetworkImage from the outside', (
    tester,
  ) async {
    final border = Border.all(color: Colors.blue);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routeObserver],
        home: Material(
          child: UiImage(
            url: 'https://example.invalid/framed-image.png',
            fit: BoxFit.contain,
            width: 120,
            height: 80,
            cacheWidth: 240,
            cacheHeight: 160,
            shape: BoxShape.rectangle,
            border: border,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            clipBehavior: Clip.hardEdge,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );

    await tester.pump();
    final expectedMemCacheWidth = (120 * tester.view.devicePixelRatio).round();

    final imageFinder = find.byType(CachedNetworkImage);
    expect(imageFinder, findsOneWidget);

    final frameFinder = find.ancestor(
      of: imageFinder,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;

        final constraints = widget.constraints;
        final decoration = widget.decoration;

        return widget.clipBehavior == Clip.hardEdge &&
            constraints?.minWidth == 120 &&
            constraints?.maxWidth == 120 &&
            constraints?.minHeight == 80 &&
            constraints?.maxHeight == 80 &&
            decoration is BoxDecoration &&
            decoration.color != null &&
            decoration.shape == BoxShape.rectangle &&
            decoration.border == border &&
            decoration.borderRadius ==
                const BorderRadius.all(Radius.circular(8));
      }),
    );
    expect(frameFinder, findsOneWidget);

    final cachedImage = tester.widget<CachedNetworkImage>(imageFinder);
    expect(cachedImage.fit, BoxFit.contain);
    expect(cachedImage.width, 120);
    expect(cachedImage.height, 80);
    expect(cachedImage.memCacheWidth, expectedMemCacheWidth);
    expect(cachedImage.memCacheHeight, 160);
    expect(cachedImage.filterQuality, FilterQuality.medium);
  });

  testWidgets(
    'UiImage automatically retries failed loads and hides refresh until exhausted',
    (tester) async {
      final originalCacheManager =
          CachedNetworkImageProvider.defaultCacheManager;
      CachedNetworkImageProvider.defaultCacheManager = _FailingCacheManager();
      addTearDown(() {
        CachedNetworkImageProvider.defaultCacheManager = originalCacheManager;
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: const Material(
            child: UiImage(
              url: 'https://example.invalid/ui-image.png',
              width: 120,
              height: 80,
              timeRetry: Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      String imageKeyValue() {
        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        return (image.key as ValueKey<String>).value;
      }

      Future<void> waitForRetryState(String token) async {
        for (
          var i = 0;
          i < 20 &&
              imageKeyValue().endsWith(token) &&
              find.byIcon(Icons.refresh).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump();
        }
      }

      expect(imageKeyValue(), endsWith('#0'));
      await waitForRetryState('#0');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(imageKeyValue(), endsWith('#1'));
      await waitForRetryState('#1');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(imageKeyValue(), endsWith('#2'));
      await waitForRetryState('#2');
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(imageKeyValue(), endsWith('#2'));
    },
  );
}

class _FailingCacheManager extends DefaultCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    if (withProgress) {
      yield DownloadProgress(url, null, 0);
    }
    throw Exception('forced image failure');
  }

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) {
    return getFileStream(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
    );
  }
}
