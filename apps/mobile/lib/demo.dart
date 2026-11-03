// One-click demo sign-in for local development — the same seeded people the web
// offers and apps/backend/supabase/seed.sql creates. Their shared password grants
// access to nothing outside a throwaway local stack, which is why it can be
// committed (CLAUDE.md, local-dev env). Keep this list in step with the seed’s
// header comment; the copy parity with the web is pinned by test.
class DemoAccount {
  final String email;
  final String name;
  final String roles;
  final String summary;

  const DemoAccount({required this.email, required this.name, required this.roles, required this.summary});
}

const demoPassword = 'testtest';

const demoAccounts = [
  DemoAccount(
    email: 'maria@test.com',
    name: 'Maria',
    roles: 'Member · CA',
    summary: 'A draft home repair, and a car deductible funded by her brother with a 0% loan.',
  ),
  DemoAccount(
    email: 'sam@test.com',
    name: 'Sam',
    roles: 'Member · CA',
    summary: 'Maria’s brother and lender. Has an open car damage request on the board.',
  ),
  DemoAccount(
    email: 'james@test.com',
    name: 'James',
    roles: 'Member + reviewer · NY',
    summary: 'Reviews requests from other states, so he can review Maria and Sam.',
  ),
  DemoAccount(
    email: 'priya@test.com',
    name: 'Priya',
    roles: 'Member + appeal panel · TX',
    summary: 'A car damage request already paid from the community pool.',
  ),
];

const loopbackHosts = {'localhost', '127.0.0.1', '::1'};

/// Whether demo sign-in may be offered. Needs a dev build AND a loopback stack:
/// the host check is what stops a dev build accidentally pointed at a real
/// project from sending the seeded credentials to it.
bool demoSignInAllowed(bool dev, String supabaseUrl) {
  if (!dev) return false;
  var host = Uri.parse(supabaseUrl).host;
  if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);
  return loopbackHosts.contains(host);
}
