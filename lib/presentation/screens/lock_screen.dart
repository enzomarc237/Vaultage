import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

class LockScreen extends StatefulWidget {
  final int attemptsRemaining;
  final Duration? lockoutDuration;
  final Function(String) onUnlock;

  const LockScreen({
    super.key,
    required this.attemptsRemaining,
    this.lockoutDuration,
    required this.onUnlock,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  final List<String> _pinDigits = [];
  bool _isError = false;
  bool _showRecovery = false;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_onPinChanged);
  }

  void _onPinChanged() {
    // Sync pin digits with controller
    final text = _pinController.text;
    if (text.length != _pinDigits.length) {
      setState(() {
        _pinDigits.clear();
        _pinDigits.addAll(text.split(''));
      });
    }
  }

  void _addDigit(String digit) {
    if (_pinDigits.length < 12) {
      setState(() {
        _pinDigits.add(digit);
        _pinController.text = _pinDigits.join();
        _isError = false;
      });
      
      // Auto-submit if we have 6+ digits
      if (_pinDigits.length >= 6) {
        _submitPin();
      }
    }
  }

  void _removeDigit() {
    if (_pinDigits.isNotEmpty) {
      setState(() {
        _pinDigits.removeLast();
        _pinController.text = _pinDigits.join();
        _isError = false;
      });
    }
  }

  void _submitPin() {
    if (_pinDigits.length >= 4) {
      widget.onUnlock(_pinDigits.join());
    }
  }

  void _clearPin() {
    setState(() {
      _pinDigits.clear();
      _pinController.clear();
      _isError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isInLockout = widget.lockoutDuration != null;
    
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Lock Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _isError
                          ? const Color.fromRGBO(255, 59, 48, 0.1)
                          : const Color.fromRGBO(0, 122, 255, 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: MacosIcon(
                          _isError
                            ? CupertinoIcons.exclamationmark_shield_fill
                            : CupertinoIcons.lock_fill,
                          size: 40,
                          color: _isError
                            ? MacosColors.systemRedColor
                            : MacosColors.systemBlueColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Title
                    Text(
                      _showRecovery ? 'Recovery Key' : 'Secure Vault',
                      style: MacosTheme.of(context).typography.title1,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    
                    // Subtitle
                    Text(
                      _showRecovery
                        ? 'Enter your 12-word recovery key'
                        : 'Enter your PIN to unlock',
                      style: MacosTheme.of(context).typography.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    
                    // PIN Display / Lockout Message
                    if (isInLockout)
                      _buildLockoutMessage()
                    else if (_showRecovery)
                      _buildRecoveryInput()
                    else
                      _buildPinDisplay(),
                    
                    const SizedBox(height: 32),
                    
                    // Keypad (only show if not in lockout)
                    if (!isInLockout && !_showRecovery)
                      _buildKeypad(),
                    
                    if (_showRecovery)
                      PushButton(
                        controlSize: ControlSize.large,
                        onPressed: () {
                          // Submit recovery key
                        },
                        child: const Text('Submit Recovery Key'),
                      ),
                    
                    const SizedBox(height: 16),
                    
                    // Attempts remaining
                    if (!isInLockout && !_showRecovery && widget.attemptsRemaining < 10)
                      Text(
                        '${widget.attemptsRemaining} attempts remaining',
                        style: MacosTheme.of(context).typography.caption1.copyWith(
                          color: widget.attemptsRemaining <= 3
                            ? MacosColors.systemRedColor
                            : MacosColors.systemOrangeColor,
                        ),
                      ),
                    
                    // Recovery key link
                    if (!isInLockout && !_showRecovery)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showRecovery = true;
                          });
                        },
                        child: Text(
                          'Forgot PIN? Use Recovery Key',
                          style: TextStyle(
                            fontSize: 12,
                            color: MacosColors.systemBlueColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    
                    if (_showRecovery)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showRecovery = false;
                          });
                        },
                        child: Text(
                          'Back to PIN',
                          style: TextStyle(
                            fontSize: 12,
                            color: MacosColors.systemBlueColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPinDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isError
          ? const Color.fromRGBO(255, 59, 48, 0.1)
          : const Color.fromRGBO(128, 128, 128, 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isError
            ? const Color.fromRGBO(255, 59, 48, 0.5)
            : const Color.fromRGBO(128, 128, 128, 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(6, (index) {
          final isFilled = index < _pinDigits.length;
          return Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled
                ? (_isError ? MacosColors.systemRedColor : MacosColors.systemBlueColor)
                : const Color.fromRGBO(128, 128, 128, 0.3),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLockoutMessage() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 149, 0, 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color.fromRGBO(255, 149, 0, 0.5),
        ),
      ),
      child: Column(
        children: [
          const MacosIcon(
            CupertinoIcons.clock_fill,
            size: 32,
            color: MacosColors.systemOrangeColor,
          ),
          const SizedBox(height: 12),
          Text(
            'Too many failed attempts',
            style: MacosTheme.of(context).typography.headline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait ${widget.lockoutDuration!.inSeconds} seconds before trying again.',
            style: MacosTheme.of(context).typography.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRecoveryInput() {
    return MacosTextField(
      placeholder: 'Enter recovery key (12 words)',
      maxLines: 3,
      prefix: const MacosIcon(CupertinoIcons.lock_shield_fill),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        // Keypad rows
        for (var row = 0; row < 3; row++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var col = 1; col <= 3; col++)
                _buildKeypadButton((row * 3 + col).toString()),
            ],
          ),
          const SizedBox(height: 12),
        ],
        
        // Bottom row (Clear, 0, Backspace)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('C', isAction: true, onTap: _clearPin),
            _buildKeypadButton('0'),
            _buildKeypadButton('⌫', isAction: true, onTap: _removeDigit),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String label, {bool isAction = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: MacosIconButton(
        icon: Text(
          label,
          style: TextStyle(
            fontSize: isAction ? 18 : 24,
            fontWeight: FontWeight.w500,
            color: isAction
              ? MacosColors.systemBlueColor
              : MacosTheme.of(context).typography.body.color,
          ),
        ),
        onPressed: onTap ?? () => _addDigit(label),
        backgroundColor: const Color.fromRGBO(128, 128, 128, 0.1),
        hoverColor: const Color.fromRGBO(128, 128, 128, 0.2),
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }
}
