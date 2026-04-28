import 'dart:async';

import 'package:haka_comic/network/proxy_overrides.dart';
import 'package:haka_comic/rust/api/proxy.dart';
import 'package:haka_comic/utils/log.dart';

class ProxyConfig {
  const ProxyConfig({
    required this.enable,
    required this.host,
    required this.port,
  });

  final bool enable;
  final String host;
  final int port;

  factory ProxyConfig.fromPayload(Map<dynamic, dynamic> payload) {
    return ProxyConfig(
      enable: payload['enable'] as bool? ?? false,
      host: payload['host'] as String? ?? '',
      port: (payload['port'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{'enable': enable, 'host': host, 'port': port};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProxyConfig &&
            runtimeType == other.runtimeType &&
            enable == other.enable &&
            host == other.host &&
            port == other.port;
  }

  @override
  int get hashCode => Object.hash(enable, host, port);
}

typedef FetchProxyConfig = Future<ProxyConfig> Function();
typedef ApplyProxyConfig = void Function(ProxyConfig proxy);
typedef ProxyListener = void Function(ProxyConfig proxy);

class DesktopProxyCoordinator {
  DesktopProxyCoordinator({
    FetchProxyConfig? fetchProxy,
    ApplyProxyConfig? applyProxy,
    this.pollInterval = const Duration(seconds: 3),
  }) : _fetchProxy = fetchProxy ?? _readCurrentProxy,
       _applyProxy = applyProxy ?? applyProxyConfig;

  final FetchProxyConfig _fetchProxy;
  final ApplyProxyConfig _applyProxy;
  final Duration pollInterval;

  final Set<ProxyListener> _listeners = <ProxyListener>{};

  Timer? _timer;
  ProxyConfig? _currentProxy;
  bool _syncing = false;

  ProxyConfig? get currentProxy => _currentProxy;

  Future<ProxyConfig?> start() async {
    final proxy = await syncNow();
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(syncNow()));
    return proxy;
  }

  void addListener(ProxyListener listener, {bool emitCurrent = false}) {
    _listeners.add(listener);
    final current = _currentProxy;
    if (emitCurrent && current != null) {
      listener(current);
    }
  }

  void removeListener(ProxyListener listener) {
    _listeners.remove(listener);
  }

  Future<ProxyConfig?> syncNow() async {
    if (_syncing) {
      return _currentProxy;
    }

    _syncing = true;
    try {
      final proxy = await _fetchProxy();
      if (proxy != _currentProxy) {
        Log.i('Proxy changed', {
          proxy.enable ? '${proxy.host}:${proxy.port}' : 'DIRECT',
        });
        _currentProxy = proxy;
        _applyProxy(proxy);
        for (final listener in List<ProxyListener>.from(_listeners)) {
          listener(proxy);
        }
      }
      return proxy;
    } catch (_) {
      return _currentProxy;
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _listeners.clear();
  }

  static void applyProxyConfig(ProxyConfig proxy) {
    ProxyHttpOverrides.updateProxy(
      enable: proxy.enable,
      host: proxy.host,
      port: proxy.port,
    );
  }

  static Future<ProxyConfig> _readCurrentProxy() async {
    final proxy = await getProxy();
    return ProxyConfig(
      enable: proxy.enable,
      host: proxy.host,
      port: proxy.port,
    );
  }
}

final DesktopProxyCoordinator desktopProxyCoordinator =
    DesktopProxyCoordinator();
