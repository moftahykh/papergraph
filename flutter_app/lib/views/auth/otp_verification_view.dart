import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

class OtpVerificationView extends StatefulWidget {
  final String email;
  final VoidCallback onVerified;

  const OtpVerificationView({
    super.key,
    required this.email,
    required this.onVerified,
  });

  @override
  State<OtpVerificationView> createState() => _OtpVerificationViewState();
}

class _OtpVerificationViewState extends State<OtpVerificationView> {
  final List<TextEditingController> _digitControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  final PaperGraphApiClient _apiClient = PaperGraphApiClient();
  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _digitControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otpCode => _digitControllers.map((c) => c.text).join();

  void _onDigitChanged(String val, int index) {
    if (val.isNotEmpty) {
      if (val.length > 1) {
        // Handle pasting multiple digits
        final chars = val.trim().split('');
        for (int i = 0; i < chars.length && (index + i) < 6; i++) {
          _digitControllers[index + i].text = chars[i];
        }
        final nextIndex = (index + chars.length).clamp(0, 5);
        _focusNodes[nextIndex].requestFocus();
        return;
      }

      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_otpCode.length == 6) {
          _submitVerification();
        }
      }
    }
  }

  Future<void> _submitVerification() async {
    final code = _otpCode.trim();
    if (code.length < 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiClient.verifyOtp(widget.email, code);
      if (!mounted) return;

      if (res['success'] == true) {
        widget.onVerified();
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Verification failed';
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Verification failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _resendCode() async {
    if (_secondsRemaining > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      await _apiClient.sendOtp(widget.email);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new 6-digit code has been sent to your email.'),
          backgroundColor: AppTheme.accentEmerald,
        ),
      );
      _startCountdown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not resend code: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email'), elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Email badge
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? AppTheme.darkSurface
                        : AppTheme.lightSurface,
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorder
                          : AppTheme.lightBorder,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.mark_email_read_rounded,
                    color: isDark ? Colors.white : const Color(0xFF18181B),
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Enter 6-Digit Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent an authentication code to your inbox at:\n${widget.email}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // 6-Pin Input Boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) => _buildPinBox(index, isDark),
                ),
              ),
              const SizedBox(height: 20),

              // Error Message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentRose.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accentRose.withAlpha(80),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppTheme.accentRose,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.accentRose,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Verify Button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitVerification,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: isDark
                      ? Colors.white
                      : const Color(0xFF18181B),
                  foregroundColor: isDark
                      ? const Color(0xFF09090B)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: isDark
                              ? const Color(0xFF09090B)
                              : Colors.white,
                        ),
                      )
                    : const Text(
                        'Verify & Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),

              // Resend Section
              Center(
                child: _secondsRemaining > 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 17,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Resend code in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: _isResending ? null : _resendCode,
                        icon: _isResending
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF18181B),
                                ),
                              )
                            : Icon(
                                Icons.refresh_rounded,
                                size: 18,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF18181B),
                              ),
                        label: Text(
                          'Resend Code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF18181B),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinBox(int index, bool isDark) {
    return SizedBox(
      width: 46,
      height: 54,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _digitControllers[index].text.isEmpty &&
              index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
        child: TextFormField(
          controller: _digitControllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: isDark ? AppTheme.darkSurface : const Color(0xFFF1F5F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white : const Color(0xFF18181B),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (val) => _onDigitChanged(val, index),
        ),
      ),
    );
  }
}
