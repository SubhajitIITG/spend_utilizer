import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../util/format.dart';
import 'email_password_form.dart';
import 'otp_form.dart';
import 'theme.dart';

/// Cloud status icon for app bars; opens the profile screen.
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService?>();
    final sync = context.watch<SyncService>();
    final IconData icon;
    final String tip;
    if (auth == null || !auth.signedIn) {
      icon = Icons.cloud_off_outlined;
      tip = 'Saved on this device only';
    } else if (sync.state == SyncState.syncing) {
      icon = Icons.cloud_sync_outlined;
      tip = 'Syncing…';
    } else if (sync.state == SyncState.error) {
      icon = Icons.sync_problem;
      tip = 'Sync problem: tap for details';
    } else {
      icon = Icons.cloud_done_outlined;
      tip = 'Synced';
    }
    return IconButton(
      tooltip: tip,
      icon: Icon(
        icon,
        color: sync.state == SyncState.error
            ? Theme.of(context).colorScheme.error
            : null,
      ),
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService?>();
    final sync = context.watch<SyncService>();
    final store = context.watch<AppStore>();
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: royalAppBar('Account & sync'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (auth == null) ...[
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Cloud sync is not set up'),
                  subtitle: Text(
                    'Your data is saved only on this device. '
                    'See SETUP.md in the project to enable login and sync.',
                  ),
                ),
              ] else ...[
                ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      auth.isGuest ? Icons.person_outline : Icons.person,
                    ),
                  ),
                  title: Text(auth.displayName, style: t.titleMedium),
                  subtitle: Text(
                    auth.isGuest
                        ? 'Guest account'
                        : 'Signed in · your data syncs across devices',
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: Icon(switch (sync.state) {
                    SyncState.syncing => Icons.cloud_sync_outlined,
                    SyncState.error => Icons.sync_problem,
                    SyncState.idle => Icons.cloud_done_outlined,
                  }),
                  title: Text(switch (sync.state) {
                    SyncState.syncing => 'Syncing…',
                    SyncState.error => 'Last sync failed',
                    SyncState.idle =>
                      sync.lastSyncedAt == null
                          ? 'Not synced yet'
                          : 'Synced ${formatDateTime(sync.lastSyncedAt!)}',
                  }),
                  subtitle: sync.state == SyncState.error
                      ? Text(AuthService.errorText(sync.lastError ?? ''))
                      : Text(
                          '${store.dirty.length + store.tombstones.length} '
                          'change(s) waiting to upload',
                        ),
                  trailing: FilledButton.tonal(
                    onPressed: sync.state == SyncState.syncing
                        ? null
                        : () => sync.syncNow(),
                    child: const Text('Sync now'),
                  ),
                ),
                if (auth.isGuest) ...[const Divider(), const _UpgradeGuest()],
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Sign out'),
                  subtitle: const Text('Removes your data from this device'),
                  onTap: () => _signOut(context, auth, sync, store),
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Chat history'),
                subtitle: const Text(
                  'Chat messages stay on this device. Your '
                  'transactions, accounts and reminders are what sync.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(
    BuildContext context,
    AuthService auth,
    SyncService sync,
    AppStore store,
  ) async {
    final guest = auth.isGuest;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          guest
              ? 'You are using a guest account. If you sign out without adding '
                    'an email or phone number first, your data CANNOT be '
                    'recovered.'
              : 'Your data stays safe in the cloud and will come back when '
                    'you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // Upload anything pending before leaving.
    if (!guest) await sync.syncNow();
    sync.stop();
    store.clearAll();
    await store.saveNow();
    await auth.signOut();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _UpgradeGuest extends StatefulWidget {
  const _UpgradeGuest();
  @override
  State<_UpgradeGuest> createState() => _UpgradeGuestState();
}

class _UpgradeGuestState extends State<_UpgradeGuest> {
  OtpChannelKind _channel = OtpChannelKind.email;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService?>()!;
    void saved() {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saved! Sign in with it on your other devices to see the same '
            'data.',
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keep your data safe',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Add an email and password (or your phone number) to turn this guest '
            'account into a permanent one. Then you can sign in on any '
            'device and see the same data.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<OtpChannelKind>(
            segments: const [
              ButtonSegment(value: OtpChannelKind.email, label: Text('Email')),
              ButtonSegment(value: OtpChannelKind.phone, label: Text('Phone')),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 12),
          if (_channel == OtpChannelKind.email)
            EmailPasswordForm(
              saveOnly: true,
              createLabel: 'Save my account',
              onCreate: (email, password) async {
                await auth.linkEmailPassword(email, password);
                saved();
              },
            )
          else
            OtpForm(
              channel: OtpChannelKind.phone,
              verifyLabel: 'Verify & save',
              onSend: auth.linkPhone,
              onVerify: (target, code) async {
                await auth.verifyLinkPhone(target, code);
                saved();
              },
            ),
        ],
      ),
    );
  }
}
