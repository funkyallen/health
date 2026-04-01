import 'package:flutter/material.dart';

import 'simple_omni_7b_test_page.dart';

class ElderVoiceScreen extends StatelessWidget {
  final String? deviceMac;

  const ElderVoiceScreen({super.key, this.deviceMac});

  @override
  Widget build(BuildContext context) {
    return const SimpleOmni7bTestPage();
  }
}
