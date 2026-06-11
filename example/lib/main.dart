// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_guardian_example/src/app_controller.dart';
import 'package:webview_guardian_example/src/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GuardianExampleApp());
}

class GuardianExampleApp extends StatefulWidget {
  const GuardianExampleApp({super.key});

  @override
  State<GuardianExampleApp> createState() => _GuardianExampleAppState();
}

class _GuardianExampleAppState extends State<GuardianExampleApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    unawaited(_controller.init());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebView Guardian Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FEB)),
        useMaterial3: true,
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
