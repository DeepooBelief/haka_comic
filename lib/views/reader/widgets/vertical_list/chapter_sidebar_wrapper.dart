import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:haka_comic/config/app_config.dart';
import 'package:haka_comic/utils/request/request_state.dart';
import 'package:haka_comic/views/reader/providers/list_state_provider.dart';
import 'package:haka_comic/views/reader/providers/reader_provider.dart';
import 'package:haka_comic/views/reader/providers/sidebar_provider.dart';
import 'package:haka_comic/views/reader/widgets/vertical_list/chapter_sidebar.dart';

/// 章节切换侧边栏手势检测 + 动画编排层
///
/// 交互策略：
/// 一次滑动：松手位置在目标方向 [_directJumpPositionRatio] 以内 → 直接跳转
/// 否则侧边栏停住展开，等待二次操作：
///   - 继续往同方向滑动超过 [_secondaryDragThreshold] → 跳转
///   - 往反方向滑动 / 点击遮罩 → 收起
///
/// 方向约定：
///   delta 正值 = 手指向右，负值 = 手指向左
///   SidebarDirection.right = 下一章（侧边栏从右侧滑出，手指从右往左 delta<0）
///   SidebarDirection.left  = 上一章（侧边栏从左侧滑出，手指从左往右 delta>0）
class ChapterSidebarWrapper extends StatefulWidget {
  final Widget child;
  const ChapterSidebarWrapper({super.key, required this.child});

  @override
  State<ChapterSidebarWrapper> createState() => _ChapterSidebarWrapperState();
}

class _ChapterSidebarWrapperState extends State<ChapterSidebarWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  SidebarDirection? _dragDirection;
  bool _isDragging = false;

  // 视觉参数
  static const _sidebarWidthRatio = 0.4;
  static const _contentMinScale = 0.92;
  static const _cornerRadius = 16.0;
  static const _overlayMaxOpacity = 0.3;

  // 边缘检测区：从边缘 20px 偏移开始，宽度 1/4 屏幕（避开系统手势区）
  static const _edgeInset = 20.0;
  static const _edgeWidthRatio = 0.25;

  // 一次滑动直接跳转：松手位置在目标方向 20% 以内
  static const _directJumpPositionRatio = 0.2;

  // 侧边栏展开后，二次滑动跳转所需最小距离（逻辑像素）
  static const _secondaryDragThreshold = 80.0;

  // 侧边栏跟手灵敏度：用屏幕宽度的 70% 作分母
  static const _dragSensitivity = 0.7;

  // 侧边栏展开后是否处于"等待二次操作"状态
  bool _awaitingSecondary = false;
  double _secondaryDragAccum = 0.0;

  // 手指位置记录
  Offset? _pointerStart;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── 完整状态重置 ────────────────────────────────────────

  void _resetAllState() {
    _isDragging = false;
    _dragDirection = null;
    _awaitingSecondary = false;
    _secondaryDragAccum = 0.0;
    _pointerStart = null;
  }

  // ── 条件判断 ────────────────────────────────────────────

  bool get _canOpen {
    final reader = context.reader;
    final state = context.stateReader;
    if (reader.showToolbar || state.lockMenu) return false;
    if (reader.handler.state is Loading) return false;
    if (context.sidebarReader.active) return false;
    return true;
  }

  // ── 边缘检测区（一次滑动触发）──────────────────────────

  void _onEdgePointerDown(PointerDownEvent event, SidebarDirection dir) {
    if (!_canOpen) return;
    // 方向边界检查（防御性）
    final reader = context.reader;
    if (dir == SidebarDirection.right && reader.isLastChapter) return;
    if (dir == SidebarDirection.left && reader.isFirstChapter) return;

    _pointerStart = event.position;
    _dragDirection = dir;
  }

  void _onEdgePointerMove(PointerMoveEvent event) {
    if (_dragDirection == null) return;
    final delta = event.delta.dx;
    if (!_isDragging) {
      final totalDx = event.position.dx - (_pointerStart?.dx ?? event.position.dx);
      if (totalDx.abs() < 4.0) return;
      _isDragging = true;
      // 仅在开启侧边栏确认模式时才激活 provider（驱动侧边栏动画）
      if (AppConf().sidebarConfirmRequired) {
        context.sidebarReader.beginDrag(_dragDirection!);
      }
    }
    if (AppConf().sidebarConfirmRequired) {
      _updateDrag(delta);
    }
  }

  void _onEdgePointerUp(PointerUpEvent event) {
    if (_dragDirection == null) return;
    if (_isDragging) {
      _finishFirstDrag(event.position);
    } else {
      _dragDirection = null;
    }
    _pointerStart = null;
  }

  void _onEdgePointerCancel(PointerCancelEvent event) {
    _pointerStart = null;
    if (!_awaitingSecondary) {
      _resetAllState();
      _controller.animateTo(0.0,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 200),
      ).then((_) {
        if (!mounted) return;
        context.sidebarReader.dismiss();
      });
    }
  }

  // ── 遮罩层（侧边栏展开后的二次操作）──────────────────

  void _onOverlayDragStart(DragStartDetails details) {
    if (!_awaitingSecondary) return;
    _isDragging = true;
    _secondaryDragAccum = 0.0;
  }

  void _onOverlayDragUpdate(DragUpdateDetails details) {
    if (!_isDragging || !_awaitingSecondary) return;
    _handleSecondaryDrag(details.primaryDelta ?? 0);
  }

  void _onOverlayDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    _secondaryDragAccum = 0.0;
    // 距离不够就停在原地，继续等待
  }

  // ── 侧边栏面板上的二次拖拽 ─────────────────────────────

  void _onSidebarPointerDown(PointerDownEvent event) {
    if (!_awaitingSecondary) return;
    _isDragging = true;
    _secondaryDragAccum = 0.0;
  }

  void _onSidebarPointerMove(PointerMoveEvent event) {
    if (!_isDragging || !_awaitingSecondary) return;
    _handleSecondaryDrag(event.delta.dx);
  }

  void _onSidebarPointerUp(PointerUpEvent event) {
    if (!_isDragging) return;
    _isDragging = false;
    _secondaryDragAccum = 0.0;
  }

  void _onSidebarPointerCancel(PointerCancelEvent event) {
    _isDragging = false;
    _secondaryDragAccum = 0.0;
  }

  // ── 核心逻辑 ──────────────────────────────────────────

  void _updateDrag(double delta) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // right(下一章)：手指向左 delta<0，sign=-1 使 controller 递增
    // left(上一章)：手指向右 delta>0，sign=+1 使 controller 递增
    final sign = _dragDirection == SidebarDirection.right ? -1.0 : 1.0;
    _controller.value =
        (_controller.value + (delta * sign) / (screenWidth * _dragSensitivity))
            .clamp(0.0, 1.0);
    context.sidebarReader.updateProgress(_controller.value);
  }

  /// 一次滑动松手：根据配置决定行为
  ///   - sidebarConfirmRequired=false：直接跳转，不显示侧边栏
  ///   - sidebarConfirmRequired=true ：展开侧边栏等待二次确认
  void _finishFirstDrag(Offset upPosition) {
    final dir = _dragDirection;
    _isDragging = false;
    _dragDirection = null;

    if (!AppConf().sidebarConfirmRequired) {
      // 未开启侧边栏确认 → 直接跳转，不显示侧边栏
      _jumpChapter(dir!);
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;

    // right(下一章)：手指从右往左划，停在左侧 20% 以内 → 直接跳
    // left(上一章)：手指从左往右划，停在右侧 20% 以内 → 直接跳
    final isDeepEnough = dir == SidebarDirection.right
        ? upPosition.dx < screenWidth * _directJumpPositionRatio
        : upPosition.dx > screenWidth * (1.0 - _directJumpPositionRatio);

    if (isDeepEnough) {
      _jumpChapter(dir!);
    } else {
      _openAndAwait(dir!);
    }
  }

  /// 侧边栏展开停住，等待二次操作
  void _openAndAwait(SidebarDirection dir) {
    _isDragging = false;
    _dragDirection = null;
    _awaitingSecondary = true;
    _secondaryDragAccum = 0.0;
    _controller.animateTo(1.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 200),
    );
    // beginDrag 在 _onEdgePointerMove 中已调用过（幂等，安全）
    if (!context.sidebarReader.active) {
      context.sidebarReader.beginDrag(dir);
    }
  }

  /// 二次拖拽处理
  void _handleSecondaryDrag(double delta) {
    final dir = context.sidebarReader.direction;
    // right(下一章)：向左滑 delta<0，-delta>0 为向内
    // left(上一章)：向右滑 delta>0，delta>0 为向内
    final inward = dir == SidebarDirection.right ? -delta : delta;

    if (inward > 0) {
      _secondaryDragAccum += inward;
      if (_secondaryDragAccum >= _secondaryDragThreshold) {
        _secondaryDragAccum = 0.0;
        _jumpChapter(dir);
      }
    } else {
      // 反方向滑动 → 收起
      _secondaryDragAccum = 0.0;
      _closeSidebar();
    }
  }

  void _jumpChapter(SidebarDirection dir) {
    HapticFeedback.mediumImpact();
    // 完整重置所有状态，立即生效
    _resetAllState();
    _controller.stop();
    _controller.value = 0.0;
    context.sidebarReader.dismiss();
    if (dir == SidebarDirection.right) {
      context.reader.goNext();
    } else {
      context.reader.goPrevious();
    }
  }

  void _closeSidebar() {
    _resetAllState();
    _controller.animateTo(0.0,
      curve: Curves.easeInCubic,
      duration: const Duration(milliseconds: 200),
    ).then((_) {
      if (!mounted) return;
      context.sidebarReader.dismiss();
    });
  }

  void _confirmAndClose() {
    _jumpChapter(context.sidebarReader.direction);
  }

  @override
  Widget build(BuildContext context) {
    final active = context.sidebarSelector<bool>((p) => p.active);
    final direction = context.sidebarSelector<SidebarDirection>((p) => p.direction);
    final isFirst = context.selector<bool>((p) => p.isFirstChapter);
    final isLast = context.selector<bool>((p) => p.isLastChapter);
    final sidebarWidth = MediaQuery.sizeOf(context).width * _sidebarWidthRatio;

    return Stack(
      children: [
        // 内容层：缩放 + 圆角
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 1.0 - (_controller.value * (1.0 - _contentMinScale));
            final radius = _controller.value * _cornerRadius;
            return ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: widget.child,
        ),

        // 遮罩层（点击收起 + 二次拖拽）
        if (active)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => GestureDetector(
              onTap: _closeSidebar,
              onHorizontalDragStart: _onOverlayDragStart,
              onHorizontalDragUpdate: _onOverlayDragUpdate,
              onHorizontalDragEnd: _onOverlayDragEnd,
              child: Container(
                color: Colors.black.withOpacity(
                  _controller.value * _overlayMaxOpacity,
                ),
              ),
            ),
          ),

        // 侧边栏面板（二次拖拽）
        if (active)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = sidebarWidth * (1.0 - _controller.value);
              return Positioned(
                top: 0,
                bottom: 0,
                width: sidebarWidth,
                left: direction == SidebarDirection.left ? -offset : null,
                right: direction == SidebarDirection.right ? -offset : null,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onSidebarPointerDown,
                  onPointerMove: _onSidebarPointerMove,
                  onPointerUp: _onSidebarPointerUp,
                  onPointerCancel: _onSidebarPointerCancel,
                  child: child!,
                ),
              );
            },
            child: ChapterSidebar(
              direction: direction,
              onConfirm: _confirmAndClose,
            ),
          ),

        // 左边缘检测区（上一章）
        if (!isFirst && !active)
          Positioned(
            left: _edgeInset,
            top: 0,
            bottom: 0,
            width: MediaQuery.sizeOf(context).width * _edgeWidthRatio,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _onEdgePointerDown(e, SidebarDirection.left),
              onPointerMove: _onEdgePointerMove,
              onPointerUp: _onEdgePointerUp,
              onPointerCancel: _onEdgePointerCancel,
            ),
          ),

        // 右边缘检测区（下一章）
        if (!isLast && !active)
          Positioned(
            right: _edgeInset,
            top: 0,
            bottom: 0,
            width: MediaQuery.sizeOf(context).width * _edgeWidthRatio,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _onEdgePointerDown(e, SidebarDirection.right),
              onPointerMove: _onEdgePointerMove,
              onPointerUp: _onEdgePointerUp,
              onPointerCancel: _onEdgePointerCancel,
            ),
          ),
      ],
    );
  }
}
