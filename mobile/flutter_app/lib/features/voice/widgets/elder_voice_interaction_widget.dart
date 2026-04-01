import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../voice/providers/omni_voice_provider.dart';

/// 老人语音交互 UI 组件
/// 提供简洁的语音输入/输出界面和实时反馈
class ElderVoiceInteractionWidget extends StatefulWidget {
  final String? deviceMac;
  final VoidCallback? onResponseReceived;
  final String voice;

  const ElderVoiceInteractionWidget({
    super.key,
    this.deviceMac,
    this.onResponseReceived,
    this.voice = 'Tina',
  });

  @override
  State<ElderVoiceInteractionWidget> createState() =>
      _ElderVoiceInteractionWidgetState();
}

class _ElderVoiceInteractionWidgetState
    extends State<ElderVoiceInteractionWidget> {
  late OmniVoiceProvider _voiceProvider;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVoice();
    });
  }

  Future<void> _initializeVoice() async {
    _voiceProvider = context.read<OmniVoiceProvider>();
    if (!_voiceProvider.isConnected) {
      final success = await _voiceProvider.connect(voice: widget.voice);
      if (success && mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _handleStartRecording() async {
    final success = await _voiceProvider.startRecording();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法启动录音，请检查麦克风权限')),
      );
    }
  }

  Future<void> _handleStopRecording() async {
    final success = await _voiceProvider.stopRecordingAndProcess();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音频处理失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OmniVoiceProvider>(
      builder: (context, voiceProvider, child) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade50,
                Colors.purple.shade50,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.blue.shade200,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 状态指示
              _buildStatusIndicator(voiceProvider),

              const SizedBox(height: 16),

              // 录音按钮
              if (!voiceProvider.isRecording)
                _buildStartButton(voiceProvider)
              else
                _buildStopButton(voiceProvider),

              const SizedBox(height: 20),

              // 响应文本
              if (voiceProvider.fullResponse.isNotEmpty)
                _buildResponseCard(voiceProvider),

              // 错误提示
              if (voiceProvider.hasError)
                _buildErrorCard(voiceProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(OmniVoiceProvider voiceProvider) {
    final statusColor = _getStatusColor(voiceProvider.status);
    final statusText = _getStatusText(voiceProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: statusColor,
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton(OmniVoiceProvider voiceProvider) {
    final isAvailable =
        voiceProvider.isConnected && !voiceProvider.isProcessing;

    return ElevatedButton.icon(
      onPressed: isAvailable ? _handleStartRecording : null,
      icon: const Icon(Icons.mic, size: 28),
      label: const Text(
        '按住说话',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
      ),
    );
  }

  Widget _buildStopButton(OmniVoiceProvider voiceProvider) {
    return ElevatedButton.icon(
      onPressed: _handleStopRecording,
      icon: const Icon(Icons.stop, size: 28),
      label: const Text(
        '停止说话',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
      ),
    );
  }

  Widget _buildResponseCard(OmniVoiceProvider voiceProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.shade100,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI 回复：',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            voiceProvider.fullResponse,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(OmniVoiceProvider voiceProvider) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              voiceProvider.statusMessage,
              style: TextStyle(
                fontSize: 14,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(OmniVoiceStatus status) {
    return switch (status) {
      OmniVoiceStatus.idle => Colors.grey,
      OmniVoiceStatus.connecting => Colors.orange,
      OmniVoiceStatus.recording => Colors.red,
      OmniVoiceStatus.processing => Colors.yellow.shade700,
      OmniVoiceStatus.responding => Colors.blue,
      OmniVoiceStatus.error => Colors.red.shade700,
    };
  }

  String _getStatusText(OmniVoiceProvider voiceProvider) {
    if (voiceProvider.statusMessage.isNotEmpty) {
      return voiceProvider.statusMessage;
    }

    return switch (voiceProvider.status) {
      OmniVoiceStatus.idle => '就绪',
      OmniVoiceStatus.connecting => '正在连接...',
      OmniVoiceStatus.recording => '正在录音...',
      OmniVoiceStatus.processing => '处理中...',
      OmniVoiceStatus.responding => '接收响应...',
      OmniVoiceStatus.error => '错误',
    };
  }

  @override
  void dispose() {
    super.dispose();
  }
}
