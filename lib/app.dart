import 'package:flutter/material.dart';

import 'features/launch/launch_screen.dart';

class RoadEyeApp extends StatelessWidget {
  const RoadEyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadEye',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF234E45)),
        scaffoldBackgroundColor: const Color(0xFFF5F6F2),
      ),
      home: const LaunchScreen(),
    );
  }
}
