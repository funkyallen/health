import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/logout_action.dart';
import '../../care/models/care_profile_model.dart';
import '../../care/providers/care_provider.dart';
import '../../care/screens/elder_home_screen.dart';
import '../../voice/providers/voice_provider.dart';
import '../models/agent_experience.dart';
import '../providers/agent_provider.dart';
import '../widgets/agent_chat_components.dart';

class ElderAgentScreen extends StatefulWidget {
  final String? deviceMac;

  const ElderAgentScreen({super.key, this.deviceMac});

  @override
  State<ElderAgentScreen> createState() => _ElderAgentScreenState();
}

class _ElderAgentScreenState extends State<ElderAgentScreen> {
  static const AgentExperience _experience = AgentExperience.elder;

  final ScrollController _scrollController = ScrollController();

  AgentProvider? _agentProvider;
  String _lastAssistantSnapshot = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<CareProvider>().fetchProfile();
      context.read<AgentProvider>().init(_experience.introMessage);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AgentProvider>();
    if (!identical(_agentProvider, provider)) {
      _agentProvider?.removeListener(_handleAgentChanged);
      _agentProvider = provider;
      _agentProvider?.addListener(_handleAgentChanged);
    }
  }

  @override
  void dispose() {
    _agentProvider?.removeListener(_handleAgentChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAgentChanged() {
    if (!mounted) {
      return;
    }

    final provider = _agentProvider;
    if (provider == null) {
      return;
    }

    final messages = provider.messages;
    final currentAssistantSnapshot =
        messages.isNotEmpty ? messages.last.content : '';
    final shouldScroll = messages.length != _lastMessageCount ||
        currentAssistantSnapshot != _lastAssistantSnapshot ||
        provider.status == AgentStatus.loading ||
        provider.status == AgentStatus.streaming;

    _lastMessageCount = messages.length;
    _lastAssistantSnapshot = currentAssistantSnapshot;

    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  String? _resolveDeviceMac() {
    final directMac = widget.deviceMac?.trim();
    if (directMac != null && directMac.isNotEmpty) {
      return directMac;
    }

    final profile = context.read<CareProvider>().profile;
    return _resolveDeviceMacFromProfile(profile);
  }

  String? _resolveDeviceMacFromProfile(CareAccessProfile? profile) {
    if (profile != null && profile.deviceMetrics.isNotEmpty) {
      final metricMac = profile.deviceMetrics.first.deviceMac.trim();
      if (metricMac.isNotEmpty) {
        return metricMac;
      }
    }

    if (profile != null && profile.boundDeviceMacs.isNotEmpty) {
      final boundMac = profile.boundDeviceMacs.first.trim();
      if (boundMac.isNotEmpty) {
        return boundMac;
      }
    }

    return null;
  }

  Future<void> _sendMessage(String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final deviceMac = _resolveDeviceMac();
    if (deviceMac == null || deviceMac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_experience.missingDeviceHint)),
      );
      return;
    }

    await context.read<AgentProvider>().sendMessage(
          normalizedText,
          deviceMac: deviceMac,
          role: _experience.apiRole,
        );
    _handleAssistantResponse();
    _scrollToBottom();
  }

  void _handleAssistantResponse() {
    if (!mounted) {
      return;
    }

    final messages = context.read<AgentProvider>().messages;
    if (messages.isEmpty || messages.last.role != 'assistant') {
      return;
    }

    final lastContent = messages.last.content.trim();
    if (lastContent.isEmpty) {
      return;
    }

    context.read<VoiceProvider>().processTts(lastContent);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _goToHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const ElderHomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentProvider = context.watch<AgentProvider>();
    final voiceProvider = context.watch<VoiceProvider>();
    final careProvider = context.watch<CareProvider>();
    final currentDeviceMac = widget.deviceMac?.trim().isNotEmpty == true
        ? widget.deviceMac!.trim()
        : _resolveDeviceMacFromProfile(careProvider.profile);

    return Scaffold(
      backgroundColor: const Color(0xFF08161B),
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goToHome,
          icon: const Icon(Icons.home_outlined, color: Colors.white70),
          tooltip: '回到主页',
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _experience.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _experience.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: const <Widget>[LogoutAction()],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF08161B),
              Color(0xFF091A20),
              Color(0xFF071115),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _buildHeroCard(currentDeviceMac),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                itemCount: agentProvider.messages.length +
                    (agentProvider.status == AgentStatus.loading ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index == agentProvider.messages.length) {
                    return AgentLoadingBubble(
                      accent: _experience.accent,
                      assistantIcon: _experience.assistantIcon,
                      label: _experience.loadingLabel,
                    );
                  }

                  final message = agentProvider.messages[index];
                  final isUser = message.role == 'user';
                  final isStreaming = !isUser &&
                      agentProvider.status == AgentStatus.streaming &&
                      index == agentProvider.messages.length - 1;

                  return AgentMessageBubble(
                    text: message.content,
                    isUser: isUser,
                    isStreaming: isStreaming,
                    accent: _experience.accent,
                    assistantIcon: _experience.assistantIcon,
                    assistantLabel: _experience.assistantLabel,
                    userLabel: _experience.userLabel,
                    streamingLabel: _experience.streamingLabel,
                    fontSize: isUser ? 19 : 21,
                  );
                },
              ),
            ),
            if (agentProvider.status != AgentStatus.loading &&
                agentProvider.status != AgentStatus.streaming)
              _buildPresetSection(),
            _buildVoiceInputSection(voiceProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(String? deviceMac) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _experience.accent.withValues(alpha: 0.25),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _experience.accent.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _experience.accent.withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.watch_outlined,
              color: _experience.accent,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '我会先看手环最近的变化，再用容易听懂的话告诉您重点。',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  deviceMac == null || deviceMac.isEmpty
                      ? '还没有拿到当前手环信息'
                      : '当前分析设备：$deviceMac',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _goToHome,
            child: const Text('回主页看参数'),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _experience.emptyPromptTitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ..._experience.presetPrompts.map((String prompt) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _sendMessage(prompt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    foregroundColor: _experience.accent,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: _experience.accent.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Text(
                    prompt,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVoiceInputSection(VoiceProvider voiceProvider) {
    final helperText = voiceProvider.isRecording
        ? '正在听您说话...'
        : (voiceProvider.isProcessing ? '正在整理成问题...' : '长按话筒跟我说话');

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 36),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1D24),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            helperText,
            style: TextStyle(
              color: voiceProvider.isRecording
                  ? _experience.accent
                  : Colors.white54,
              fontSize: 18,
              fontWeight: voiceProvider.isRecording
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onLongPressStart: (_) => voiceProvider.startRecording(),
            onLongPressEnd: (_) async {
              await voiceProvider.stopRecording();
              if (voiceProvider.lastAsrText.isNotEmpty) {
                await _sendMessage(voiceProvider.lastAsrText);
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (voiceProvider.isRecording)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 1.0, end: 1.45),
                    duration: const Duration(milliseconds: 720),
                    builder: (BuildContext context, double value, Widget? child) {
                      return Container(
                        width: 108 * value,
                        height: 108 * value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _experience.accent.withValues(
                            alpha: 0.22 * (1.65 - value),
                          ),
                        ),
                      );
                    },
                  ),
                CircleAvatar(
                  radius: 52,
                  backgroundColor:
                      voiceProvider.isRecording || voiceProvider.isProcessing
                          ? _experience.accent
                          : Colors.white.withValues(alpha: 0.1),
                  child: Icon(
                    voiceProvider.isProcessing ? Icons.graphic_eq : Icons.mic,
                    size: 50,
                    color:
                        voiceProvider.isRecording || voiceProvider.isProcessing
                            ? const Color(0xFF08161B)
                            : _experience.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
