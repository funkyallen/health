import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/voice_model.dart';
import '../repositories/voice_repository.dart';
import '../../../core/services/audio_service.dart';

enum VoiceLoadStatus { initial, loading, loaded, error }

class VoiceProvider extends ChangeNotifier {
  final VoiceRepository _repository;
  final AudioService _audioService;

  VoiceLoadStatus _status = VoiceLoadStatus.initial;
  VoiceStatus? _voiceStatus;
  String? _errorMessage;

  bool _isProcessing = false;
  bool _isRecording = false;
  String _lastAsrText = '';
  String _lastTtsUrl = '';

  VoiceProvider(this._repository, this._audioService);

  VoiceLoadStatus get status => _status;
  VoiceStatus? get voiceStatus => _voiceStatus;
  String? get errorMessage => _errorMessage;
  bool get isProcessing => _isProcessing;
  bool get isRecording => _isRecording;
  String get lastAsrText => _lastAsrText;
  String get lastTtsUrl => _lastTtsUrl;

  bool get isVoiceAvailable => _voiceStatus?.configured ?? false;

  Future<void> checkStatus() async {
    _status = VoiceLoadStatus.loading;
    notifyListeners();

    try {
      _voiceStatus = await _repository.getVoiceStatus();
      _status = VoiceLoadStatus.loaded;
    } catch (e) {
      _status = VoiceLoadStatus.error;
      _errorMessage = '获取语音服务状态失败';
    }
    notifyListeners();
  }

  Future<void> startRecording() async {
    if (!isVoiceAvailable) return;
    final path = await _audioService.startRecording();
    if (path != null) {
      _isRecording = true;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    notifyListeners();

    final path = await _audioService.stopRecording();
    if (path != null) {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
      await processAsr(base64Audio);
    }
  }

  Future<void> processAsr(String base64Audio) async {
    if (!isVoiceAvailable) return;
    _isProcessing = true;
    notifyListeners();

    try {
      final res = await _repository.speechToText(base64Audio);
      _lastAsrText = res.text;
    } catch (_) {
      _errorMessage = '识别失败';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> processTts(String text) async {
    if (!isVoiceAvailable) return;
    _isProcessing = true;
    notifyListeners();

    try {
      final res = await _repository.textToSpeech(text);
      _lastTtsUrl = res.audioUrl;
      // 自动播放合成内容
      if (_lastTtsUrl.isNotEmpty) {
        await _audioService.play(_lastTtsUrl);
      }
    } catch (_) {
      _errorMessage = '语音合成失败';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
