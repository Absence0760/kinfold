import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/auth/flow.dart';
import 'package:kinfold_mobile/provider.dart';

// The sign-in step pinned by recording fakes: what the step decides — a
// session, or the member’s own words for the failure — without ever reaching
// a network. The endpoint call is pinned exactly as the seam’s own words.
final calls = <String>[];

String record(String method, String path, Map<String, String>? json) {
  final body = json == null ? '' : json.entries.map((e) => '${e.key}=${e.value}').join(' ');
  final line = '$method $path $body'.trim();
  calls.add(line);
  return line;
}

Future<Response> ok(String path, {String method = 'GET', Map<String, String>? json}) async {
  record(method, path, json);
  return (status: 200, body: 'jwt-for-marco');
}

Future<Response> badCredentials(String path, {String method = 'GET', Map<String, String>? json}) async {
  record(method, path, json);
  return (status: 400, body: '{"code":"invalid_credentials","message":"Invalid login credentials"}');
}

Future<Response> limited(String path, {String method = 'GET', Map<String, String>? json}) async {
  record(method, path, json);
  return (status: 429, body: '');
}

Future<Response> melting(String path, {String method = 'GET', Map<String, String>? json}) async {
  record(method, path, json);
  return (status: 503, body: 'gateway dropped, no words');
}

Future<Response> gibberish(String path, {String method = 'GET', Map<String, String>? json}) async {
  record(method, path, json);
  return (status: 400, body: 'nonsense-not-json');
}

void main() {
  final Provider good = Provider(url: localStackUrl(), send: ok);
  final Provider keyless = Provider(url: '', send: ok);
  final Provider wrong = Provider(url: localStackUrl(), send: badCredentials);
  final Provider rateLimiter = Provider(url: localStackUrl(), send: limited);
  final Provider meltdown = Provider(url: localStackUrl(), send: melting);
  final Provider noisy = Provider(url: localStackUrl(), send: gibberish);

  test('the step sends the stack’s own sign-in call, in its own words', () async {
    calls.clear();
    final out = await attemptSignIn(good, 'maria@test.com', 'testtest');
    expect(calls, ['POST /auth/v1/signin email=maria@test.com password=testtest']);
    expect(out.session, 'jwt-for-marco');
    expect(out.notice, null);
  });

  test('a build with no key signs in nobody: no call, the setup words', () async {
    calls.clear();
    final out = await attemptSignIn(keyless, 'maria@test.com', 'testtest', dev: true);
    expect(calls, []);
    expect(out.session, null);
    expect(out.notice!.text, 'The member area has no Supabase key. Start it with the command below, which reads the key from the running local stack:');
    expect(out.notice!.command, 'pnpm dev:run:web');
  });

  test('wrong credentials answer in the web’s own words', () async {
    final out = await attemptSignIn(wrong, 'maria@test.com', 'wrong');
    expect(out.session, null);
    expect(out.notice!.text, 'That email and password don’t match an account. Check both and try again.');
    expect(out.notice!.command, null);
  });

  test('too many attempts waits a minute, no command needed', () async {
    final out = await attemptSignIn(rateLimiter, 'maria@test.com', 'testtest');
    expect(out.notice!.text, 'Too many sign-in attempts. Wait a minute, then try again.');
    expect(out.notice!.command, null);
  });

  test('a dev build’s server failure carries the check command; prod only gets words', () async {
    final dev = await attemptSignIn(meltdown, 'maria@test.com', 'testtest', dev: true);
    expect(dev.notice!.text, 'The local backend answered with a server error. Check it with');
    expect(dev.notice!.command, 'pnpm dev:db:status');
    final prod = await attemptSignIn(meltdown, 'maria@test.com', 'testtest');
    expect(prod.notice!.text, 'Kinfold isn’t responding right now. Nothing was changed. Try again in a few minutes.');
    expect(prod.notice!.command, null);
  });

  test('an answer with no words to name still fails visibly, not silently', () async {
    final out = await attemptSignIn(noisy, 'maria@test.com', 'testtest');
    expect(out.session, null);
    expect(out.notice!.text, 'Sign-in didn’t work. Try again in a minute.');
  });
}
