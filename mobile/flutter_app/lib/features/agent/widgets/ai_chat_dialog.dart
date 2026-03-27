import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../care/models/care_profile_model.dart';
import '../models/agent_experience.dart';
import '../providers/agent_provider.dart';
import 'agent_chat_components.dart';

class AiChatDialog extends StatefulWidget {
  final String? deviceMac;
  final List<CareAccessDeviceMetric> availableDevices;

  const AiChatDialog({
    super.key,
    this.deviceMac,
    this.availableDevices = const <CareAccessDeviceMetric>[],
  });

  @override
  State<AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<AiChatDialog> {
  static const AgentExperience _experience = AgentExperience.family;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final Set<String> _selectedDeviceMacs = <String>{};

  AgentProvider? _agentProvider;
  String _lastAssistantSnapshot = '';
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedDeviceMacs.addAll(_buildInitialSelection());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
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
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _buildInitialSelection() {
    final available = widget.availableDevices
        .map((CareAccessDeviceMetric item) => item.deviceMac.trim())
        .where((String mac) => mac.isNotEmpty)
        .toList(growable: false);
    if (available.isNotEmpty) {
      return available;
    }

    final primary = widget.deviceMac?.trim() ?? '';
    return primary.isEmpty ? const <String>[] : <String>[primary];
  }

  List<String> _orderedSelectedMacs() {
    final ordered = <String>[];
    final seen = <String>{};

    void collect(String mac) {
      final normalized = mac.trim();
      if (normalized.isEmpty || seen.contains(normalized)) {
        return;
      }
      seen.add(normalized);
      ordered.add(normalized);
    }

    for (final device in widget.availableDevices) {
      if (_selectedDeviceMacs.contains(device.deviceMac.trim())) {
        collect(device.deviceMac);
      }
    }
    for (final mac in _selectedDeviceMacs) {
      collect(mac);
    }
    return ordered;
  }

  void _handleAgentChanged() {
    final provider = _agentProvider;
    if (!mounted || provider == null) {
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

  Future<void> _sendMessage(String text) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final selectedMacs = _orderedSelectedMacs();
    if (selectedMacs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_experience.missingDeviceHint)),
      );
      return;
    }

    _textController.clear();
    _focusNode.unfocus();

    await context.read<AgentProvider>().sendMessage(
          normalizedText,
          deviceMac: selectedMacs.first,
          deviceMacs: selectedMacs,
          role: _experience.apiRole,
        );
    _scrollToBottom();
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1820),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white10),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 18,
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(),
          const SizedBox(height: 14),
          _buildDeviceBanner(),
          if (widget.availableDevices.length > 1) ...<Widget>[
            const SizedBox(height: 12),
            _buildDeviceSelector(),
          ],
          const SizedBox(height: 14),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.58,
              ),
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount:
                    provider.messages.length + (provider.status == AgentStatus.loading ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index == provider.messages.length) {
                    return AgentLoadingBubble(
                      accent: _experience.accent,
                      assistantIcon: _experience.assistantIcon,
                      label: _experience.loadingLabel,
                      compact: true,
                    );
                  }

                  final message = provider.messages[index];
                  final isUser = message.role == 'user';
                  final isStreaming = !isUser &&
                      provider.status == AgentStatus.streaming &&
                      index == provider.messages.length - 1;

                  return AgentMessageBubble(
                    text: message.content,
                    isUser: isUser,
                    isStreaming: isStreaming,
                    accent: _experience.accent,
                    assistantIcon: _experience.assistantIcon,
                    assistantLabel: _experience.assistantLabel,
                    userLabel: _experience.userLabel,
                    streamingLabel: _experience.streamingLabel,
                    fontSize: 14,
                    compact: true,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (provider.status != AgentStatus.loading &&
              provider.status != AgentStatus.streaming)
            _buildPresetSection(),
          const SizedBox(height: 12),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _experience.accent.withValues(alpha: 0.16),
          ),
          child: Icon(
            _experience.assistantIcon,
            color: _experience.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _experience.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _experience.subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildDeviceBanner() {
    final selectedMacs = _orderedSelectedMacs();
    final label = selectedMacs.isEmpty
        ? _experience.missingDeviceHint
        : selectedMacs.length == 1
            ? '当前分析对象：${selectedMacs.first}'
            : '当前分析对象：已选 ${selectedMacs.length} 台设备，可一起提问';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selectedMacs.isEmpty
              ? Colors.white10
              : _experience.accent.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            selectedMacs.isEmpty ? Icons.info_outline : Icons.devices_outlined,
            color: selectedMacs.isEmpty ? Colors.white54 : _experience.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '问答对象可多选',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.availableDevices.map((CareAccessDeviceMetric device) {
            final mac = device.deviceMac.trim();
            final isSelected = _selectedDeviceMacs.contains(mac);
            return FilterChip(
              selected: isSelected,
              showCheckmark: false,
              selectedColor: _experience.accent.withValues(alpha: 0.2),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              side: BorderSide(
                color: isSelected
                    ? _experience.accent.withValues(alpha: 0.5)
                    : Colors.white10,
              ),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    device.subjectName,
                    style: TextStyle(
                      color: isSelected ? _experience.accent : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mac,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              onSelected: (bool next) {
                setState(() {
                  if (next) {
                    _selectedDeviceMacs.add(mac);
                  } else {
                    _selectedDeviceMacs.remove(mac);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPresetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _experience.emptyPromptTitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _experience.presetPrompts.map((String prompt) {
            return ActionChip(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              side: BorderSide(
                color: _experience.accent.withValues(alpha: 0.22),
              ),
              label: Text(
                prompt,
                style: TextStyle(
                  color: _experience.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => _sendMessage(prompt),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: _experience.inputHint,
                hintStyle: const TextStyle(color: Colors.white30),
                border: InputBorder.none,
              ),
              onSubmitted: (String value) => _sendMessage(value),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: _experience.accent),
            onPressed: () => _sendMessage(_textController.text),
          ),
        ],
      ),
    );
  }
}
