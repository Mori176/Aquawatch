import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_shell.dart';
import 'login.dart';

/// Decides the first screen on launch: resume a remembered session
/// (within the 24-hour window) or show the login screen.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final auth = AuthService();
    final canResume = await auth.canResumeSession();
    if (!mounted) return;

    if (canResume) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } else {
      // No valid remembered session — clear any stale login and ask again.
      await auth.signOut();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/AquaManager.png', height: 96, width: 96),
            const SizedBox(height: 24),
            const CircularProgressIndicator(strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
