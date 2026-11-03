import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/auth/sign_in.dart';
import 'package:kinfold_mobile/provider.dart';

// The words a sign-in failure becomes. These sentences are pinned against the
// web’s own copy (apps/web/src/lib/auth/errors.ts): a member reads one product’s
// words whichever surface they use, so a drift on either side fails here.
void main() {
  test('a wrong email or password gets its own words', () {
    final failure = classifySignInFailure(AuthFault(code: 'invalid_credentials', message: '', status: 400, retryable: false));
    expect(failure, SignInFailure.invalidCredentials);
    expect(signInNotice(failure).text, 'That email and password don’t match an account. Check both and try again.');
  });

  test('too many attempts gets its own words', () {
    final failure = classifySignInFailure(AuthFault(code: 'over_request_rate_limit', message: '', status: 400, retryable: false));
    expect(failure, SignInFailure.rateLimited);
    expect(signInNotice(failure).text, 'Too many sign-in attempts. Wait a minute, then try again.');
  });

  test('an unconfirmed email is explained, not hidden behind “failed”', () {
    final failure = classifySignInFailure(AuthFault(code: 'email_not_confirmed', message: 'Email not confirmed', status: 400, retryable: false));
    expect(failure, SignInFailure.unconfirmed);
    expect(signInNotice(failure).text, 'This email address hasn’t been confirmed yet. Open the confirmation link in the email we sent you, then sign in.');
  });

  test('a banned account names who to contact', () {
    final failure = classifySignInFailure(AuthFault(code: 'user_banned', message: '', status: 400, retryable: false));
    expect(failure, SignInFailure.banned);
    expect(signInNotice(failure).text, 'This account can’t sign in right now. Ask the member who invited you to contact the Kinfold team.');
  });

  test('a dropped connection never reads as “signed out”', () {
    final failure = classifySignInFailure(AuthFault(code: '', message: 'network request failed', status: 0, retryable: false));
    expect(failure, SignInFailure.network);
    expect(signInNotice(failure).text, 'Can’t reach Kinfold. Check your connection and try again.');
  });

  test('a local run gets the command that starts the stack', () {
    final failure = classifySignInFailure(AuthFault(code: '', message: 'fetch failed', status: 0, retryable: false));
    final notice = signInNotice(failure, dev: true);
    expect(notice.text, 'Can’t reach the local backend. Start it with');
    expect(notice.command, 'pnpm dev:db:up');
  });

  test('a server refusal is shown with its reason kept small', () {
    final failure = classifySignInFailure(AuthFault(code: '', message: '', status: 503, retryable: false));
    expect(failure, SignInFailure.server);
    expect(signInNotice(failure).text, 'Kinfold isn’t responding right now. Nothing was changed. Try again in a few minutes.');
  });

  test('an answer the app doesn’t recognise still tells the member to wait', () {
    final failure = classifySignInFailure(AuthFault(code: 'whatever', message: '', status: 404, retryable: false));
    expect(failure, SignInFailure.unknown);
    expect(signInNotice(failure, message: 'Unexpected input').text, 'Sign-in didn’t work: “Unexpected input”. Try again in a minute.');
    expect(signInNotice(failure).text, 'Sign-in didn’t work. Try again in a minute.');
  });

  test('a refusal that also reads like a network problem is still a refusal', () {
    // The web’s order: code beats message. A 500 with “network” in its text is a server, not a dropped connection.
    final failure = classifySignInFailure(AuthFault(code: '', message: 'the network said no', status: 500, retryable: false));
    expect(failure, SignInFailure.server);
  });

  test('a build with no Supabase key says so instead of pretending', () {
    final notice = notConfiguredNotice();
    expect(notice.text, 'Signing in isn’t available right now. Please try again later.');
    final devNotice = notConfiguredNotice(dev: true);
    expect(devNotice.command, 'pnpm dev:run:web');
  });
}
