import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/views/reader/widgets/vertical_list/page_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  ItemPosition position(int index, double leading, double trailing) {
    return ItemPosition(
      index: index,
      itemLeadingEdge: leading,
      itemTrailingEdge: trailing,
    );
  }

  test('ignores chapter footer when choosing vertical reader page', () {
    final index = currentVerticalPageIndex([
      position(0, 0.0, 0.7),
      position(4, 0.8, 0.9),
    ], imageCount: 4);

    expect(index, 0);
  });

  test('does not report last page when only chapter footer is visible', () {
    final index = currentVerticalPageIndex([
      position(4, 0.0, 0.1),
    ], imageCount: 4);

    expect(index, isNull);
  });
}
