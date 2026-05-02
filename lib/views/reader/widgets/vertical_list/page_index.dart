import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

List<int> visibleVerticalImageIndices(
  Iterable<ItemPosition> positions, {
  required int imageCount,
}) {
  if (imageCount <= 0) return [];

  final indices = positions
      .where((pos) => pos.index >= 0 && pos.index < imageCount)
      .where(
        (pos) =>
            pos.itemLeadingEdge < 1.0 &&
            pos.itemTrailingEdge > 0.0 &&
            pos.itemTrailingEdge <= 1.0,
      )
      .map((position) => position.index)
      .toList();

  indices.sort();
  return indices;
}

int? currentVerticalPageIndex(
  Iterable<ItemPosition> positions, {
  required int imageCount,
}) {
  final indices = visibleVerticalImageIndices(
    positions,
    imageCount: imageCount,
  );
  if (indices.isEmpty) return null;
  return indices.last;
}
