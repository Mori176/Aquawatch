import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import 'home_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _operatorIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _dbService = DatabaseService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _agreeProtocols = false;

  @override
  void dispose() {
    _nameController.dispose();
    _operatorIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    final operatorId = _operatorIdController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || operatorId.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      _showSnack('Password must be at least 6 characters.');
      return;
    }
    if (!_agreeProtocols) {
      _showSnack('You must agree to the System Protocols.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = await _authService.register(email, password);
      final uid = credential.user?.uid;
      if (uid != null) {
        await _dbService.saveUserProfile(
          uid: uid,
          name: name,
          operatorId: operatorId,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'email-already-in-use' => 'An account already exists for this email.',
        'invalid-email' => 'Invalid email format.',
        'weak-password' => 'Password is too weak.',
        'operation-not-allowed' =>
          'Email/password sign-up is disabled. Contact the admin.',
        _ => 'Registration failed: ${e.message}',
      };
      _showSnack(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Register',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Create your operator account',
                style: TextStyle(color: AppColors.greyText, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'NAME',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _operatorIdController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'OPERATOR ID',
                  hintText: 'OP-XXXX-XXXX',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'EMAIL ADDRESS',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createAccount(),
                decoration: InputDecoration(
                  labelText: 'PASSWORD',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Password must be at least 6 characters and include a '
                'mix of letters and numbers.',
                style: TextStyle(fontSize: 12, color: AppColors.greyText),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreeProtocols,
                      onChanged: (v) =>
                          setState(() => _agreeProtocols = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'I agree to the System Protocols and accept full '
                      'responsibility for my logged actions.',
                      style: TextStyle(fontSize: 13, color: AppColors.greyText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _createAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.googleGreen,
                      ),
                      icon: const Icon(Icons.person_add_alt_1, size: 20),
                      label: const Text('CREATE ACCOUNT'),
                    ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already registered?',
                    style:
                        TextStyle(color: AppColors.greyText, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Operator Login',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
