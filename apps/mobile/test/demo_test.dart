import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/demo.dart';

// The seeded people the phone app offers in dev, pinned against the web’s list
// and the seed’s header comment: one product’s people, whichever surface opens.
void main() {
  test('the demo people are the seeded ones, in the seed’s order', () {
    expect(demoAccounts.map((a) => a.email).toList(), ['maria@test.com', 'sam@test.com', 'james@test.com', 'priya@test.com']);
    expect(demoAccounts[1].name, 'Sam');
    expect(demoAccounts[2].roles, 'Member + reviewer · NY');
    expect(demoAccounts[3].summary, 'A car damage request already paid from the community pool.');
    expect(demoPassword, 'testtest');
  });

  test('demo sign-in needs a dev build AND a loopback stack', () {
    expect(demoSignInAllowed(true, 'http://127.0.0.1:54721'), true);
    expect(demoSignInAllowed(true, 'http://localhost:54721'), true);
    // A dev build accidentally pointed at a real project must not offer the
    // seeded credentials to it.
    expect(demoSignInAllowed(true, 'https://real.kinfold.dev'), false);
    // A production build never offers them at all.
    expect(demoSignInAllowed(false, 'http://127.0.0.1:54721'), false);
    // A bare IP with a scope (the stack answering a network name) is still the
    // machine’s own — the web unwraps the brackets the same way.
    expect(demoSignInAllowed(true, 'http://[::1]:54721'), true);
  });
}
