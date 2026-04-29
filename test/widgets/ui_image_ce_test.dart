import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/router/route_observer.dart';
import 'package:haka_comic/widgets/ui_image.dart';

void main() {
  test('UiImage CE uses CachedNetworkImage fade instead of manual fade', () {
    final source = File('lib/widgets/ui_image_ce.dart').readAsStringSync();

    expect(source, isNot(contains('TweenAnimationBuilder')));
    expect(source, isNot(contains('fadeInDuration: Duration.zero')));
    expect(source, isNot(contains('fadeOutDuration: Duration.zero')));
    expect(
      source,
      contains('fadeInDuration: const Duration(milliseconds: 350)'),
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
}
