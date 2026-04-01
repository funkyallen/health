import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/audio_service.dart';
import '../services/omni_realtime_service.dart';

enum OmniVoiceStatus {
  idle,
  connecting,
  recording,
  processing,
  responding,
  error,
}

class OmniVoiceProvider extends ChangeNotifier {
  final OmniRealtimeService _omniService;
  final AudioService _audioService;
  final String apiKey;

  late final StreamSubscription<OmniEvent> _eventSubscription;

  OmniVoiceStatus _status = OmniVoiceStatus.idle;
  String _statusMessage = '';
  String _fullResponse = '';
  String _lastAsrText = '';
  String? _lastAudioPath;
  bool _isRecording = false;
  bool _hasError = false;

  OmniVoiceProvider({
    required this.apiKey,
    required OmniRealtimeService omniService,
    required AudioService audioService,
  })  : _omniService = omniService,
        _audioService = audioService {
    _eventSubscription = _omniService.eventStream.listen(_handleOmniEvent);
  }

  OmniVoiceStatus get status => _status;

  String get statusMessage => _statusMessage;

  String get fullResponse => _fullResponse;

  String get lastAsrText => _lastAsrText;

  String? get lastAudioPath => _lastAudioPath;

  bool get isRecording => _isRecording;

  bool get isConnected => _omniService.isConnected;

  bool get isProcessing => _omniService.isProcessing;

  bool get hasError => _hasError;

  void _handleOmniEvent(OmniEvent event) {
    if (event is OmniConnected) {
      _updateStatus(OmniVoiceStatus.idle, '已连接到 Qwen Omni');
      _hasError = false;
      return;
    }
    if (event is OmniConnecting) {
      _updateStatus(OmniVoiceStatus.connecting, '正在连接...');
      return;
    }
    if (event is OmniDisconnected) {
      _updateStatus(OmniVoiceStatus.idle, '已断开连接');
      return;
    }
    if (event is OmniAudioAppended) {
      _updateStatus(OmniVoiceStatus.processing, '音频已追加，处理中...');
      return;
    }
    if (event is OmniAudioCommitted) {
      _updateStatus(OmniVoiceStatus.processing, '音频已提交，等待响应...');
      return;
    }
    if (event is OmniTextDelta) {
      _fullResponse += event.text;
      _updateStatus(OmniVoiceStatus.responding, '接收响应中...');
      notifyListeners();
      return;
    }
    if (event is OmniAudioDelta) {
      unawaited(_handleAudioResponse(event.audioBase64, event.audioFormat));
      return;
    }
    if (event is OmniResponseDone) {
      _updateStatus(OmniVoiceStatus.idle, '响应完成');
      _lastAsrText = _fullResponse;
      unawaited(_playResponseAudio());
      return;
    }
    if (event is OmniErrorEvent) {
      _handleError(event.message ?? '未知错误');
    }
  }

  Future<bool> connect({String voice = 'Tina'}) async {
    try {
      _fullResponse = '';
      _updateStatus(OmniVoiceStatus.connecting, '正在连接到 Qwen Omni...');
      final success = await _omniService.connect();
      if (!success) {
        _handleError('连接失败');
        return false;
      }
      _updateStatus(OmniVoiceStatus.idle, '已连接');
      return true;
    } catch (error) {
      _handleError('连接异常: $error');
      return false;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (_isRecording) {
        return false;
      }

      _fullResponse = '';
      _updateStatus(OmniVoiceStatus.recording, '正在录音...');
      final path = await _audioService.startRecording();
      if (path == null) {
        _handleError('无法启动录音');
        return false;
      }

      _isRecording = true;
      _lastAudioPath = path;
      notifyListeners();
      return true;
    } catch (error) {
      _handleError('启动录音失败: $error');
      return false;
    }
  }

  Future<bool> stopRecordingAndProcess() async {
    try {
      if (!_isRecording) {
        return false;
      }

      _isRecording = false;
      _updateStatus(OmniVoiceStatus.processing, '正在处理音频...');
      final path = await _audioService.stopRecording();
      if (path == null) {
        _handleError('无法停止录音');
        return false;
      }

      _lastAudioPath = path;
      final file = File(path);
      if (!await file.exists()) {
        _handleError('录音文件不存在');
        return false;
      }

      final audioBytes = await file.readAsBytes();
      final audioBase64 = base64Encode(audioBytes);
      await _omniService.appendAudio(audioBase64);
      await Future.delayed(const Duration(milliseconds: 100));
      await _omniService.commitAudio();
      notifyListeners();
      return true;
    } catch (error) {
      _handleError('音频处理失败: $error');
      return false;
    }
  }

  Future<void> _handleAudioResponse(String audioBase64, String audioFormat) async {
    try {
      if (audioBase64.isEmpty) {
        return;
      }
      final audioBytes = base64Decode(audioBase64);
      await _audioService.playBytes(audioBytes, audioFormat);
    } catch (error) {
      debugPrint('处理音频响应失败: $error');
    }
  }

  Future<void> _playResponseAudio() async {
    if (_fullResponse.trim().isEmpty) {
      return;
    }
  }

  void _updateStatus(OmniVoiceStatus status, String message) {
    _status = status;
    _statusMessage = message;
    _hasError = status == OmniVoiceStatus.error;
    notifyListeners();
  }

  void _handleError(String message) {
    _hasError = true;
    _updateStatus(OmniVoiceStatus.error, message);
    debugPrint('OmniVoiceProvider error: $message');
  }

  Future<void> disconnect() async {
    if (_isRecording) {
      _isRecording = false;
      await _audioService.stopRecording();
    }
    await _omniService.disconnect();
    _updateStatus(OmniVoiceStatus.idle, '');
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    unawaited(disconnect());
    super.dispose();
  }
}
