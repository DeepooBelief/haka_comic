import 'package:flutter/material.dart';
import 'package:haka_comic/views/reader/providers/sidebar_provider.dart';
import 'package:haka_comic/views/reader/providers/reader_provider.dart';

/// 章节切换侧边栏面板 UI
class ChapterSidebar extends StatelessWidget {
  final SidebarDirection direction;
  final VoidCallback onConfirm;
  const ChapterSidebar({super.key, required this.direction, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    // chapters 是 late final，不会变化，无需 watch
    final chapters = context.reader.chapters;
    final chapterIndex = context.selector((p) => p.chapterIndex);
    final isNext = direction == SidebarDirection.right;
    final targetIndex = isNext ? chapterIndex + 1 : chapterIndex - 1;

    // 边界保护：正常不会触发（wrapper 已通过 isFirst/isLast 控制）
    if (targetIndex < 0 || targetIndex >= chapters.length) {
      return const SizedBox.shrink();
    }

    final targetChapter = chapters[targetIndex];

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      borderRadius: BorderRadius.horizontal(
        left: isNext ? const Radius.circular(16) : Radius.zero,
        right: isNext ? Radius.zero : const Radius.circular(16),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isNext ? Icons.skip_next : Icons.skip_previous,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isNext ? '下一章' : '上一章',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                targetChapter.title,
                style: Theme.of(context).textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: onConfirm,
                  child: const Text('确认切换'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
