import 'package:flutter_test/flutter_test.dart';

import 'package:kinfold_mobile/profile.dart';
import 'package:kinfold_mobile/dashboard/membership.dart';

// The first screen’s words: the standing a member row carries is shown in the
// member’s words — the same sentences as the web’s identityWord.
void main() {
  test('the standing words are the web’s, all four', () {
    expect(identityWord('pending_verification'), 'Not done yet — the check has to pass before you can post');
    expect(identityWord('active'), 'Done');
    expect(identityWord('suspended'), 'Suspended');
    expect(identityWord('closed'), 'Closed');
  });

  test('no member row yet reads as itself, not as “Done”', () {
    final profile = viewerProfile(memberBody: '[]');
    expect(profile.standing, 'no account row yet');
    expect(profile.state, '');
    expect(profile.roles, []);
  });

  test('a member mid-identity-check learns why the app holds them back', () {
    final profile = viewerProfile(memberBody: '[{"id":"m1","state":"CA","status":"pending_verification"}]', rolesBody: '[]');
    expect(profile.standing, 'Not done yet — the check has to pass before you can post');
    expect(profile.state, 'CA');
  });

  test('a signed-in member sees their standing and their roles', () {
    final profile = viewerProfile(memberBody: '[{"id":"m1","state":"NY","status":"active"}]', rolesBody: '[{"role":"reviewer"}]');
    expect(profile.standing, 'Done');
    expect(profile.state, 'NY');
    expect(profile.roles, ['reviewer']);
  });

  test('a member with no roles is a member, not an error', () {
    final profile = viewerProfile(memberBody: '[{"id":"m1","state":"TX","status":"active"}]');
    expect(profile.roles, []);
  });
}
