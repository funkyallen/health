import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Future<bool> requestPermissions() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String?> startRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      if (!await requestPermissions()) {
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc, 
        sampleRate: 16000, 
        bitRate: 128000,
      );

      await _recorder.start(config, path: path);
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stop();
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<void> play(String source) async {
    try {
      if (source.startsWith('http') || source.startsWith('https')) {
        await _player.play(UrlSource(source));
      } else if (source.startsWith('data:audio')) {
        // Handle base64 data URI if needed, but usually we get URLs or b64 strings
        // For simplicity, let's assume synthesized audio is played from URL or we save it to file
      } else {
        await _player.play(DeviceFileSource(source));
      }
    } catch (e) {
      // Log error
    }
  }

  Future<void> playBase64(String base64Content, String format) async {
    try {
      final bytes = Uri.parse('data:audio/$format;base64,$base64Content').data!.contentAsBytes();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/temp_tts.$format');
      await file.writeAsBytes(bytes);
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      // Log error
    }
  }

  Future<void> stopPlayback() async {
    await _player.stop();
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
