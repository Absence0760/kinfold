// The signed-in member’s first screen in the phone app, assembled from what the
// provider read back: the member row is decoded once, not re-read per field, and
// the standing the row carries is put in the member’s words by membership.dart.
import 'dart:convert';
import 'dashboard/membership.dart';

class Profile {
  final String standing;
  final String state;
  final List<String> roles;

  Profile({required this.standing, required this.state, required this.roles}) {}
}

/// Turn the provider’s raw reads into a profile. The stack returns rows as JSON
/// arrays; an empty array is “no member row yet” — a new member whose identity
/// check is still running sees the words for that standing, never a silent empty
/// home.
Profile viewerProfile({String? memberBody, String? rolesBody}) {
  final rows = (memberBody == null || memberBody.isEmpty) ? [] : (jsonDecode(memberBody) as List);
  final row = rows.isEmpty ? null : (rows.first as Map<String, dynamic>);
  final roleRows = (rolesBody == null || rolesBody.isEmpty) ? [] : (jsonDecode(rolesBody) as List);
  final roles = roleRows.map((r) => (r as Map<String, dynamic>)['role'].toString()).toList();
  final status = row == null ? null : (row['status'] as String?);
  final state = row == null ? '' : (row['state'] as String? ?? '');
  return Profile(standing: identityWord(status), state: state, roles: roles);
}
