import 'package:flutter/material.dart';

import '../detector/detector_screen.dart';

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  bool _checkPassed = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'ROADEYE',
                    style: textTheme.labelLarge?.copyWith(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'A clearer view\nof the road.',
                    style: textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Road damage detection, powered by YOLO11.',
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF163D35),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RoadEye is running',
                          style: textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'The app has opened successfully. Tap below to '
                          'check that it responds.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFDFEBE5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD7EF9A),
                              foregroundColor: const Color(0xFF163D35),
                              minimumSize: const Size(48, 52),
                            ),
                            onPressed: () {
                              setState(() => _checkPassed = true);
                            },
                            child: const Text('Check app'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _checkPassed
                                ? 'App check passed'
                                : 'Ready for your first check',
                            key: const ValueKey('app-check-status'),
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFD7EF9A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFD7EF9A),
                              side: const BorderSide(color: Color(0xFFD7EF9A)),
                              minimumSize: const Size(48, 52),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const DetectorScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Start Live Detection'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Road Damage Detector', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Real-time YOLO11 damage detector active. Tap Start Live Detection to scan.',
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  Text('Made for the road ahead.', style: textTheme.bodySmall),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
