// Sign-in failures in plain words — the same sentences as the web’s
// `apps/web/src/lib/auth/errors.ts` half of `signInNotice`. A member sees one
// product’s words whichever surface they use. The copy is deliberately
// duplicated per workspace: a Dart package and a Svelte app share no module
// system, and the repo’s no-premature-abstraction rule extracts a shared file
// only at the third caller — so the seam is a future decision, not this one.
import '../provider.dart';

typedef Notice = ({String text, String? command});

enum SignInFailure {
  invalidCredentials,
  rateLimited,
  unconfirmed,
  banned,
  network,
  server,
  unknown,
}

/// Why a sign-in failed, from the provider’s own answer. The order is the web’s:
/// a refusal that also reads like a network problem is still a refusal.
SignInFailure classifySignInFailure(AuthFault fault) {
  final code = fault.code.toLowerCase();
  final message = fault.message.toLowerCase();
  bool has(String needle) => message.contains(needle);

  if (code == 'invalid_credentials' || has('invalid login credentials')) {
    return SignInFailure.invalidCredentials;
  }
  if (code == 'over_request_rate_limit' ||
      fault.status == 429 ||
      has('rate limit') ||
      has('too many')) {
    return SignInFailure.rateLimited;
  }
  if (code == 'email_not_confirmed' || has('email not confirmed')) {
    return SignInFailure.unconfirmed;
  }
  if (code == 'user_banned') {
    return SignInFailure.banned;
  }
  if (fault.retryable && fault.status >= 500) {
    return SignInFailure.server;
  }
  if (fault.status == 0 ||
      fault.retryable ||
      has('failed to fetch') ||
      has('networkerror') ||
      has('fetch failed') ||
      has('load failed') ||
      has('network request failed')) {
    return SignInFailure.network;
  }
  if (fault.status >= 500) {
    return SignInFailure.server;
  }
  return SignInFailure.unknown;
}

/// The sign-in error to show. `dev` is true on a laptop running the local stack,
/// where the fix is a command; a production member only ever gets plain words.
Notice signInNotice(SignInFailure failure, {bool dev = false, String message = ''}) {
  switch (failure) {
    case SignInFailure.invalidCredentials:
      return (command: null, text: 'That email and password don’t match an account. Check both and try again.');
    case SignInFailure.rateLimited:
      return (command: null, text: 'Too many sign-in attempts. Wait a minute, then try again.');
    case SignInFailure.unconfirmed:
      return (command: null, text: 'This email address hasn’t been confirmed yet. Open the confirmation link in the email we sent you, then sign in.');
    case SignInFailure.banned:
      return (command: null, text: 'This account can’t sign in right now. Ask the member who invited you to contact the Kinfold team.');
    case SignInFailure.network:
      return dev
          ? (text: 'Can’t reach the local backend. Start it with', command: 'pnpm dev:db:up')
          : (command: null, text: 'Can’t reach Kinfold. Check your connection and try again.');
    case SignInFailure.server:
      return dev
          ? (text: 'The local backend answered with a server error. Check it with', command: 'pnpm dev:db:status')
          : (command: null, text: 'Kinfold isn’t responding right now. Nothing was changed. Try again in a few minutes.');
    case SignInFailure.unknown:
      return message.isEmpty
          ? (command: null, text: 'Sign-in didn’t work. Try again in a minute.')
          : (command: null, text: 'Sign-in didn’t work: “$message”. Try again in a minute.');
  }
}

/// The notice when the build has no Supabase key: the member area has nothing
/// to reach, and the member is told what to start instead of being shown a
/// stack trace.
Notice notConfiguredNotice({bool dev = false}) => dev
    ? (text: 'The member area has no Supabase key. Start it with the command below, which reads the key from the running local stack:', command: 'pnpm dev:run:web')
    : (command: null, text: 'Signing in isn’t available right now. Please try again later.');
