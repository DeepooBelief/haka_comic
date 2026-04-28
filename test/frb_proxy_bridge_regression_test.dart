import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FRB proxy bridge stays crate-owned and does not expose sysproxy', () {
    final yaml = File('flutter_rust_bridge.yaml').readAsStringSync();
    final proxyApi = File('lib/rust/api/proxy.dart').readAsStringSync();

    expect(yaml, isNot(contains('sysproxy')));
    expect(proxyApi, isNot(contains("third_party/sysproxy.dart")));
  });
}
