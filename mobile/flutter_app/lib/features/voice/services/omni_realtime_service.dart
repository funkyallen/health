import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class OmniRealtimeService {
  static const String _wsUrl =
      'wss://dashscope.aliyuncs.com/api-ws/v1/realtime';

  final String apiKey;
  final String model;
  final String voice;
  final bool enableAudioOutput;

  WebSocketChannel? _channel;
  final StreamController<OmniEvent> _eventController =
      StreamController<OmniEvent>.broadcast();
  bool _isConnected = false;
  bool _isAudioSubmitted = false;

  OmniRealtimeService({
    required this.apiKey,
    this.model = 'qwen2.5-omni-7b',
    this.voice = 'Tina',
    this.enableAudioOutput = false,
  });

  Stream<OmniEvent> get eventStream => _eventController.stream;

  bool get isConnected => _isConnected;

  bool get isProcessing => _isAudioSubmitted;

  Future<bool> connect() async {
    try {
      _emitEvent(OmniEvent.connecting());

      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await Future.delayed(const Duration(milliseconds: 100));

      _sendAuthorizationRequest();

      _channel!.stream.listen(
        _handleServerMessage,
        onError: _handleError,
        onDone: _handleConnectionClosed,
        cancelOnError: true,
      );

      _isConnected = true;
      _emitEvent(OmniEvent.connected());
      return true;
    } catch (error) {
      _emitEvent(OmniEvent.error('连接失败: $error'));
      return false;
    }
  }

  void _sendAuthorizationRequest() {
    final event = <String, Object>{
      'type': 'session.update',
      'session': <String, Object>{
        'modalities': enableAudioOutput ? ['text', 'audio'] : ['text'],
        'voice': voice,
        'max_tokens': 2048,
      },
    };
    _channel?.sink.add(jsonEncode(event));
  }

  Future<void> appendAudio(String audioBase64) async {
    if (!_isConnected) {
      throw Exception('未连接到服务端');
    }

    try {
      _isAudioSubmitted = true;
      _emitEvent(OmniEvent.audioAppended());
      _channel?.sink.add(jsonEncode(<String, Object>{
        'type': 'input_audio_buffer.append',
        'audio': audioBase64,
      }));
    } catch (error) {
      _emitEvent(OmniEvent.error('追加音频失败: $error'));
      rethrow;
    }
  }

  Future<void> commitAudio() async {
    if (!_isConnected) {
      throw Exception('未连接到服务端');
    }

    try {
      _channel?.sink.add(jsonEncode(<String, Object>{
        'type': 'input_audio_buffer.commit',
      }));
      _emitEvent(OmniEvent.audioCommitted());
    } catch (error) {
      _emitEvent(OmniEvent.error('提交音频失败: $error'));
      rethrow;
    }
  }

  void _handleServerMessage(dynamic message) {
    try {
      if (message is! String) {
        return;
      }

      final json = jsonDecode(message) as Map<String, dynamic>;
      final eventType = json['type'] as String?;

      switch (eventType) {
        case 'session.created':
          _emitEvent(OmniEvent.sessionCreated());
          break;
        case 'session.updated':
          _emitEvent(OmniEvent.sessionUpdated());
          break;
        case 'conversation.item.created':
          _handleItemCreated(json);
          break;
        case 'response.text.delta':
          _handleTextDelta(json);
          break;
        case 'response.audio.delta':
          _handleAudioDelta(json);
          break;
        case 'response.done':
          _handleResponseDone();
          break;
        case 'response.function_call_arguments.done':
          _emitEvent(OmniEvent.functionCallDone());
          break;
        case 'error':
          _handleErrorEvent(json);
          break;
        default:
          if (kDebugMode) {
            debugPrint('Unhandled omni event: $eventType');
          }
      }
    } catch (error) {
      debugPrint('Failed to process omni message: $error');
    }
  }

  void _handleItemCreated(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>?;
    final role = item?['type'] as String?;
    if (role == 'user') {
      _emitEvent(OmniEvent.userItemCreated());
    } else if (role == 'assistant') {
      _emitEvent(OmniEvent.assistantItemCreated());
    }
  }

  void _handleTextDelta(Map<String, dynamic> json) {
    final delta = json['delta'] as String?;
    if (delta != null && delta.isNotEmpty) {
      _emitEvent(OmniEvent.textDelta(delta));
    }
  }

  void _handleAudioDelta(Map<String, dynamic> json) {
    final audioBase64 = json['audio'] as String?;
    final audioFormat = json['fmt'] as String? ?? 'wav';
    if (audioBase64 != null && audioBase64.isNotEmpty) {
      _emitEvent(OmniEvent.audioDelta(audioBase64, audioFormat));
    }
  }

  void _handleResponseDone() {
    _isAudioSubmitted = false;
    _emitEvent(OmniEvent.responseDone());
  }

  void _handleErrorEvent(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;
    final message = error?['message'] as String? ?? '未知错误';
    _emitEvent(OmniEvent.error('服务端错误: $message'));
  }

  void _handleError(Object error) {
    _isConnected = false;
    _emitEvent(OmniEvent.error('WebSocket 错误: $error'));
  }

  void _handleConnectionClosed() {
    _isConnected = false;
    _isAudioSubmitted = false;
    _emitEvent(OmniEvent.disconnected());
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _isAudioSubmitted = false;
    await _channel?.sink.close();
    _emitEvent(OmniEvent.disconnected());
  }

  void _emitEvent(OmniEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void dispose() {
    _eventController.close();
    _channel?.sink.close();
  }
}

sealed class OmniEvent {
  final String? message;

  const OmniEvent({this.message});

  factory OmniEvent.connecting() => const OmniConnecting();

  factory OmniEvent.connected() => const OmniConnected();

  factory OmniEvent.disconnected() => const OmniDisconnected();

  factory OmniEvent.sessionCreated() => const OmniSessionCreated();

  factory OmniEvent.sessionUpdated() => const OmniSessionUpdated();

  factory OmniEvent.userItemCreated() => const OmniUserItemCreated();

  factory OmniEvent.assistantItemCreated() => const OmniAssistantItemCreated();

  factory OmniEvent.audioAppended() => const OmniAudioAppended();

  factory OmniEvent.audioCommitted() => const OmniAudioCommitted();

  factory OmniEvent.textDelta(String text) => OmniTextDelta(text);

  factory OmniEvent.audioDelta(String audioBase64, String format) =>
      OmniAudioDelta(audioBase64, format);

  factory OmniEvent.responseDone() => const OmniResponseDone();

  factory OmniEvent.functionCallDone() => const OmniFunctionCallDone();

  factory OmniEvent.error(String message) => OmniErrorEvent(message);
}

class OmniConnecting extends OmniEvent {
  const OmniConnecting() : super(message: 'connecting');
}

class OmniConnected extends OmniEvent {
  const OmniConnected() : super(message: 'connected');
}

class OmniDisconnected extends OmniEvent {
  const OmniDisconnected() : super(message: 'disconnected');
}

class OmniSessionCreated extends OmniEvent {
  const OmniSessionCreated() : super(message: 'session_created');
}

class OmniSessionUpdated extends OmniEvent {
  const OmniSessionUpdated() : super(message: 'session_updated');
}

class OmniUserItemCreated extends OmniEvent {
  const OmniUserItemCreated() : super(message: 'user_item_created');
}

class OmniAssistantItemCreated extends OmniEvent {
  const OmniAssistantItemCreated() : super(message: 'assistant_item_created');
}

class OmniAudioAppended extends OmniEvent {
  const OmniAudioAppended() : super(message: 'audio_appended');
}

class OmniAudioCommitted extends OmniEvent {
  const OmniAudioCommitted() : super(message: 'audio_committed');
}

class OmniTextDelta extends OmniEvent {
  final String text;

  const OmniTextDelta(this.text) : super(message: text);
}

class OmniAudioDelta extends OmniEvent {
  final String audioBase64;
  final String audioFormat;

  const OmniAudioDelta(this.audioBase64, this.audioFormat);
}

class OmniResponseDone extends OmniEvent {
  const OmniResponseDone() : super(message: 'response_done');
}

class OmniFunctionCallDone extends OmniEvent {
  const OmniFunctionCallDone() : super(message: 'function_call_done');
}

class OmniErrorEvent extends OmniEvent {
  const OmniErrorEvent(String message) : super(message: message);
}
