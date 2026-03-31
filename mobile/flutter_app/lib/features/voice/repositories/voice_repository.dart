import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../models/voice_model.dart';

class VoiceRepository {
  final ApiClient _apiClient;

  VoiceRepository(this._apiClient);

  String get apiEndpoint => _apiClient.baseUrl;

  Future<VoiceStatus> getVoiceStatus() async {
    final response = await _apiClient.get('voice/status');
    return VoiceStatus.fromJson(response.data);
  }

  Future<AsrResponse> speechToText(String base64Audio) async {
    final response = await _apiClient.post('voice/asr', data: {'audio_base64': base64Audio});
    return AsrResponse.fromJson(response.data);
  }

  Future<AsrResponse> omniChat(String audioPath, {String? deviceMac, String? role}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(audioPath, filename: 'input.wav'),
      'device_mac': deviceMac ?? '',
      'role': role ?? 'elder',
    });
    final response = await _apiClient.post('omni/analyze', data: formData);
    return AsrResponse.fromJson(response.data);
  }

  Future<TtsResponse> textToSpeech(String text) async {
    final response = await _apiClient.post('voice/tts', data: {'text': text});
    return TtsResponse.fromJson(response.data);
  }
}
