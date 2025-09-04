import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _otpFocusNode = FocusNode();

  String? _verificationId;
  bool _isLoading = false;
  bool _isOtpSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isOtpSent && mounted) {
        FocusScope.of(context).requestFocus(_phoneFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  // --- UPDATED: write both 'phone' and 'phoneNumber' (back/forward compatible)
  Future<void> _ensureUserDocumentExists(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    await userRef.set({
      'phone': user.phoneNumber,
      'phoneNumber': user.phoneNumber, // NEW
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'email': user.email,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
    }, SetOptions(merge: true));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.trim().isEmpty) {
      _showErrorSnackBar("Please enter your phone number.");
      return;
    }
    if (_phoneController.text.trim().length < 9 || _phoneController.text.trim().length > 10) {
      _showErrorSnackBar("Please enter a valid 9 or 10 digit phone number.");
      return;
    }

    final phoneNumber = "+94${_phoneController.text.trim()}";
    setState(() => _isLoading = true);

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        final userCred = await _auth.signInWithCredential(credential);
        if (userCred.user != null) {
          await _ensureUserDocumentExists(userCred.user!);
        }
        if (mounted) {
          _showSuccessSnackBar("Signed in automatically!");
          setState(() => _isLoading = false);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) {
          _showErrorSnackBar("Verification Failed: ${e.code}");
          setState(() => _isLoading = false);
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (mounted) {
          _showSuccessSnackBar("OTP sent to $phoneNumber!");
          setState(() {
            _verificationId = verificationId;
            _isOtpSent = true;
            _isLoading = false;
            FocusScope.of(context).requestFocus(_otpFocusNode);
          });
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // noop
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6 || _verificationId == null) {
      _showErrorSnackBar("Please enter the 6-digit code.");
      return;
    }
    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpController.text.trim(),
      );
      final userCred = await _auth.signInWithCredential(credential);
      if (userCred.user != null) {
        await _ensureUserDocumentExists(userCred.user!);
      }
      if (mounted) _showSuccessSnackBar("Successfully signed in!");
    } on FirebaseAuthException catch (e) {
      if (mounted) _showErrorSnackBar("Invalid OTP or error: ${e.code}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final primaryAction = _isOtpSent ? _verifyOtp : _sendOtp;
    final buttonText = _isOtpSent ? 'Verify & Sign In' : 'Send OTP';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/Gemini_Generated_Image',
                  height: 80,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.task_alt_rounded,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isOtpSent ? 'Enter Verification Code' : 'Welcome to Servana!',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(color: colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  _isOtpSent
                      ? 'A 6-digit code was sent to your phone.'
                      : 'Sign in or create an account with your phone number.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 48),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.0, 0.1), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _isOtpSent ? _buildOtpInputUI(theme, textTheme) : _buildPhoneInputUI(theme, textTheme),
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                    : ElevatedButton(onPressed: primaryAction, child: Text(buttonText)),
                const SizedBox(height: 16),
                if (_isOtpSent && !_isLoading)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isOtpSent = false;
                        _otpController.clear();
                        _phoneController.clear();
                        FocusScope.of(context).requestFocus(_phoneFocusNode);
                      });
                    },
                    child: const Text('Use a different number?'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneInputUI(ThemeData theme, TextTheme textTheme) {
    return Column(
      key: const ValueKey('phone-input'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '77 123 4567',
            labelText: 'Phone Number',
            prefixIcon: Icon(Icons.phone_android_rounded),
            prefixText: '+94 ',
          ),
          style: textTheme.bodyLarge,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Phone number cannot be empty.';
            if (value.trim().length < 9 || value.trim().length > 10) return 'Enter a valid 9 or 10 digit number.';
            return null;
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }

  Widget _buildOtpInputUI(ThemeData theme, TextTheme textTheme) {
    return Column(
      key: const ValueKey('otp-input'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _otpController,
          focusNode: _otpFocusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: textTheme.headlineMedium?.copyWith(letterSpacing: 10, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: '● ● ● ● ● ●',
            hintStyle: TextStyle(letterSpacing: 10, fontWeight: FontWeight.bold),
            counterText: "",
            labelText: 'OTP Code',
          ),
          validator: (value) {
            if (value == null || value.trim().length != 6) return 'Enter the 6-digit code.';
            return null;
          },
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }
}
