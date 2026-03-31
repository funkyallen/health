import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../voice/models/voice_model.dart';
import '../repositories/agent_repository.dart';
import '../../voice/repositories/voice_repository.dart';
import '../../../core/services/audio_service.dart';
import '../../voice/providers/voice_provider.dart';
import '../../care/providers/care_provider.dart';

enum AgentStatus { initial, loading, streaming, loaded, error }

class AgentProvider extends ChangeNotifier {
  final AgentRepository _repository;

  AgentStatus _status = AgentStatus.initial;
  String? _errorMessage;
  final List<AgentMessage> _messages = <AgentMessage>[];

  AgentProvider(this._repository);

  AgentStatus get status => _status;
  String? get errorMessage => _errorMessage;
  List<AgentMessage> get messages => _messages;

  void init([String? initialGreeting]) {
    _messages.clear();
    if (initialGreeting != null && initialGreeting.trim().isNotEmpty) {
      _messages.add(
        AgentMessage(role: 'assistant', content: initialGreeting.trim()),
      );
    }
    _status = AgentStatus.loaded;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> sendMessage(
    String text, {
    String? deviceMac,
    List<String> deviceMacs = const <String>[],
    required String role,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final userMessage = AgentMessage(role: 'user', content: normalizedText);
    _messages.add(userMessage);

    _status = AgentStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final assistantMessage = AgentMessage(role: 'assistant', content: '');
    _messages.add(assistantMessage);
    notifyListeners();

    try {
      _status = AgentStatus.streaming;
      notifyListeners();

      await for (final delta in _repository.streamAgentAnalysis(
        normalizedText,
        deviceMac,
        deviceMacs: deviceMacs,
        role: role,
      )) {
        assistantMessage.content += delta;
        notifyListeners();
      }

      _status = AgentStatus.loaded;
    } catch (_) {
      _errorMessage = '暂时无法连接到健康助手，请稍后再试。';
      _status = AgentStatus.error;
      if (assistantMessage.content.isEmpty) {
        assistantMessage.content = '连接失败，请稍后重试。';
      }
    }

    notifyListeners();
  }

  Future<void> sendVoiceMessage(
    List<int> audioBytes, {
    String? deviceMac,
    required String role,
  }) async {
    final userMessage = AgentMessage(role: 'user', content: '[语音消息]');
    _messages.add(userMessage);

    _status = AgentStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final assistantMessage = AgentMessage(role: 'assistant', content: '');
    _messages.add(assistantMessage);
    notifyListeners();

    try {
      _status = AgentStatus.streaming;
      notifyListeners();

      await for (final delta in _repository.streamOmniAnalysis(
        audioBytes,
        deviceMac,
        role: role,
      )) {
        assistantMessage.content += delta;
        notifyListeners();
      }

      _status = AgentStatus.loaded;
    } catch (_) {
      _errorMessage = '语音分析失败，请稍后再试。';
      _status = AgentStatus.error;
      assistantMessage.content = '语音解析失败。';
    }

    notifyListeners();
  }

  Future<void> ttsSpeak(BuildContext context, String text) async {
    if (text.trim().isEmpty) return;
    
    final voiceProvider = context.read<VoiceProvider>();
    final careProvider = context.read<CareProvider>();
    final deviceMac = careProvider.profile?.boundDeviceMacs.firstOrNull;

    _status = AgentStatus.loading;
    notifyListeners();

    try {
      await voiceProvider.processTts(text);
      _status = AgentStatus.loaded;
    } catch (e) {
      _errorMessage = '播报失败';
      _status = AgentStatus.error;
    }
    notifyListeners();
  }
}
