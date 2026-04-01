import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/omni_7b_voice_provider.dart';

/// Qwen2.5-Omni-7B 简化测试页面
class SimpleOmni7bTestPage extends StatefulWidget {
  const SimpleOmni7bTestPage({super.key});

  @override
  State<SimpleOmni7bTestPage> createState() => _SimpleOmni7bTestPageState();
}

class _SimpleOmni7bTestPageState extends State<SimpleOmni7bTestPage> {
  final _messageController = TextEditingController();
  late Omni7bVoiceProvider _provider;
  String _lastMessage = '';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _provider = context.read<Omni7bVoiceProvider>();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qwen2.5-Omni-7B 测试'),
        backgroundColor: Colors.purple,
      ),
      body: Consumer<Omni7bVoiceProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // 状态显示
              Container(
                color: _getStatusColor(provider.status),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (provider.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          provider.errorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 对话历史显示（优先）
              Expanded(
                child: provider.history.isEmpty
                    ? Center(
                        child: Text(
                          provider.status.name == 'error' ? '出错了' : '等待响应...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: provider.history.length,
                        itemBuilder: (context, index) {
                          final item = provider.history[index];
                          final bgColor = item.sender == '用户' ? Colors.purple[50] : Colors.blue[50];
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.sender,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: item.sender == '用户' ? Colors.purple : Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(item.text, style: const TextStyle(fontSize: 15)),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // 输入区域
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Column(
                  children: [
                    // 文本输入
                    TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: '输入问题或消息',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabled: !provider.isLoading,
                      ),
                      maxLines: null,
                      minLines: 3,
                    ),
                    const SizedBox(height: 12),

                    // 按钮区域
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: provider.isLoading
                                ? null
                                : () async {
                                    final text = _messageController.text;
                                    if (text.isNotEmpty) {
                                      _lastMessage = text;
                                      _messageController.clear();
                                      await provider.sendText(text);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                              provider.isLoading ? '处理中...' : '发送文本',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            _messageController.clear();
                            provider.clearResponse();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 录音和音频按钮
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: provider.isLoading
                                ? null
                                : () async {
                                    if (!_isRecording) {
                                      setState(() {
                                        _isRecording = true;
                                        _provider.clearResponse();
                                      });
                                      await _provider.startRecording();
                                    } else {
                                      setState(() {
                                        _isRecording = false;
                                      });
                                      await _provider.stopRecording();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecording ? Colors.red : Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(
                              _isRecording ? '停止录音' : '开始录音',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton(
                            onPressed: provider.recordedAudioPath != null && !provider.isLoading
                                ? () async {
                                    await _provider.playRecordedAudio();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('播放录音'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: provider.recordedAudioPath != null && !provider.isLoading
                                ? () async {
                                    await _provider.sendAudio(provider.recordedAudioPath!);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('发送录音'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: provider.recordedAudioPath != null && _messageController.text.isNotEmpty && !provider.isLoading
                                ? () async {
                                    final text = _messageController.text;
                                    _lastMessage = text;
                                    _messageController.clear();
                                    await _provider.sendTextWithAudio(text: text, audioPath: provider.recordedAudioPath!);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('文本+录音'),
                          ),
                        ),
                      ],
                    ),


                    // 重试按钮
                    if (provider.status.name == 'error' && _lastMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () =>
                                provider.retry(_lastMessage),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('重试'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getStatusColor(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.idle:
        return Colors.grey[600]!;
      case VoiceStatus.processing:
        return Colors.blue;
      case VoiceStatus.sending:
        return Colors.orange;
      case VoiceStatus.error:
        return Colors.red;
    }
  }
}
