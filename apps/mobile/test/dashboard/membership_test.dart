import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/dashboard/membership.dart';

// A member’s standing in the member’s words. These sentences are pinned against
// the web’s identityWord (apps/web/src/lib/dashboard/membership.ts): a member
// reads one product’s words whichever surface they use, so a drift on either
// side fails here.
void main() {
  test('the standing words are the web’s, all four', () {
    expect(identityWord('pending_verification'), 'Not done yet — the check has to pass before you can post');
    expect(identityWord('active'), 'Done');
    expect(identityWord('suspended'), 'Suspended');
    expect(identityWord('closed'), 'Closed');
  });

  test('no member row yet reads as itself, not as a blank', () {
    expect(identityWord(null), 'no account row yet');
  });

  test('a standing the stack added after this app shipped is shown, not hidden', () {
    expect(identityWord('away_for_a_bit'), 'away_for_a_bit');
  });
}
