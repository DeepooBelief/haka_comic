import 'dart:io';

/// 全局 HttpOverrides，让所有 HttpClient（包括 extended_image、Dio 底层）
/// 都使用当前系统代理，无需 TUN 模式。
///
/// 每个 Isolate 需单独调用 [install]；[updateProxy] 是 Isolate-local 的。
class ProxyHttpOverrides extends HttpOverrides {
  static String _proxyString = 'DIRECT';

  /// 安装到当前 Isolate 的全局 HttpOverrides。
  static void install() {
    HttpOverrides.global = ProxyHttpOverrides();
  }

  /// 根据最新代理状态更新当前 Isolate 的代理字符串。
  static void updateProxy({
    required bool enable,
    required String host,
    required int port,
  }) {
    _proxyString = (enable && host.isNotEmpty) ? 'PROXY $host:$port' : 'DIRECT';
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => _proxyString;
    // 桌面端使用自签证书代理时可能需要放开校验，可按需启用：
    // client.badCertificateCallback = (_, __, ___) => true;
    return client;
  }
}
