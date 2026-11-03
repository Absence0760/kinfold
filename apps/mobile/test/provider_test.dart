import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/provider.dart';

// The provider seam pinned by a recording fake: the calls the app makes to the
// stack are pinned exactly (paths, methods, bodies), so the shell’s wiring can
// be read off the test without ever reaching a network — the repo’s fake-vendor
// pattern (a local equivalent, and a code default pointing at it, in one change).
final calls = <String>[];

Future<Response> record(String path, {String method = 'GET', Map<String, String>? json}) async {
  final body = json == null ? '' : json.entries.map((e) => '${e.key}=${e.value}').join(' ');
  calls.add('$method $path $body'.trim());
  return (status: 200, body: '[]');
}

Future<Response> refuse(String path, {String method = 'GET', Map<String, String>? json}) async => (status: 500, body: 'no');

void main() {
  final Provider p = Provider(url: localStackUrl(), send: record);
  final Provider angry = Provider(url: localStackUrl(), send: refuse);

  test('the local run answers the dev stack’s own port by default', () {
    expect(localStackUrl(), 'http://127.0.0.1:54721');
    expect(p.configured(), true);
  });

  test('the profile reads the two rows the first screen is made of, once each', () async {
    calls.clear();
    final data = await loadViewer(p, 'm1');
    expect(calls, [
      'GET /rest/v1/members?id=eq.m1&select=id,state,status',
      'GET /rest/v1/member_roles?member_id=eq.m1&select=role',
    ]);
    expect(data, isNotNull);
  });

  test('no signed-in id asks the stack nothing', () async {
    calls.clear();
    final data = await loadViewer(p, '');
    expect(calls, []);
    expect(data, null);
  });

  test('a refused read is a failed load, not an empty home', () async {
    final data = await loadViewer(angry, 'm1');
    expect(data, null);
  });
}
