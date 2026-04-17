import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_button.dart';

/// JoinGroupScreen allows users to join an existing group using a 6-digit code.
/// 
/// User Flow:
/// 1. Enter 6-digit code (one digit at a time)
/// 2. Code auto-validates when complete
/// 3. Success: Navigate back (group appears in list)
/// 4. Error: Show message, allow retry
/// 
/// Design Decisions:
/// - 6 separate input boxes for clear visual feedback
/// - Auto-advance to next box after each digit
/// - Auto-submit when all 6 digits entered
/// - Paste support for copying code from messages
class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  /// Controllers for each digit input.
  /// 
  /// Why 6 separate controllers?
  /// - Each box is independent TextField
  /// - Can access/modify each digit separately
  /// - Required for the "one box per digit" UI pattern
  late List<TextEditingController> _controllers;
  
  /// Focus nodes to control which box is active.
  /// 
  /// Why FocusNode?
  /// - Programmatically move focus between boxes
  /// - Auto-advance: digit entered → focus next box
  /// - Backspace: focus previous box
  late List<FocusNode> _focusNodes;
  
  /// Track if we're currently joining (for loading state).
  bool _isJoining = false;
  
  /// Error message to display.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());
    for (int i = 0; i < 6; i++) {
      final index = i;
      _focusNodes[index].onKeyEvent = (node, event) {
        _onKeyEvent(index, event);
        return KeyEventResult.ignored;
      };
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    // IMPORTANT: Dispose all controllers and focus nodes
    // Each one holds resources that must be freed
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Gets the complete 6-digit code from all controllers.
  String get _fullCode {
    return _controllers.map((c) => c.text).join();
  }

  /// Checks if all 6 digits have been entered.
  bool get _isCodeComplete {
    return _fullCode.length == 6;
  }

  /// Handles input change for a specific digit box.
  /// 
  /// Logic:
  /// 1. If digit entered → move to next box
  /// 2. If all 6 digits → auto-submit
  /// 3. Handle paste (user pastes full code)
  void _onDigitChanged(int index, String value) {
    // Clear any previous error when user types
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }

    // Handle paste: user pastes full code into first box
    if (value.length > 1) {
      _handlePaste(value);
      return;
    }

    // Single digit entered → move to next box
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    // Check if code is complete
    if (_isCodeComplete) {
      // Small delay to show the last digit before validating
      Future.delayed(const Duration(milliseconds: 100), () {
        _handleJoinGroup();
      });
    }

    setState(() {});  // Update UI (button state, etc.)
  }

  /// Handles backspace key press.
  /// 
  /// Why special handling?
  /// - When box is empty and backspace pressed → go to previous box
  /// - Better UX for correcting mistakes
  void _onKeyEvent(int index, KeyEvent event) {
    // Check for backspace on empty field
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      // Move to previous box and clear it
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
    }
  }

  /// Handles paste operation.
  /// 
  /// When user pastes a code:
  /// 1. Extract only digits
  /// 2. Fill boxes left to right
  /// 3. Auto-submit if 6 digits pasted
  void _handlePaste(String pastedText) {
    // Extract only digits from pasted text
    final digits = pastedText.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Fill each box with corresponding digit
    for (int i = 0; i < 6; i++) {
      if (i < digits.length) {
        _controllers[i].text = digits[i];
      } else {
        _controllers[i].clear();
      }
    }

    // Focus appropriate box
    if (digits.length >= 6) {
      // All filled → unfocus (hide keyboard briefly before submit)
      FocusScope.of(context).unfocus();
      // Auto-submit
      Future.delayed(const Duration(milliseconds: 100), () {
        _handleJoinGroup();
      });
    } else if (digits.length < 6) {
      // Focus next empty box
      _focusNodes[digits.length].requestFocus();
    }

    setState(() {});
  }

  /// Clears all input boxes.
  void _clearCode() {
    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
    setState(() {
      _errorMessage = null;
    });
  }

  /// Handles the join group operation.
  Future<void> _handleJoinGroup() async {
    if (!_isCodeComplete || _isJoining) return;

    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });

    // Get current user ID
    final userId = context.read<AuthProvider>().firebaseUser?.uid;
    
    if (userId == null) {
      setState(() {
        _isJoining = false;
        _errorMessage = 'Error: Not logged in';
      });
      return;
    }

    // Attempt to join
    final result = await context.read<GroupProvider>().joinGroup(
      code: _fullCode,
      userId: userId,
    );

    if (!mounted) return;

    setState(() {
      _isJoining = false;
    });

    if (result.group != null) {
      Navigator.pop(context, result.group!.groupName);
    } else {
      // Error - show message and let user retry
      setState(() {
        _errorMessage = result.error ?? 'Failed to join group';
      });
      // Clear the code for retry
      _clearCode();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Join Group'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header illustration
              Container(
                padding: const EdgeInsets.all(AppConstants.largePadding),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.group,
                      size: 64,
                      color: AppConstants.primaryColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Join a Group',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-digit code shared by the group creator.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Code input label
              const Text(
                'Enter Group Code',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // 6-digit code input boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return _buildDigitBox(index);
                }),
              ),
              const SizedBox(height: 24),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppConstants.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                    border: Border.all(
                      color: AppConstants.errorColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppConstants.errorColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppConstants.errorColor),
                        ),
                      ),
                    ],
                  ),
                ),

              // Loading indicator or join button
              if (_isJoining)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        color: AppConstants.primaryColor,
                      ),
                      SizedBox(height: 16),
                      Text('Joining group...'),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    // Join button (backup if auto-submit doesn't trigger)
                    CustomButton(
                      text: 'Join Group',
                      onPressed: _isCodeComplete ? _handleJoinGroup : null,
                      icon: Icons.login,
                    ),
                    const SizedBox(height: 16),
                    
                    // Clear button
                    if (_fullCode.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clearCode,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Clear Code'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 32),

              // Help text
              Container(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'How to get a code?',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask the group creator to share their 6-digit code with you. They can find it in the group settings.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a single digit input box.
  /// 
  /// Design:
  /// - Square box with border
  /// - Large centered digit
  /// - Changes color when focused
  /// - Only accepts single digit
  Widget _buildDigitBox(int index) {
    final bool hasValue = _controllers[index].text.isNotEmpty;
    final bool isFocused = _focusNodes[index].hasFocus;

    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6,  // Allow paste of full code
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            counterText: '',  // Hide character counter
            filled: true,
            fillColor: hasValue
                ? AppConstants.primaryColor.withOpacity(0.1)
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: BorderSide(
                color: isFocused
                    ? AppConstants.primaryColor
                    : Colors.grey[300]!,
                width: isFocused ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: BorderSide(
                color: hasValue
                    ? AppConstants.primaryColor.withOpacity(0.5)
                    : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              borderSide: const BorderSide(
                color: AppConstants.primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,  // Only allow digits
          ],
          onChanged: (value) => _onDigitChanged(index, value),
        ),
    );
  }
}
