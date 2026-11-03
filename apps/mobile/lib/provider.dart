// What the auth provider hands back when a call fails: the provider’s own
// answer, before any words are attached to it. `status` is 0 when the request
// never got an answer, which is what separates a dropped connection from a
// refusal.
class AuthFault {
  final String code;
  final String message;
  final int status;
  final bool retryable;

  AuthFault({required this.code, required this.message, required this.status, required this.retryable}) {}
}

// The provider seam: what the app asks of the backend, in calls the app’s own
// words name. The transport is injectable — a unit test hands back a recording
// fake and pins the request the app would send (the repo’s fake-vendor pattern:
// a local equivalent *and* a code default pointing at it, in the same change).
// The code default for a local run is the dev stack’s own API port (docs/STACK.md:
// API 54721), so a fresh clone needs no cloud account — local-first.
typedef Response = ({int status, String body});

typedef Transport = Future<Response> Function(String path, {String method, Map<String, String>? json});

/// A configured provider: the API base URL of the stack to reach. An empty url
/// means the build has no Supabase key — `notConfiguredNotice` says so instead
/// of pretending an empty request will work.
class Provider {
  final String url;
  final Transport send;

  Provider({required this.url, required this.send}) {}

  bool configured() => url.isNotEmpty;
}

/// The dev stack’s own API surface — the code default a local run answers
/// (docs/STACK.md: Supabase API on 54721). Nothing outside a throwaway local
/// environment grants access to it, so pointing the default at it is safe.
String localStackUrl() => 'http://127.0.0.1:54721';

/// Sign a member in against the stack’s own sign-in endpoint. A failure answer
/// arrives as null here; the caller attaches the member’s words (sign_in.dart).
Future<Map<String, String>?> signIn(Provider p, String email, String password) async {
  if (!p.configured()) return null;
  final r = await p.send('/auth/v1/signin', method: 'POST', json: {'email': email, 'password': password});
  if (r.status >= 400) return null;
  return {'session': r.body};
}

/// The member’s row and roles — the profile half of the shell. The board
/// returns rows as JSON arrays; the two reads the first screen is made of
/// happen once each. A refused read returns null (a failed load), which is
/// never shown as an empty home.
Future<Map<String, String>?> loadViewer(Provider p, String userId) async {
  if (!p.configured() || userId.isEmpty) return null;
  final member = await p.send('/rest/v1/members?id=eq.' + userId + '&select=id,state,status', method: 'GET');
  final roles = await p.send('/rest/v1/member_roles?member_id=eq.' + userId + '&select=role', method: 'GET');
  if (member.status >= 400 || roles.status >= 400) return null;
  return {'member': member.body, 'roles': roles.body};
}
