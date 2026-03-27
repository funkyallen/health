import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/logout_action.dart';
import '../../agent/widgets/ai_chat_dialog.dart';
import '../../alarm/providers/alarm_provider.dart';
import '../../alarm/screens/alarm_center_screen.dart';
import '../../health/providers/health_provider.dart';
import '../../health/repositories/health_repository.dart';
import '../../health/screens/device_detail_screen.dart';
import '../../settings/screens/server_settings_screen.dart';
import '../../voice/screens/voice_screen.dart';
import '../models/care_profile_model.dart';
import '../providers/care_provider.dart';

class FamilySubjectCardViewModel {
  final String elderId;
  final String subjectName;
  final String apartment;
  final CareAccessDeviceMetric? metric;

  const FamilySubjectCardViewModel({
    required this.elderId,
    required this.subjectName,
    required this.apartment,
    required this.metric,
  });

  bool get hasDevice => metric != null;
}

class FamilyHomeScreen extends StatefulWidget {
  const FamilyHomeScreen({super.key});

  @override
  State<FamilyHomeScreen> createState() => _FamilyHomeScreenState();
}

class _FamilyHomeScreenState extends State<FamilyHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CareProvider>().startAutoRefresh();
    });
  }

  @override
  void dispose() {
    context.read<CareProvider>().stopAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final careProvider = context.watch<CareProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF08161B),
      appBar: AppBar(
        title: const Text(
          '家人守护',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          _buildAlarmAction(context),
          const LogoutAction(),
          IconButton(
            icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (BuildContext context) =>
                      const ServerSettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => careProvider.fetchProfile(),
          ),
        ],
      ),
      body: _buildBody(careProvider),
    );
  }

  Widget _buildAlarmAction(BuildContext context) {
    final hasUnacknowledged = context
        .watch<AlarmProvider>()
        .alarms
        .any((alarm) => !alarm.acknowledged);

    return Stack(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const AlarmCenterScreen(),
              ),
            );
          },
        ),
        if (hasUnacknowledged)
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(CareProvider provider) {
    if (provider.status == CareLoadStatus.loading && provider.profile == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF875A)),
      );
    }

    if (provider.status == CareLoadStatus.error && provider.profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              provider.errorMessage ?? '加载失败',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.fetchProfile(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final profile = provider.profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }

    final subjects = _buildSubjects(provider, profile);
    if (subjects.isEmpty) {
      return _buildUnboundState();
    }

    return _buildBoundState(subjects);
  }

  List<FamilySubjectCardViewModel> _buildSubjects(
    CareProvider provider,
    CareAccessProfile profile,
  ) {
    final elders = provider.familyDirectory?.elders;
    if (elders == null || elders.isEmpty) {
      return profile.deviceMetrics
          .map(
            (CareAccessDeviceMetric metric) => FamilySubjectCardViewModel(
              elderId: metric.elderId ?? metric.deviceMac,
              subjectName: metric.subjectName,
              apartment: '--',
              metric: metric,
            ),
          )
          .toList(growable: false);
    }

    return elders.map((elder) {
      CareAccessDeviceMetric? matchedMetric;
      for (final metric in profile.deviceMetrics) {
        if (metric.elderId == elder.id) {
          matchedMetric = metric;
          break;
        }
      }

      return FamilySubjectCardViewModel(
        elderId: elder.id,
        subjectName: elder.name,
        apartment: elder.apartment,
        metric: matchedMetric,
      );
    }).toList(growable: false);
  }

  Widget _buildUnboundState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const <Widget>[
            Icon(Icons.people_outline, size: 80, color: Colors.white24),
            SizedBox(height: 24),
            Text(
              '当前还没有关联的老人监护对象',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              '等老人账号与家庭账号建立关联后，这里会显示对应的健康监测对象和设备状态。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoundState(List<FamilySubjectCardViewModel> subjects) {
    final availableDevices = subjects
        .where((FamilySubjectCardViewModel subject) => subject.metric != null)
        .map((FamilySubjectCardViewModel subject) => subject.metric!)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _buildRealtimeBanner(),
        const SizedBox(height: 20),
        _buildSectionTitle('我的关注'),
        ...subjects.map(_buildSubjectCard),
        const SizedBox(height: 16),
        _buildVoiceEntry(context),
        const SizedBox(height: 24),
        _buildSectionTitle('AI 健康对话'),
        _buildAgentEntry(context, availableDevices),
      ],
    );
  }

  Widget _buildRealtimeBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF875A).withValues(alpha: 0.2),
        ),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.podcasts, color: Color(0xFFFF875A)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '已开启自动刷新，会持续同步家庭关注对象的最新监测状态。',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubjectCard(FamilySubjectCardViewModel subject) {
    final metric = subject.metric;
    if (metric == null) {
      return _buildNoDeviceCard(subject);
    }

    final healthScore = metric.healthScore;
    final healthy = (healthScore ?? 0) >= 80;

    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (BuildContext context) => ChangeNotifierProvider(
                create: (BuildContext context) => HealthProvider(
                  context.read<HealthRepository>(),
                  metric.deviceMac,
                ),
                child: DeviceDetailScreen(deviceMac: metric.deviceMac),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.watch, color: Color(0xFFFF875A)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          subject.subjectName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${subject.apartment} · ${metric.deviceName} · ${metric.deviceMac}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: healthy
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '健康度 ${healthScore ?? '--'}',
                      style: TextStyle(
                        color:
                            healthy ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildMetricItem(
                    Icons.favorite,
                    '心率',
                    '${metric.heartRate?.toInt() ?? '--'} bpm',
                  ),
                  _buildMetricItem(
                    Icons.monitor_heart_outlined,
                    '血压',
                    metric.bloodPressure ?? '--',
                  ),
                  _buildMetricItem(
                    Icons.water_drop,
                    '血氧',
                    '${metric.bloodOxygen?.toInt() ?? '--'} %',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoDeviceCard(FamilySubjectCardViewModel subject) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.person_outline, color: Color(0xFF6FD3FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        subject.subjectName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subject.apartment,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '无设备',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '当前还没有绑定手环，绑定后即可查看实时指标、异常告警和趋势曲线。',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(IconData icon, String label, String value) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 20, color: Colors.white54),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildVoiceEntry(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const VoiceScreen(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              const Color(0xFFFF875A).withValues(alpha: 0.1),
              Colors.transparent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFF875A).withValues(alpha: 0.2),
          ),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.mic_none, color: Color(0xFFFF875A), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '智能语音交互',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '语音转文字与合成播报',
                    style: TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentEntry(
    BuildContext context,
    List<CareAccessDeviceMetric> availableDevices,
  ) {
    final hasDevices = availableDevices.isNotEmpty;
    final primaryMac = hasDevices ? availableDevices.first.deviceMac : null;

    return InkWell(
      onTap: hasDevices
          ? () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                barrierColor: Colors.black87,
                builder: (BuildContext context) => AiChatDialog(
                  deviceMac: primaryMac,
                  availableDevices: availableDevices,
                ),
              );
            }
          : null,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: hasDevices ? 1 : 0.72,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF875A).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFF875A),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '向守护助手提问',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasDevices
                          ? '支持围绕监测趋势、异常波动和家属跟进行动提问'
                          : '至少有一位老人绑定手环后，才能结合实时监测数据进行分析',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white24,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
