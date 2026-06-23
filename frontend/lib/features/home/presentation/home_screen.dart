import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/colors.dart';
import '../../../models/session_models.dart';
import '../../../services/orchestrator_client.dart';
import 'widgets/action_panel.dart';
import 'widgets/status_card.dart';
import 'widgets/text_command_composer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController(
    text: 'Search Naver for Incheon youth monthly rent support and read the conditions.',
  );
  final OrchestratorClient _client = OrchestratorClient();

  StreamSubscription<SessionEvent>? _sessionSubscription;
  CanonicalCommand? _command;
  List<SessionEvent> _events = const [];
  String _status = 'Idle';
  String _phase = 'idle';
  String? _sessionId;
  String? _error;
  Map<String, dynamic>? _result;
  bool _isSubmitting = false;
  bool _isCanonicalizing = false;

  String _policySummary(CanonicalCommand command) {
    if (command.requiresConfirmation) {
      return 'Approval is required before execution because this command changes system state or carries elevated risk.';
    }
    if (command.intent == 'change_system_setting') {
      return 'Auto-run enabled for reversible setting changes such as dark mode.';
    }
    if (command.riskLevel == 'medium') {
      return 'Medium-risk action is allowed to run automatically by current policy.';
    }
    return 'This command can run immediately.';
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _interpretCommand() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isCanonicalizing || _isSubmitting) {
      return;
    }

    setState(() {
      _isCanonicalizing = true;
      _error = null;
      _command = null;
      _result = null;
      _status = 'Interpreting';
      _phase = 'canonicalize';
    });

    try {
      final command = await _client.canonicalizeCommand(text);
      if (!mounted) {
        return;
      }
      setState(() {
        _command = command;
        _status = 'Ready';
        _phase = 'review';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _status = 'Error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCanonicalizing = false;
        });
      }
    }
  }

  Future<void> _runReviewedCommand({bool confirmed = false}) async {
    final command = _command;
    if (command == null || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _events = const [];
      _result = null;
      _status = 'Starting';
      _phase = 'queued';
    });

    try {
      final response = await _client.runCanonicalCommand(command, confirmed: confirmed);
      await _sessionSubscription?.cancel();

      setState(() {
        _command = response.command;
        _sessionId = response.sessionId;
        _status = _toTitleCase(response.session.status);
        _phase = response.session.currentPhase;
        _events = response.session.events;
        _result = response.session.result;
      });

      _sessionSubscription = _client.watchSession(response.sessionId).listen(
        (event) {
          if (!mounted) {
            return;
          }

          setState(() {
            _events = [..._events, event];
            _status = _toTitleCase(event.status);
            _phase = event.currentPhase ?? event.phase;
            _result = event.result ?? _result;
            _isSubmitting = event.status == 'queued' || event.status == 'running';
          });
        },
        onError: (Object error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _error = error.toString();
            _status = 'Error';
            _isSubmitting = false;
          });
        },
        onDone: () {
          if (!mounted) {
            return;
          }

          setState(() {
            _isSubmitting = false;
            if (_status != 'Error' && _status != 'Canceled') {
              _status = 'Completed';
              _phase = 'complete';
            }
          });
        },
      );
    } catch (error) {
      setState(() {
        _error = error.toString();
        _status = 'Error';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _approveAndRun() async {
    final command = _command;
    if (command == null) {
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Approval Required'),
          content: Text(
            'This command is classified as ${command.riskLevel} risk and needs explicit approval before execution.\n\n'
            'Intent: ${command.intent}\n'
            'Command: ${command.normalizedText}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Approve and Run'),
            ),
          ],
        );
      },
    );

    if (approved == true) {
      await _runReviewedCommand(confirmed: true);
    }
  }

  Future<void> _stopSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      return;
    }

    try {
      await _client.stopSession(sessionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  String _toTitleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatResultValue(Object? value) {
    if (value == null) {
      return '-';
    }
    if (value is bool) {
      return value ? 'yes' : 'no';
    }
    return value.toString();
  }

  List<Map<String, dynamic>> _plannedSteps(Map<String, dynamic>? result) {
    final raw = result?['planned_steps'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  List<Map<String, dynamic>> _executedSteps(Map<String, dynamic>? result) {
    final raw = result?['executed_steps'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  List<String> _planningNotes(Map<String, dynamic>? result) {
    final raw = result?['planning_notes'];
    if (raw is! List) {
      return const [];
    }
    return raw.map((item) => item.toString()).toList();
  }

  List<Map<String, dynamic>> _directoryEntries(Map<String, dynamic>? result) {
    final raw = result?['directory_entries'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  Widget _buildKeyValueText(
    BuildContext context,
    String label,
    String value, {
    bool selectable = false,
  }) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final text = '$label: $value';
    if (selectable) {
      return SelectableText(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: surfaceTheme.textPrimary),
      );
    }
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(color: surfaceTheme.textPrimary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceTheme = theme.extension<AppSurfaceTheme>()!;
    final latestDetail = _events.isEmpty ? 'No execution events yet.' : _events.last.detail;
    final result = _result;
    final plannedSteps = _plannedSteps(result);
    final executedSteps = _executedSteps(result);
    final planningNotes = _planningNotes(result);
    final directoryEntries = _directoryEntries(result);

    return Scaffold(
      backgroundColor: surfaceTheme.shellBackground,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: surfaceTheme.surface,
                border: Border(bottom: BorderSide(color: surfaceTheme.border)),
              ),
              child: Row(
                children: [
                  Text('VisionNavi', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 12),
                  Text(
                    'Interpret first, then execute.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: surfaceTheme.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              height: 92,
              decoration: BoxDecoration(
                color: surfaceTheme.surface,
                border: Border(bottom: BorderSide(color: surfaceTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: StatusCard(
                      label: 'Session Status',
                      value: _status,
                      icon: Icons.mic_none_rounded,
                      iconBackground: (_isSubmitting || _isCanonicalizing)
                          ? AppColors.successSoft
                          : surfaceTheme.contentBackground,
                      iconColor: (_isSubmitting || _isCanonicalizing)
                          ? AppColors.success
                          : surfaceTheme.textMuted,
                      showWave: true,
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: surfaceTheme.border),
                  Expanded(
                    child: StatusCard(
                      label: 'Policy Mode',
                      value: _command?.requiresConfirmation == true ? 'Approval Required' : 'Auto Run',
                      icon: _command?.requiresConfirmation == true
                          ? Icons.lock_outline_rounded
                          : Icons.bolt_rounded,
                      iconBackground: _command?.requiresConfirmation == true
                          ? AppColors.warningSoft
                          : surfaceTheme.contentBackground,
                      iconColor: _command?.requiresConfirmation == true
                          ? AppColors.warning
                          : surfaceTheme.textMuted,
                      showDot: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 290,
                    child: ActionPanel(
                      isRunning: _isSubmitting || _isCanonicalizing,
                      onStop: _events.isEmpty ? null : _stopSession,
                      onSelectSearchDemo: () {
                        setState(() {
                          _controller.text =
                              'Search Naver for Incheon youth monthly rent support and read the conditions.';
                        });
                      },
                      onSelectNotepadDemo: () {
                        setState(() {
                          _controller.text = 'Open Notepad and type my presentation notes for today.';
                        });
                      },
                      onSelectWorkspaceDemo: () {
                        setState(() {
                          _controller.text = 'Open file explorer for the VisionNavi workspace and list files.';
                        });
                      },
                      onSelectDarkModeDemo: () {
                        setState(() {
                          _controller.text = 'Change Windows to dark mode';
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: surfaceTheme.contentBackground,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Command Workspace', style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Step 1: interpret the command with the LLM. Step 2: review the canonical command. Step 3: execute.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: surfaceTheme.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextCommandComposer(
                                    controller: _controller,
                                    onSubmit: _interpretCommand,
                                    isBusy: _isSubmitting || _isCanonicalizing,
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      OutlinedButton(
                                        onPressed: (_isSubmitting || _isCanonicalizing) ? null : _interpretCommand,
                                        child: Text(_isCanonicalizing ? 'Interpreting...' : 'Interpret Command'),
                                      ),
                                      ElevatedButton(
                                        onPressed: (_command == null || _isSubmitting || _isCanonicalizing)
                                            ? null
                                            : (_command?.requiresConfirmation == true
                                                  ? _approveAndRun
                                                  : _runReviewedCommand),
                                        child: Text(
                                          _isSubmitting
                                              ? 'Running...'
                                              : (_command?.requiresConfirmation == true
                                                    ? 'Approve and Run'
                                                    : 'Run Reviewed Command'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Canonical Review', style: theme.textTheme.titleMedium),
                                          const SizedBox(height: 12),
                                          Text('Phase: $_phase'),
                                          if (_sessionId != null) Text('Session: $_sessionId'),
                                          const SizedBox(height: 8),
                                          Text(latestDetail),
                                          if (_error != null) ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              _error!,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.error,
                                              ),
                                            ),
                                          ],
                                          if (_command != null) ...[
                                            const SizedBox(height: 16),
                                            if (_command!.requiresConfirmation) ...[
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningSoft,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'Approval gate active. Review the canonical command and approve before execution.',
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    color: AppColors.warning,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            Text('Raw: ${_command!.rawText}'),
                                            Text('Normalized: ${_command!.normalizedText}'),
                                            Text('Intent: ${_command!.intent}'),
                                            Text('Domain: ${_command!.taskDomain}'),
                                            Text('Risk: ${_command!.riskLevel}'),
                                            if (_command!.targetApp != null) Text('Target: ${_command!.targetApp}'),
                                            if (_command!.notes.isNotEmpty)
                                              Text('Notes: ${_command!.notes.join(', ')}'),
                                            Text(
                                              _command!.requiresConfirmation
                                                  ? 'Requires confirmation: yes'
                                                  : 'Requires confirmation: no',
                                            ),
                                            const SizedBox(height: 8),
                                            Text(_policySummary(_command!)),
                                            if (result != null) ...[
                                              const SizedBox(height: 16),
                                              Text('Execution Result', style: theme.textTheme.titleSmall),
                                              const SizedBox(height: 8),
                                              _buildKeyValueText(
                                                context,
                                                'Status',
                                                _formatResultValue(result['status']),
                                              ),
                                              _buildKeyValueText(
                                                context,
                                                'Executor',
                                                _formatResultValue(result['executor']),
                                              ),
                                              _buildKeyValueText(
                                                context,
                                                'Strategy',
                                                _formatResultValue(result['strategy']),
                                              ),
                                              if (result['target_app'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Target app',
                                                  _formatResultValue(result['target_app']),
                                                ),
                                              if (result['text'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Text',
                                                  _formatResultValue(result['text']),
                                                ),
                                              if (result['file_path'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'File',
                                                  _formatResultValue(result['file_path']),
                                                  selectable: true,
                                                ),
                                              if (result['folder_path'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Folder',
                                                  _formatResultValue(result['folder_path']),
                                                  selectable: true,
                                                ),
                                              if (result['moved_to_path'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Moved to',
                                                  _formatResultValue(result['moved_to_path']),
                                                  selectable: true,
                                                ),
                                              if (result['linked_page_url'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Linked page',
                                                  _formatResultValue(result['linked_page_url']),
                                                  selectable: true,
                                                ),
                                              if (result['page_summary'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Summary',
                                                  _formatResultValue(result['page_summary']),
                                                  selectable: true,
                                                ),
                                              if (result['primary_failure'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Primary failure',
                                                  _formatResultValue(result['primary_failure']),
                                                ),
                                              if (result['fallback_from'] != null)
                                                _buildKeyValueText(
                                                  context,
                                                  'Fallback from',
                                                  _formatResultValue(result['fallback_from']),
                                                ),
                                              if (directoryEntries.isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                Text('Workspace Entries', style: theme.textTheme.titleSmall),
                                                const SizedBox(height: 8),
                                                ...directoryEntries.map(
                                                  (entry) => Padding(
                                                    padding: const EdgeInsets.only(bottom: 4),
                                                    child: Text(
                                                      '${entry['kind']}: ${entry['name']}',
                                                      style: theme.textTheme.bodyMedium,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ] else
                                            Text(
                                              'Interpret a command to review the LLM or fallback classification result before execution.',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: surfaceTheme.textMuted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Agent Plan', style: theme.textTheme.titleMedium),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Observe, plan, act, verify, and recover are surfaced here so the user can inspect the agent path.',
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    color: surfaceTheme.textMuted,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                if (planningNotes.isNotEmpty) ...[
                                                  Text('Planner Notes', style: theme.textTheme.titleSmall),
                                                  const SizedBox(height: 8),
                                                  ...planningNotes.map(
                                                    (note) => Padding(
                                                      padding: const EdgeInsets.only(bottom: 6),
                                                      child: Text(
                                                        '• $note',
                                                        style: theme.textTheme.bodyMedium,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                ],
                                                if (plannedSteps.isNotEmpty) ...[
                                                  Text('Planned Steps', style: theme.textTheme.titleSmall),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: ListView.separated(
                                                      itemCount: plannedSteps.length,
                                                      separatorBuilder: (context, index) =>
                                                          const Divider(height: 16),
                                                      itemBuilder: (context, index) {
                                                        final step = plannedSteps[index];
                                                        final action = step['action']?.toString() ?? 'unknown';
                                                        final target = step['target']?.toString();
                                                        final reasoning = step['reasoning']?.toString();
                                                        return Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              '${index + 1}. $action',
                                                              style: theme.textTheme.bodyLarge,
                                                            ),
                                                            if (target != null && target.isNotEmpty)
                                                              Padding(
                                                                padding: const EdgeInsets.only(top: 4),
                                                                child: Text(
                                                                  'Target: $target',
                                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                                    color: surfaceTheme.textMuted,
                                                                  ),
                                                                ),
                                                              ),
                                                            if (reasoning != null && reasoning.isNotEmpty)
                                                              Padding(
                                                                padding: const EdgeInsets.only(top: 4),
                                                                child: Text(
                                                                  reasoning,
                                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                                    color: surfaceTheme.textMuted,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ] else
                                                  Expanded(
                                                    child: Align(
                                                      alignment: Alignment.topLeft,
                                                      child: Text(
                                                        'Planned action steps will appear here after the LLM planner runs.',
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          color: surfaceTheme.textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (executedSteps.isNotEmpty) ...[
                                                  const SizedBox(height: 12),
                                                  Text('Executed Steps', style: theme.textTheme.titleSmall),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: executedSteps.map((step) {
                                                      final action = step['action']?.toString() ?? 'unknown';
                                                      final status = step['status']?.toString() ?? 'unknown';
                                                      final success = status == 'success';
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: success
                                                              ? AppColors.successSoft
                                                              : AppColors.warningSoft,
                                                          borderRadius: BorderRadius.circular(999),
                                                        ),
                                                        child: Text(
                                                          '$action · $status',
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            color: success
                                                                ? AppColors.success
                                                                : AppColors.warning,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Event Timeline', style: theme.textTheme.titleMedium),
                                                const SizedBox(height: 12),
                                                Expanded(
                                                  child: ListView.separated(
                                                    itemCount: _events.length,
                                                    separatorBuilder: (context, index) =>
                                                        const Divider(height: 16),
                                                    itemBuilder: (context, index) {
                                                      final event = _events[index];
                                                      return Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            '${event.sequence}. ${event.phase}',
                                                            style: theme.textTheme.bodyLarge,
                                                          ),
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            event.detail,
                                                            style: theme.textTheme.bodyMedium?.copyWith(
                                                              color: surfaceTheme.textMuted,
                                                            ),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
