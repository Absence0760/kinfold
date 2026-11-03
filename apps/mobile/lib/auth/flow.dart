// The first screen's sign-in step: it answers with either a session or the
// member's own words, decided in one place. The shape mirrors
// apps/web/src/routes/signin/+page.svelte: the build's key check first
// (notConfiguredNotice, no call), then the seam's own sign-in call, then
// the provider's answer classified by sign_in.dart's order — a refusal that
// also reads like a network problem is still a refusal.
import 'dart:convert';

import '../provider.dart';
import 'sign_in.dart';

/// What the sign-in step hands the screen: at most one of the two.
typedef SignInAnswer = ({String? session, Notice? notice});

Future<SignInAnswer> attemptSignIn(
  Provider p,
  String email,
  String password, {
  bool dev = false,
}) async {
  if (!p.configured()) {
    return (session: null, notice: notConfiguredNotice(dev: dev));
  }
  final r = await p.send(
    '/auth/v1/signin',
    method: 'POST',
    json: {'email': email, 'password': password},
  );
  if (r.status < 400) {
    return (session: r.body, notice: null);
  }
  final fault = faultFrom(r.status, r.body);
  return (
    session: null,
    notice: signInNotice(
      classifySignInFailure(fault),
      dev: dev,
      message: fault.message,
    ),
  );
}

/// The provider's own answer from a refusal. When the stack got to answer,
/// its body is JSON naming a code and a message; a body that carries no
/// words leaves both empty, which classifies as unknown rather than hiding
/// the failure.
AuthFault faultFrom(int status, String body) {
  var code = '';
  var message = '';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      code = (decoded['code'] as String?) ?? '';
      message = (decoded['message'] as String?) ?? '';
    }
  } catch (e) {
    // Not JSON: the answer got no words to name. Empty code/message say so.
    code = '';
    message = '';
  }
  return AuthFault(
    code: code,
    message: message,
    status: status,
    retryable: status >= 500,
  );
}
