import 'package:flutter/material.dart';

import '../models/session_metadata.dart';
import '../repositories/session_repository.dart';

/// App-scoped default repository shared across the application.
final _sharedRepository = SessionRepository();

/// Displays the list of recorded sessions and provides open / delete actions.
///
/// An optional [repository] may be supplied for testing; when omitted the
/// app-wide [_sharedRepository] is used.
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key, this.repository});

  final SessionRepository? repository;

  SessionRepository get _repo => repository ?? _sharedRepository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final sessions = _repo.sessions;
        if (sessions.isEmpty) {
          return const _EmptyState();
        }
        return _SessionList(sessions: sessions, repo: _repo);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text('No sessions yet', style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Import data to create a session',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session list
// ---------------------------------------------------------------------------

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions, required this.repo});

  final List<SessionMetadata> sessions;
  final SessionRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionCard(
          session: session,
          onOpen: () => _openSession(context, session),
          onDelete: () => _confirmDelete(context, session, repo),
        );
      },
    );
  }

  void _openSession(BuildContext context, SessionMetadata session) {
    // Navigation to detail screen is blocked by dependent issues #48 / #50.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening session ${session.sessionId}')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SessionMetadata session,
    SessionRepository repository,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      repository.delete(session.sessionId);
    }
  }
}

// ---------------------------------------------------------------------------
// Session card tile
// ---------------------------------------------------------------------------

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  final SessionMetadata session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final positionLabel =
        session.position == SensorPosition.front ? 'Front' : 'Rear';
    final dateLabel = _formatDateTime(session.recordedAt);
    final rateLabel = '${session.samplingRateHz.toStringAsFixed(0)} Hz';
    final pairedLabel = session.hasPair ? ' · Paired' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.sensors,
          color: colorScheme.primary,
        ),
        title: Text(
          session.sessionId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$positionLabel sensor · $dateLabel'),
            Text('$rateLabel$pairedLabel'),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open session',
              onPressed: onOpen,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: colorScheme.error),
              tooltip: 'Delete session',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
