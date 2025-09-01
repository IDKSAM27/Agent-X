import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/profession_input_screen.dart';
import '../core/constants/app_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isEmailValid = false;

  late AnimationController _heroAnimationController;
  late AnimationController _formAnimationController;
  late AnimationController _loadingController;

  @override
  void initState() {
    super.initState();

    _heroAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _formAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _loadingController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Start animations
    _heroAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _formAnimationController.forward();
    });

    // Email validation listener
    _emailController.addListener(_validateEmail);
  }

  void _validateEmail() {
    final email = _emailController.text.trim();
    final isValid = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
    if (isValid != _isEmailValid) {
      setState(() => _isEmailValid = isValid);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _heroAnimationController.dispose();
    _formAnimationController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: AppConstants.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppConstants.spacingXXL),

                // Hero Section
                _buildHeroSection(),

                const SizedBox(height: AppConstants.spacingXXL),

                // Form Section
                _buildFormSection(),

                const SizedBox(height: AppConstants.spacingL),

                // Social Sign In
                _buildSocialSignIn(),

                const SizedBox(height: AppConstants.spacingXL),

                // Sign Up Link
                _buildSignUpLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: [
        // Agent-X Logo with the animation intact
        AnimatedBuilder(
          animation: _heroAnimationController,
          builder: (context, child) {
            return Transform.scale(
              scale: Tween<double>(begin: 0.0, end: 1.0)
                  .animate(CurvedAnimation(
                parent: _heroAnimationController,
                curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
              ))
                  .value,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to the original icon if image fails to load
                      return Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(context).colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                        ),
                        child: const Icon(
                          Icons.smart_toy_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        )

            .animate(delay: 200.ms)
            .shimmer(duration: 1000.ms)
            .then()
            .shake(hz: 4, curve: Curves.easeInOutCubic),

        const SizedBox(height: AppConstants.spacingL),

        // Title and Subtitle
        Text(
          'Welcome to AgentX',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        )
            .animate(delay: 400.ms)
            .fadeIn(duration: 600.ms)
            .slideY(begin: 0.3, end: 0),

        const SizedBox(height: AppConstants.spacingS),

        Text(
          'Sign in to continue',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        )
            .animate(delay: 600.ms)
            .fadeIn(duration: 600.ms)
            .slideY(begin: 0.3, end: 0),
      ],
    );
  }

  Widget _buildFormSection() {
    return AnimatedBuilder(
      animation: _formAnimationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            0,
            30 * (1 - _formAnimationController.value),
          ),
          child: Opacity(
            opacity: _formAnimationController.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Email Field
                _buildEmailField(),

                const SizedBox(height: AppConstants.spacingM),

                // Password Field
                _buildPasswordField(),

                const SizedBox(height: AppConstants.spacingL),

                // Sign In Button
                _buildSignInButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      focusNode: _emailFocusNode,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Email',
        hintText: 'Enter your email address',
        prefixIcon: Icon(
          Icons.email_outlined,
          color: _isEmailValid
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        suffixIcon: _isEmailValid
            ? Icon(
          Icons.check_circle,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        )
            : null,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your email address';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
          return 'Please enter a valid email address';
        }
        return null;
      },
      onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: 'Enter your password',
        prefixIcon: const Icon(Icons.lock_outlined),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          splashRadius: 20,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your password';
        }
        if (value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
      onFieldSubmitted: (_) => _signInWithEmail(),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signInWithEmail,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          disabledBackgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.12),
          elevation: _isLoading ? 0 : 2,
          shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
        child: _isLoading
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            const Text('Signing in...'),
          ],
        )
            : const Text('Sign In'),
      ),
    );
  }

  Widget _buildSocialSignIn() {
    return Column(
      children: [
        // Divider with "or"
        Row(
          children: [
            Expanded(
              child: Divider(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
              child: Text(
                'or',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Divider(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
            ),
          ],
        ),

        const SizedBox(height: AppConstants.spacingL),

        // Google Sign In Button
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _signInWithGoogle,
            icon: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              ),
              child: Image.network(
                'https://developers.google.com/identity/images/g-logo.png',
                width: 18,
                height: 18,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.g_mobiledata_rounded,
                  size: 20,
                ),
              ),
            ),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ],
    ).animate(delay: 800.ms).fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildSignUpLink() {
    return TextButton(
      onPressed: _isLoading ? null : () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const SignUpScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: animation.drive(
                  Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeInOutCubic)),
                ),
                child: child,
              );
            },
            transitionDuration: AppConstants.normalAnimation,
          ),
        );
      },
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          text: "Don't have an account? ",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(
              text: 'Sign up',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: 1000.ms).fadeIn(duration: 600.ms);
  }

  // Authentication methods with enhanced error handling
  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    _loadingController.repeat();

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        await _navigateToHome();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showErrorSnackBar(_getFirebaseErrorMessage(e.code));
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _loadingController.stop();
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    _loadingController.repeat();

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        _loadingController.stop();
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        await _navigateToHome();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _loadingController.stop();
      }
    }
  }

  String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onError,
              size: 20,
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        margin: AppConstants.paddingM,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _navigateToHome() async {
    // Show success message
    _showSuccessSnackBar('Welcome back!');

    // The AuthGate will automatically handle navigation
    // based on auth state changes, so we don't need to navigate manually
  }

}
