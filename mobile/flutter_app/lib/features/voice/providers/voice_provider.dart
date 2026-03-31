import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/voice_model.dart';
import '../repositories/voice_repository.dart';
import '../../../core/services/audio_service.dart';
import '../../care/providers/care_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';

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
    if (!isVoiceAvailable) {
      debugPrint('Voice Service not available, cannot start recording.');
      return;
    }
    final path = await _audioService.startRecording();
    if (path != null) {
      debugPrint('Recording started at: $path');
      _isRecording = true;
      notifyListeners();
    } else {
      debugPrint('Failed to start recording (permissions or hardware issue).');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;
    notifyListeners();

    debugPrint('Stopping recording...');
    final path = await _audioService.stopRecording();
    if (path != null) {
      debugPrint('Recording stopped, file saved at: $path');
      // 给硬件一点刷盘时间，防止读取到空文件
      await Future.delayed(const Duration(milliseconds: 300));
      
      final file = File(path);
      if (await file.exists()) {
        final size = await file.length();
        debugPrint('Recording file size: $size bytes');
        if (size > 0) {
          await processOmniChat(path);
        } else {
          debugPrint('Error: Recording file is empty.');
        }
      } else {
        debugPrint('Error: Recording file does not exist at $path');
      }
    } else {
      debugPrint('Error: stopRecording returned null path.');
    }
  }

  Future<void> processOmniChat(String audioPath, {BuildContext? context}) async {
    if (!isVoiceAvailable) return;
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String? deviceMac;
      if (context != null) {
        final careProvider = context.read<CareProvider>();
        deviceMac = careProvider.profile?.boundDeviceMacs.firstOrNull;
      }
      
      debugPrint('Sending OmniChat request. File: $audioPath, MAC: $deviceMac');
      final res = await _repository.omniChat(audioPath, deviceMac: deviceMac);
      debugPrint('OmniChat Response received: ${res.text}');
      
      _lastAsrText = res.text;
      
      if (_lastAsrText.isNotEmpty) {
        await processTts(_lastAsrText);
      }
    } catch (e) {
      debugPrint('OmniChat Error: $e');
      if (e is DioException) {
        debugPrint('Dio Error Details: ${e.response?.statusCode} - ${e.response?.data}');
      }
      _errorMessage = '语音对讲失败，请检查网络或登录状态';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<String?> processAsr(String base64Audio) async {
    if (!isVoiceAvailable) return null;
    _isProcessing = true;
    notifyListeners();

    try {
      final res = await _repository.speechToText(base64Audio);
      _lastAsrText = res.text;
      return _lastAsrText;
    } catch (_) {
      _errorMessage = '识别失败';
      return null;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> processTts(String text) async {
    if (!isVoiceAvailable) return;
    if (text.trim().isEmpty) return;

    debugPrint('Starting TTS for text: "$text"');
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _repository.textToSpeech(text);
      _lastTtsUrl = res.audioUrl;
      debugPrint('TTS Success, audio URL: $_lastTtsUrl');

      if (_lastTtsUrl.isNotEmpty) {
        // 后端可能返回相对路径，补全它
        String finalUrl = _lastTtsUrl;
        if (!_lastTtsUrl.startsWith('http')) {
           finalUrl = '${_repository.apiEndpoint}/$_lastTtsUrl'.replaceAll('//', '/').replaceFirst(':/', '://');
        }
        debugPrint('Playing TTS from: $finalUrl');
        await _audioService.play(finalUrl);
      } else {
        debugPrint('Error: TTS audio URL is empty.');
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
      if (e is DioException) {
        debugPrint('Dio Error Details: ${e.response?.statusCode} - ${e.response?.data}');
      }
      _errorMessage = '语音播报失败';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
