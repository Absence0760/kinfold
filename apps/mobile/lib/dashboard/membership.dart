// A member’s standing on the stack, in the member’s own words — the same
// sentences as the web dashboard’s `identityWord`. A new member learns why the
// app refuses them instead of seeing an empty home; the words come from the
// module the screens read, so no screen invents its own.
String identityWord(String? status) =>
    ({
      'pending_verification': 'Not done yet — the check has to pass before you can post',
      'active': 'Done',
      'suspended': 'Suspended',
      'closed': 'Closed',
    })[status ?? ''] ??
    (status ?? 'no account row yet');
