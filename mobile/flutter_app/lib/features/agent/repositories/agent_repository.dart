import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

class AgentMessage {
  final String role;
  String content;

  AgentMessage({required this.role, required this.content});

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    return AgentMessage(
      role: json['role'] ?? 'assistant',
      content: json['content'] ?? '',
    );
  }
}

class AgentRepository {
  static const Duration _syntheticChunkDelay = Duration(milliseconds: 44);
  static const Duration _visualChunkDelay = Duration(milliseconds: 26);

  final ApiClient _apiClient;

  AgentRepository(this._apiClient);

  Stream<String> streamAgentAnalysis(
    String message,
    String? deviceMac, {
    List<String> deviceMacs = const <String>[],
    required String role,
  }) async* {
    final normalizedRole = role.trim().toLowerCase();
    final normalizedDeviceMacs = _normalizeDeviceMacs(
      primaryDeviceMac: deviceMac,
      deviceMacs: deviceMacs,
    );

    if (normalizedDeviceMacs.isEmpty) {
      yield* _yieldSyntheticChunks(
        normalizedRole == 'family'
            ? '当前还没有可分析的手环设备，请先确认老人账号已经绑定手环并且设备在线。'
            : '当前还没有绑定可分析的手环设备，请先回到主页确认手环已经连接。',
      );
      return;
    }

    final isFamilyMultiDevice =
        normalizedRole == 'family' && normalizedDeviceMacs.length > 1;

    final endpoint = isFamilyMultiDevice
        ? 'chat/analyze/community/stream'
        : 'chat/analyze/device/stream';
    final payload = isFamilyMultiDevice
        ? <String, dynamic>{
            'question': message,
            'role': normalizedRole,
            'mode': 'qwen',
            'provider': 'qwen',
            'scope': 'community',
            'workflow': 'free_chat',
            'device_macs': normalizedDeviceMacs,
            'history_minutes': 1440,
            'per_device_limit': 240,
          }
        : <String, dynamic>{
            'question': message,
            'device_mac': normalizedDeviceMacs.first,
            'role': normalizedRole,
            'mode': 'qwen',
          };

    try {
      final response = await _apiClient.postStream(
        endpoint,
        data: payload,
      );

      final data = response.data;
      if (data == null) {
        yield* _yieldSyntheticChunks('暂时没有拿到助手返回的数据。');
        return;
      }

      var buffer = '';
      var hasYieldedDelta = false;
      await for (final chunk in _resolveTextStream(data)) {
        if (chunk.isEmpty) {
          continue;
        }

        buffer += chunk;
        while (true) {
          final lineBreak = buffer.indexOf('\n');
          if (lineBreak == -1) {
            break;
          }

          final line = buffer.substring(0, lineBreak);
          buffer = buffer.substring(lineBreak + 1);

          final parsed = _parseStreamLine(line);
          if (parsed == null) {
            continue;
          }

          if (parsed.type == _AgentStreamEventType.delta) {
            hasYieldedDelta = true;
            yield* _yieldVisualChunks(parsed.text);
            continue;
          }

          if (!hasYieldedDelta && _containsRenderableText(parsed.text)) {
            yield* _yieldSyntheticChunks(parsed.text);
            hasYieldedDelta = true;
          }
        }
      }

      final tail = _parseStreamLine(buffer);
      if (tail == null) {
        return;
      }
      if (tail.type == _AgentStreamEventType.delta) {
        yield* _yieldVisualChunks(tail.text);
        return;
      }
      if (!hasYieldedDelta && _containsRenderableText(tail.text)) {
        yield* _yieldSyntheticChunks(tail.text);
      }
    } catch (error) {
      yield* _yieldSyntheticChunks('请求分析失败：$error');
    }
  }

  Stream<String> streamOmniAnalysis(
    List<int> audioBytes,
    String? deviceMac, {
    required String role,
    String? prompt,
  }) async* {
    final endpoint = 'omni/analyze';
    
    try {
      final formData = FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(
          audioBytes,
          filename: 'input.wav',
        ),
        'prompt': prompt ?? '请结合我的生命体征数据回答。',
        'role': role.trim().toLowerCase(),
        'device_mac': deviceMac?.trim(),
      });

      // Omni current API in this implementation is not streaming at the model level for simplicity,
      // but we wrap the response in a stream for UI consistency.
      final response = await _apiClient.post(
        endpoint,
        data: formData,
      );

      if (response.data == null || response.data['ok'] != true) {
        yield* _yieldSyntheticChunks('助手暂时无法解析您的语音。');
        return;
      }

      final text = response.data['text'] as String? ?? '';
      yield* _yieldSyntheticChunks(text);
    } catch (error) {
      yield* _yieldSyntheticChunks('语音请求失败：$error');
    }
  }

  Stream<String> _resolveTextStream(dynamic data) async* {
    if (kIsWeb) {
      final content = data is String ? data : jsonEncode(data);
      if (content.isNotEmpty) {
        yield content;
      }
      return;
    }

    if (data is String) {
      if (data.isNotEmpty) {
        yield data;
      }
      return;
    }

    if (data is List<int>) {
      if (data.isNotEmpty) {
        yield utf8.decode(data, allowMalformed: true);
      }
      return;
    }

    if (data is ResponseBody) {
      await for (final chunk in data.stream) {
        if (chunk.isEmpty) {
          continue;
        }
        yield utf8.decode(chunk, allowMalformed: true);
      }
      return;
    }

    if (data is Stream) {
      await for (final chunk in data) {
        if (chunk is List<int> && chunk.isNotEmpty) {
          yield utf8.decode(chunk, allowMalformed: true);
          continue;
        }
        if (chunk is String && chunk.isNotEmpty) {
          yield chunk;
        }
      }
      return;
    }

    final fallback = jsonEncode(data);
    if (fallback.isNotEmpty) {
      yield fallback;
    }
  }

  _ParsedAgentStreamLine? _parseStreamLine(String rawLine) {
    final payloadLine = rawLine.trimLeft();
    if (payloadLine.trim().isEmpty) {
      return null;
    }

    final payload = payloadLine.startsWith('data:')
        ? payloadLine.substring(5).trimLeft()
        : payloadLine;
    if (payload.trim().isEmpty || payload.trim() == '[DONE]') {
      return null;
    }

    try {
      final event = jsonDecode(payload) as Map<String, dynamic>;
      final type = event['type'] as String? ?? '';

      if (type == 'answer.delta') {
        final delta = event['delta'] as String? ?? '';
        if (!_containsRenderableText(delta)) {
          return null;
        }
        return _ParsedAgentStreamLine(
          type: _AgentStreamEventType.delta,
          text: delta,
        );
      }

      if (type == 'answer.completed') {
        final answer = (event['answer'] as String? ?? '').trim();
        if (answer.isEmpty) {
          return null;
        }
        return _ParsedAgentStreamLine(
          type: _AgentStreamEventType.completed,
          text: answer,
        );
      }

      return null;
    } catch (_) {
      if (!_containsRenderableText(payload)) {
        return null;
      }
      return _ParsedAgentStreamLine(
        type: _AgentStreamEventType.delta,
        text: payload,
      );
    }
  }

  Stream<String> _yieldSyntheticChunks(String text) async* {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    for (final chunk in _splitIntoChunks(normalized)) {
      yield chunk;
      await Future<void>.delayed(_syntheticChunkDelay);
    }
  }

  Stream<String> _yieldVisualChunks(String text) async* {
    final normalized = text;
    if (!_containsRenderableText(normalized)) {
      return;
    }

    for (final chunk in _splitIntoVisualChunks(normalized)) {
      yield chunk;
      await Future<void>.delayed(_visualChunkDelay);
    }
  }

  List<String> _splitIntoChunks(String text) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    final normalized = text.replaceAll('\r\n', '\n');

    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      final current = buffer.toString();
      final reachedSoftBoundary =
          _isBoundaryCharacter(char) && current.trim().length >= 8;
      final reachedHardBoundary = current.length >= 20;
      final reachedParagraphBoundary =
          char == '\n' && current.trim().isNotEmpty;

      if (reachedParagraphBoundary || reachedHardBoundary || reachedSoftBoundary) {
        final value = current;
        if (_containsRenderableText(value)) {
          chunks.add(value);
        }
        buffer.clear();
      }
    }

    final tail = buffer.toString();
    if (_containsRenderableText(tail)) {
      chunks.add(tail);
    }
    return chunks.isEmpty ? <String>[text] : chunks;
  }

  List<String> _splitIntoVisualChunks(String text) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    final normalized = text.replaceAll('\r\n', '\n');

    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      final current = buffer.toString();
      final reachedBoundary =
          _isBoundaryCharacter(char) && current.trim().length >= 4;
      final reachedHardBoundary = current.length >= 8;
      final reachedParagraphBoundary =
          char == '\n' && current.trim().isNotEmpty;

      if (reachedParagraphBoundary || reachedHardBoundary || reachedBoundary) {
        chunks.add(current);
        buffer.clear();
      }
    }

    final tail = buffer.toString();
    if (tail.isNotEmpty) {
      chunks.add(tail);
    }
    return chunks.where(_containsRenderableText).toList(growable: false);
  }

  List<String> _normalizeDeviceMacs({
    String? primaryDeviceMac,
    required List<String> deviceMacs,
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void collect(String? value) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty || seen.contains(normalized)) {
        return;
      }
      seen.add(normalized);
      ordered.add(normalized);
    }

    for (final device in deviceMacs) {
      collect(device);
    }
    collect(primaryDeviceMac);
    return ordered;
  }

  static bool _isBoundaryCharacter(String char) {
    return '，。；：！？,.!?\n'.contains(char);
  }

  static bool _containsRenderableText(String value) {
    return value.trim().isNotEmpty || value.contains('\n');
  }
}

enum _AgentStreamEventType { delta, completed }

class _ParsedAgentStreamLine {
  final _AgentStreamEventType type;
  final String text;

  const _ParsedAgentStreamLine({
    required this.type,
    required this.text,
  });
}
