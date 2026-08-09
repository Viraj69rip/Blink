import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Touch gesture detector for BLINK robot control.
/// 
/// Gestures:
/// - Single tap: Selection / Confirm
/// - Double tap: Menu / Context action
/// - Triple tap: Back / Exit
/// - Long press: Home / Reset to idle
class TouchGestureDetector extends StatefulWidget {
  const TouchGestureDetector({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onTripleTap,
    this.onLongPress,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTripleTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  @override
  State<TouchGestureDetector> createState() => _TouchGestureDetectorState();
}

class _TouchGestureDetectorState extends State<TouchGestureDetector> {
  // Gesture timing constants (matching firmware)
  static const Duration _maxTapDuration = Duration(milliseconds: 300);
  static const Duration _maxTapGap = Duration(milliseconds: 350);
  static const Duration _tapSettleTime = Duration(milliseconds: 400);
  static const Duration _longPressDuration = Duration(milliseconds: 1800);

  int _tapCount = 0;
  DateTime? _lastTapTime;
  DateTime? _pressStartTime;
  Timer? _settleTimer;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  @override
  void dispose() {
    _settleTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    _pressStartTime = DateTime.now();
    _longPressTriggered = false;
    
    _longPressTimer = Timer(_longPressDuration, () {
      if (mounted && !_longPressTriggered) {
        _longPressTriggered = true;
        _cancelPendingTap();
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call();
      }
    });
  }

  void _onTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    _longPressTimer?.cancel();
    
    if (_longPressTriggered) {
      // Don't register tap if it was a long press
      return;
    }

    final now = DateTime.now();
    final pressDuration = _pressStartTime != null 
        ? now.difference(_pressStartTime!) 
        : Duration.zero;

    // Only count as tap if press was short enough
    if (pressDuration <= _maxTapDuration) {
      if (_tapCount == 0 || now.difference(_lastTapTime!) <= _maxTapGap) {
        _tapCount++;
        _lastTapTime = now;
      } else {
        // Gap too long, reset
        _tapCount = 1;
        _lastTapTime = now;
      }

      _settleTimer?.cancel();
      _settleTimer = Timer(_tapSettleTime, _resolveGesture);
    }
  }

  void _onTapCancel() {
    _longPressTimer?.cancel();
  }

  void _cancelPendingTap() {
    _settleTimer?.cancel();
    _tapCount = 0;
    _lastTapTime = null;
  }

  void _resolveGesture() {
    if (!mounted) return;
    
    final count = _tapCount;
    _tapCount = 0;
    _lastTapTime = null;

    switch (count) {
      case 1:
        HapticFeedback.lightImpact();
        widget.onSingleTap?.call();
        break;
      case 2:
        HapticFeedback.mediumImpact();
        widget.onDoubleTap?.call();
        break;
      case 3:
        HapticFeedback.heavyImpact();
        widget.onTripleTap?.call();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? _onTapDown : null,
      onTapUp: widget.enabled ? _onTapUp : null,
      onTapCancel: widget.enabled ? _onTapCancel : null,
      child: widget.child,
    );
  }
}

/// Extension to add touch gestures to any widget easily
extension TouchGestures on Widget {
  Widget withTouchGestures({
    VoidCallback? onSingleTap,
    VoidCallback? onDoubleTap,
    VoidCallback? onTripleTap,
    VoidCallback? onLongPress,
    bool enabled = true,
  }) {
    return TouchGestureDetector(
      onSingleTap: onSingleTap,
      onDoubleTap: onDoubleTap,
      onTripleTap: onTripleTap,
      onLongPress: onLongPress,
      enabled: enabled,
      child: this,
    );
  }
}