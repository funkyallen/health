import 'package:flutter/material.dart';

import '../repositories/agent_repository.dart';

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

  Future<void> ttsSpeak(String text) async {
    // This is a placeholder for triggering TTS. 
    // In a real app, we would call a TTS repository/service here.
    debugPrint('TTS Speaking: $text');
  }
}
