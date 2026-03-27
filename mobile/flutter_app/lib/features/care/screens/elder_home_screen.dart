import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../widgets/logout_action.dart';
import '../../agent/screens/elder_agent_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/care_profile_model.dart';
import '../providers/care_provider.dart';

class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({super.key});

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
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
    final authUser = context.watch<AuthProvider>().user;
    final profile = careProvider.profile;
    final metric = profile != null && profile.deviceMetrics.isNotEmpty
        ? profile.deviceMetrics.first
        : null;
    final elderName = metric?.subjectName ?? authUser?.name ?? '长者';

    return Scaffold(
      backgroundColor: const Color(0xFF08161B),
      appBar: AppBar(
        title: Text(
          '$elderName的健康守护',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: const [LogoutAction()],
      ),
      body: _buildBody(careProvider, elderName, metric),
    );
  }

  Widget _buildBody(
    CareProvider provider,
    String elderName,
    CareAccessDeviceMetric? metric,
  ) {
    if (provider.status == CareLoadStatus.loading && provider.profile == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF875A)),
      );
    }

    if (provider.status == CareLoadStatus.error && provider.profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              provider.errorMessage ?? '加载失败',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchProfile(),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
              child: const Text('重试', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      );
    }

    final profile = provider.profile;
    if (profile == null) return const SizedBox.shrink();

    final hasDevice =
        profile.boundDeviceMacs.isNotEmpty || profile.deviceMetrics.isNotEmpty;
    final deviceStatus = metric?.deviceStatus ?? 'unknown';
    final batteryLabel = metric?.battery != null ? '${metric!.battery}%' : '--';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(elderName),
            const SizedBox(height: 20),
            _buildDeviceStatusCard(
                metric, hasDevice, deviceStatus, batteryLabel),
            const SizedBox(height: 20),
            _buildRealtimeMetrics(metric),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildBigButton(
                    Icons.phone,
                    '联系家属',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildBigButton(
                    Icons.warning,
                    '一键求助',
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildBigButton(
              Icons.auto_awesome,
              '智能健康助手',
              const Color(0xFFFF875A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ElderAgentScreen(deviceMac: metric?.deviceMac),
                ),
              ),
            ),
            const SizedBox(height: 20),
            hasDevice
                ? _buildUnbindDeviceButton(provider)
                : _buildBindDeviceButton(provider),
            const SizedBox(height: 24),
            _buildInfoCard(
              profile.basicAdvice.isNotEmpty
                  ? profile.basicAdvice
                  : hasDevice
                      ? '当前账号已绑定到有效设备链路，可查看设备指标、评估结果和健康报告摘要。'
                      : '请先登记并绑定手环，绑定成功后就能在这里看到实时指标和提醒。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String elderName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            elderName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusCard(
    CareAccessDeviceMetric? metric,
    bool hasDevice,
    String status,
    String battery,
  ) {
    final normalizedStatus = status.toLowerCase();
    final isOnline =
        normalizedStatus == 'online' || normalizedStatus == 'normal';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasDevice
              ? (isOnline
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.orange.withValues(alpha: 0.5))
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            hasDevice ? Icons.watch : Icons.watch_off,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            hasDevice ? '设备已连接' : '设备未连接',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (metric != null) ...[
            const SizedBox(height: 8),
            Text(
              '${metric.deviceName} · ${metric.deviceMac}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '登记并绑定手环后，实时数据会自动同步到当前账号。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
          const SizedBox(height: 12),
          if (hasDevice)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.battery_full,
                    color: Colors.greenAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  '电量: $battery',
                  style: const TextStyle(color: Colors.white70, fontSize: 22),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRealtimeMetrics(CareAccessDeviceMetric? metric) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildMetricCard(
          '心率',
          _formatDouble(metric?.heartRate),
          'bpm',
          Icons.favorite,
        ),
        _buildMetricCard(
          '血压',
          metric?.bloodPressure ?? '--',
          'mmHg',
          Icons.bloodtype,
        ),
        _buildMetricCard(
          '血氧',
          _formatDouble(metric?.bloodOxygen),
          '%',
          Icons.water_drop,
        ),
        _buildMetricCard(
          '体温',
          _formatDouble(metric?.temperature, fractionDigits: 1),
          '°C',
          Icons.thermostat,
        ),
        _buildMetricCard(
          '步数',
          metric?.steps?.toString() ?? '--',
          '步',
          Icons.directions_walk,
        ),
        _buildMetricCard(
          '健康度',
          metric?.healthScore?.toString() ?? '--',
          '分',
          Icons.monitor_heart,
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    String unit,
    IconData icon,
  ) {
    return Container(
      width: (MediaQuery.of(context).size.width - 60) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFFFF875A), size: 36),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 22),
          ),
          const SizedBox(height: 6),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(color: Colors.white38, fontSize: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBindDeviceButton(CareProvider provider) {
    return OutlinedButton.icon(
      onPressed:
          provider.isMutating ? null : () => _showBindDeviceDialog(provider),
      icon: provider.isMutating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.watch, size: 28, color: Colors.lightBlueAccent),
      label: Text(
        provider.isMutating ? '处理中...' : '登记并绑定手环设备',
        style: const TextStyle(
          fontSize: 22,
          color: Colors.lightBlueAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
        side: const BorderSide(color: Colors.lightBlueAccent, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildUnbindDeviceButton(CareProvider provider) {
    return OutlinedButton.icon(
      onPressed: provider.isMutating
          ? null
          : () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: const Color(0xFF0D1A22),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                        color: Colors.orangeAccent, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    '解绑手环设备',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  content: const Text(
                    '确认解绑后，这只手环会与当前账号解除绑定，实时健康数据将停止同步。之后如需重新使用，可再次登记绑定。',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      height: 1.6,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Colors.white54, fontSize: 18),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text(
                        '确认解绑',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;

              final success = await provider.unbindSelfDevice();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? '手环已成功解绑'
                        : (provider.errorMessage ?? '解绑失败，请稍后重试'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  backgroundColor:
                      success ? Colors.green.shade700 : Colors.red.shade700,
                ),
              );
            },
      icon: provider.isMutating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link_off, size: 28, color: Colors.orangeAccent),
      label: Text(
        provider.isMutating ? '处理中...' : '解绑手环设备',
        style: const TextStyle(
          fontSize: 22,
          color: Colors.orangeAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
        side: const BorderSide(color: Colors.orangeAccent, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildBigButton(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap ??
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('正在尝试$label...')),
            );
          },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.2),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String basicAdvice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '今日提示',
            style: TextStyle(color: Colors.white54, fontSize: 28),
          ),
          const SizedBox(height: 12),
          Text(
            basicAdvice,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBindDeviceDialog(CareProvider provider) async {
    final macController = TextEditingController();
    final nameController = TextEditingController(text: 'T10-WATCH');
    final result = await showDialog<_BindDeviceResult>(
      context: context,
      builder: (dialogContext) {
        String? localError;
        return StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            backgroundColor: const Color(0xFF0D1A22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.lightBlueAccent, width: 1.2),
            ),
            title: const Text(
              '登记并绑定手环',
              style: TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDialogField(
                    controller: macController,
                    label: '手环 MAC 地址',
                    hintText: '例如 54:10:26:01:00:DF',
                  ),
                  const SizedBox(height: 12),
                  _buildDialogField(
                    controller: nameController,
                    label: '设备名称',
                    hintText: '默认 T10-WATCH',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支持输入 12 位十六进制 MAC，系统会自动格式化。',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      localError!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 16),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white54, fontSize: 18),
                ),
              ),
              TextButton(
                onPressed: () {
                  final normalizedMac = _normalizeMacInput(macController.text);
                  if (!_isValidMac(normalizedMac)) {
                    setState(() {
                      localError = '请输入正确的手环 MAC 地址';
                    });
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    _BindDeviceResult(
                      macAddress: normalizedMac,
                      deviceName: nameController.text.trim(),
                    ),
                  );
                },
                child: const Text(
                  '确认绑定',
                  style: TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    macController.dispose();
    nameController.dispose();

    if (result == null) return;

    final success = await provider.bindSelfDevice(
      result.macAddress,
      deviceName: result.deviceName,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? '手环已成功登记并绑定' : (provider.errorMessage ?? '绑定手环失败，请稍后重试'),
          style: const TextStyle(fontSize: 18),
        ),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.lightBlueAccent),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDouble(double? value, {int fractionDigits = 0}) {
    if (value == null) return '--';
    return value.toStringAsFixed(fractionDigits);
  }

  String _normalizeMacInput(String rawValue) {
    final compact =
        rawValue.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (compact.length != 12) {
      return rawValue.trim().toUpperCase();
    }
    final parts = <String>[];
    for (var index = 0; index < compact.length; index += 2) {
      parts.add(compact.substring(index, index + 2));
    }
    return parts.join(':');
  }

  bool _isValidMac(String value) {
    final compact = value.replaceAll(':', '');
    return RegExp(r'^[0-9A-F]{12}$').hasMatch(compact);
  }
}

class _BindDeviceResult {
  final String macAddress;
  final String? deviceName;

  const _BindDeviceResult({
    required this.macAddress,
    required this.deviceName,
  });
}
