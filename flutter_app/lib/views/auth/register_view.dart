import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../main_nav_view.dart';
import 'otp_verification_view.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  // Current Step: 0 = Account Info, 1 = Research Interests Setup
  int _currentStep = 0;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _institutionController = TextEditingController();
  final _customDomainController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _selectedDomain = 'Machine Learning';

  final List<String> _suggestedDomains = [
    'Machine Learning',
    'Computer Vision',
    'Natural Language Processing',
    'Cybersecurity',
    'Data Science',
    'Bioinformatics',
    'Quantum Computing',
    'Robotics & AI',
    'Graph Neural Networks',
  ];

  final PaperGraphApiClient _apiClient = PaperGraphApiClient();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _institutionController.dispose();
    _customDomainController.dispose();
    super.dispose();
  }

  double _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0.0;
    double strength = 0.0;
    if (password.length >= 6) strength += 0.3;
    if (password.length >= 8) strength += 0.3;
    if (RegExp(r'[A-Z]').hasMatch(password)) strength += 0.2;
    if (RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      strength += 0.2;
    }
    return strength.clamp(0.0, 1.0);
  }

  Color _getStrengthColor(double strength) {
    if (strength <= 0.3) return AppTheme.accentRose;
    if (strength <= 0.6) return AppTheme.accentAmber;
    return AppTheme.accentEmerald;
  }

  String _getStrengthLabel(double strength) {
    if (strength <= 0.3) return 'Weak';
    if (strength <= 0.6) return 'Moderate';
    return 'Strong';
  }

  void _onProceedToOtp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 1. Verify if email already exists before dispatching OTP
    try {
      final exists = await authProvider.isEmailRegistered(email).timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      if (exists) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This email is already registered. Please sign in or reset your password.'),
            backgroundColor: AppTheme.accentRose,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    } catch (_) {
      // If check encounters an issue or times out, continue flow safely
    }

    try {
      await _apiClient.sendOtp(email).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const ApiException(
          'Connection timed out while sending verification code. Please check your internet connection or server status.',
        ),
      );
      if (!mounted) return;

      setState(() => _isLoading = false);

      // Navigate to OTP Verification View
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationView(
            email: _emailController.text.trim(),
            onVerified: () {
              Navigator.pop(context); // Close OTP screen
              setState(() {
                _currentStep = 1; // Advance to Step 2: Research Interests
              });
            },
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending code: $e'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  void _onFinalRegister() async {
    final domain = _customDomainController.text.trim().isNotEmpty
        ? _customDomainController.text.trim()
        : (_selectedDomain ?? 'General Computer Science');

    final institution = _institutionController.text.trim().isNotEmpty
        ? _institutionController.text.trim()
        : 'Academic Researcher';

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      institution: institution,
      researchField: domain,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      // Reset guest search count upon becoming a verified member
      await HiveService.resetGuestSearchCount();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Welcome to PaperGraph. Your profile is ready.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentEmerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationView()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Registration failed'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentStep == 0 ? 'Create Researcher Profile' : 'Research Interests'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _currentStep == 0
              ? _buildStepOneForm(isDark)
              : _buildStepTwoInterests(isDark, authProvider),
        ),
      ),
    );
  }

  Widget _buildStepOneForm(bool isDark) {
    final password = _passwordController.text;
    final strength = _calculatePasswordStrength(password);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Badge
          Text(
            'Join the Research Network',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Step 1 of 2: Enter your credentials to receive a verification code.',
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // Full Name
          _buildFieldLabel('Full Name & Academic Title', isDark),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'e.g. Dr. Alex Morgan',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 18),

          // Academic Email
          _buildFieldLabel('Academic / Work Email', isDark),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'name@institution.edu',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Email is required';
              }
              if (!val.contains('@') || !val.contains('.')) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          // Password Field
          _buildFieldLabel('Password', isDark),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'At least 6 characters',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (val) =>
                val != null && val.length < 6 ? 'Password must be at least 6 characters' : null,
          ),

          // Password Strength Bar
          if (password.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: strength,
                      backgroundColor: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor(strength)),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _getStrengthLabel(strength),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: _getStrengthColor(strength),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),

          // Confirm Password Field
          _buildFieldLabel('Confirm Password', isDark),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              prefixIcon: const Icon(Icons.lock_clock_outlined, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Please confirm your password';
              }
              if (val != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 30),

          // Submit Step 1 Button
          ElevatedButton(
            onPressed: _isLoading ? null : _onProceedToOtp,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: isDark ? Colors.white : const Color(0xFF18181B),
              foregroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: isDark ? const Color(0xFF09090B) : Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Send OTP Verification Code',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 20),

          // Already have account
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF18181B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepTwoInterests(bool isDark, AuthProvider authProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Verified Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.accentEmerald.withAlpha(25),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentEmerald.withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_rounded, color: AppTheme.accentEmerald, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Email Verified: ${_emailController.text}',
                  style: const TextStyle(
                    color: AppTheme.accentEmerald,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Personalize Your Research Profile',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Step 2 of 2: Select your domains of interest to tailor your connected graphs.',
          style: TextStyle(
            fontSize: 13.5,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // Affiliation
        _buildFieldLabel('Affiliation / University (Optional)', isDark),
        TextFormField(
          controller: _institutionController,
          decoration: const InputDecoration(
            hintText: 'e.g. University / Research Center',
            prefixIcon: Icon(Icons.school_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 24),

        // Primary Research Domain Chips
        _buildFieldLabel('Primary Research Domain', isDark),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _suggestedDomains.map((domain) {
            final isSelected = _selectedDomain == domain && _customDomainController.text.isEmpty;
            return ChoiceChip(
              label: Text(domain),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedDomain = selected ? domain : null;
                  _customDomainController.clear();
                });
              },
              selectedColor: isDark ? const Color(0xFF242426) : const Color(0xFF18181B),
              backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              ),
              side: BorderSide(
                color: isSelected
                    ? (isDark ? const Color(0x40FFFFFF) : const Color(0xFF18181B))
                    : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Custom domain input
        TextFormField(
          controller: _customDomainController,
          onChanged: (val) {
            if (val.isNotEmpty) {
              setState(() => _selectedDomain = null);
            }
          },
          decoration: const InputDecoration(
            hintText: 'Or enter custom domain (e.g. Neuroscience)',
            prefixIcon: Icon(Icons.science_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 32),

        // Launch Button
        ElevatedButton(
          onPressed: authProvider.isLoading ? null : _onFinalRegister,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: isDark ? Colors.white : const Color(0xFF18181B),
            foregroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: authProvider.isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: isDark ? const Color(0xFF09090B) : Colors.white,
                  ),
                )
              : const Text(
                  'Complete & Launch PaperGraph',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFieldLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
      ),
    );
  }
}
