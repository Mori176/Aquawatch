import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles Firebase Auth plus the "remember this terminal for 24 hours"
/// behaviour controlled by the login checkbox.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _kRememberUntil = 'remember_until_ms';
  static const Duration _rememberWindow = Duration(hours: 24);

  Stream<User?> get userStream => _auth.authStateChanges();

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  Future<UserCredential> register(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Called after a successful sign-in. If [remember] is true, the session
  /// may be resumed for the next 24 hours even after the app is killed.
  /// If false, the next launch will require a fresh login.
  Future<void> rememberSession({required bool remember}) async {
    final prefs = await SharedPreferences.getInstance();
    final until = remember
        ? DateTime.now().add(_rememberWindow).millisecondsSinceEpoch
        : 0;
    await prefs.setInt(_kRememberUntil, until);
  }

  /// True when a signed-in user exists AND the 24-hour window is still open.
  Future<bool> canResumeSession() async {
    if (_auth.currentUser == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kRememberUntil) ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRememberUntil);
    await _auth.signOut();
  }
}
