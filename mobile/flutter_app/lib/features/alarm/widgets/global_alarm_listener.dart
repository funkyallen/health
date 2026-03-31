import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/alarm_model.dart';
import '../providers/alarm_provider.dart';

class GlobalAlarmListener extends StatefulWidget {
  final Widget child;

  const GlobalAlarmListener({
    super.key,
    required this.child,
  });

  @override
  State<GlobalAlarmListener> createState() => _GlobalAlarmListenerState();
}

class _GlobalAlarmListenerState extends State<GlobalAlarmListener> {
  static const Duration _freshAlarmWindow = Duration(minutes: 2);

  final Set<String> _shownAlarmIds = <String>{};
  final List<AlarmRecord> _pendingAlarms = <AlarmRecord>[];

  AlarmProvider? _alarmProvider;
  bool _initializedSnapshot = false;
  bool _dialogVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AlarmProvider>();
    if (!identical(_alarmProvider, provider)) {
      _alarmProvider?.removeListener(_onAlarmChanged);
      _alarmProvider = provider;
      _alarmProvider?.addListener(_onAlarmChanged);
    }
  }

  @override
  void dispose() {
    _alarmProvider?.removeListener(_onAlarmChanged);
    super.dispose();
  }

  void _onAlarmChanged() {
    if (!mounted) {
      return;
    }

    final provider = _alarmProvider;
    if (provider == null) {
      return;
    }

    if (provider.status == AlarmLoadStatus.initial) {
      _shownAlarmIds.clear();
      _pendingAlarms.clear();
      _initializedSnapshot = false;
      _dialogVisible = false;
      return;
    }

    if (provider.status != AlarmLoadStatus.loaded) {
      return;
    }

    if (!_initializedSnapshot) {
      for (final alarm in provider.alarms) {
        if (_shouldPresentInitialAlarm(alarm)) {
          _shownAlarmIds.add(alarm.id);
          _enqueueAlarm(alarm);
          continue;
        }
        _shownAlarmIds.add(alarm.id);
      }
      _initializedSnapshot = true;
      return;
    }

    for (final alarm in provider.alarms) {
      if (_shouldPresentRealtimeAlarm(alarm)) {
        _shownAlarmIds.add(alarm.id);
        _enqueueAlarm(alarm);
      }
    }
  }

  bool _shouldPresentInitialAlarm(AlarmRecord alarm) {
    return !_shownAlarmIds.contains(alarm.id) &&
        !alarm.acknowledged &&
        alarm.isSos &&
        _isFreshAlarm(alarm);
  }

  bool _shouldPresentRealtimeAlarm(AlarmRecord alarm) {
    return !_shownAlarmIds.contains(alarm.id) &&
        !alarm.acknowledged &&
        alarm.isSos;
  }

  bool _isFreshAlarm(AlarmRecord alarm) {
    final createdAt = alarm.createdAtDateTime;
    if (createdAt == null) {
      return false;
    }
    final age = DateTime.now().difference(createdAt).abs();
    return age <= _freshAlarmWindow;
  }

  void _enqueueAlarm(AlarmRecord alarm) {
    if (_dialogVisible) {
      final alreadyQueued = _pendingAlarms.any((item) => item.id == alarm.id);
      if (!alreadyQueued) {
        _pendingAlarms.add(alarm);
      }
      return;
    }

    _showAlarmDialog(alarm);
  }

  Future<void> _showAlarmDialog(AlarmRecord alarm) async {
    if (!mounted) {
      return;
    }

    _dialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A0A),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.redAccent, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              '紧急求助报警',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alarm.deviceMac.isNotEmpty) ...[
              Text(
                '设备 MAC: ${alarm.deviceMac}',
                style: const TextStyle(color: const Color(0xFF0F172A), fontSize: 16),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '时间: ${alarm.createdAtDisplay}',
              style: const TextStyle(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Text(
              alarm.message.isNotEmpty
                  ? alarm.message
                  : '老人可能遇到紧急情况，请立即联系或前往处理。',
              style: const TextStyle(color: const Color(0xFF0F172A)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _alarmProvider?.acknowledge(alarm.id);
              Navigator.pop(dialogContext);
            },
            child: const Text(
              '我知道了',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );

    _dialogVisible = false;
    if (!mounted || _pendingAlarms.isEmpty) {
      return;
    }

    final nextAlarm = _pendingAlarms.removeAt(0);
    _showAlarmDialog(nextAlarm);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
