import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum SidebarDirection { left, right }

extension BuildContextSidebar on BuildContext {
  SidebarProvider get sidebarReader => read<SidebarProvider>();
  T sidebarSelector<T>(T Function(SidebarProvider) s) =>
      select<SidebarProvider, T>(s);
}

/// 章节切换侧边栏状态管理
class SidebarProvider extends ChangeNotifier {
  /// 侧边栏是否激活
  bool _active = false;
  bool get active => _active;

  /// 滑出方向：left = 从左侧滑出（上一章），right = 从右侧滑出（下一章）
  SidebarDirection _direction = SidebarDirection.right;
  SidebarDirection get direction => _direction;

  /// 拖拽/动画进度 0.0~1.0（仅内部记录，动画由 AnimationController 驱动）
  double _progress = 0.0;
  double get progress => _progress;

  void beginDrag(SidebarDirection dir) {
    if (_active) return;
    _direction = dir;
    _active = true;
    notifyListeners();
  }

  void updateProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
  }

  void dismiss() {
    _active = false;
    _progress = 0.0;
    _direction = SidebarDirection.right;
    notifyListeners();
  }
}
