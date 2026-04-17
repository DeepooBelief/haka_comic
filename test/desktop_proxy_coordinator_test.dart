import 'package:flutter_test/flutter_test.dart';
import 'package:haka_comic/network/desktop_proxy_coordinator.dart';

void main() {
  group('DesktopProxyCoordinator', () {
    const directProxy = ProxyConfig(enable: false, host: '', port: 0);
    const systemProxy = ProxyConfig(
      enable: true,
      host: '127.0.0.1',
      port: 7890,
    );

    test('uses a 3 second default polling interval', () {
      final coordinator = DesktopProxyCoordinator();
      expect(coordinator.pollInterval, const Duration(seconds: 3));
      coordinator.dispose();
    });

    test('start syncs the current proxy immediately', () async {
      final applied = <ProxyConfig>[];
      var fetchCount = 0;

      final coordinator = DesktopProxyCoordinator(
        pollInterval: const Duration(seconds: 15),
        fetchProxy: () async {
          fetchCount += 1;
          return systemProxy;
        },
        applyProxy: applied.add,
      );

      await coordinator.start();

      expect(fetchCount, 1);
      expect(applied, [systemProxy]);
      expect(coordinator.currentProxy, systemProxy);

      coordinator.dispose();
    });

    test('syncNow only notifies listeners when proxy changes', () async {
      final applied = <ProxyConfig>[];
      final notified = <ProxyConfig>[];
      final sequence = <ProxyConfig>[directProxy, directProxy, systemProxy];
      var index = 0;

      final coordinator = DesktopProxyCoordinator(
        fetchProxy: () async => sequence[index++],
        applyProxy: applied.add,
      )..addListener(notified.add);

      await coordinator.syncNow();

      expect(notified, [directProxy]);
      expect(applied, [directProxy]);

      await coordinator.syncNow();

      expect(notified, [directProxy]);
      expect(applied, [directProxy]);

      await coordinator.syncNow();

      expect(notified, [directProxy, systemProxy]);
      expect(applied, [directProxy, systemProxy]);
      expect(coordinator.currentProxy, systemProxy);

      coordinator.dispose();
    });
  });
}
