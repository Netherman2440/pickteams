import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Uses the pointer kind, not the OS or web flag. A quick touch swipe remains
/// available to the enclosing scroll view, including on hybrid desktops.
class PlayerTransferDrag extends StatelessWidget {
  const PlayerTransferDrag({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.onDragStarted,
    this.onDragEnd,
  });

  final Object data;
  final Widget child;
  final Widget feedback;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final faded = Opacity(opacity: .4, child: child);
    return _MouseDrag(
      data: data,
      feedback: feedback,
      childWhenDragging: faded,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd?.call(),
      child: _TouchDrag(
        data: data,
        feedback: feedback,
        childWhenDragging: faded,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnd?.call(),
        child: child,
      ),
    );
  }
}

class _MouseDrag extends Draggable<Object> {
  const _MouseDrag({
    required super.data,
    required super.child,
    required super.feedback,
    required super.childWhenDragging,
    super.onDragStarted,
    super.onDragEnd,
  }) : super(
         maxSimultaneousDrags: 1,
         dragAnchorStrategy: pointerDragAnchorStrategy,
       );

  @override
  ImmediateMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: {PointerDeviceKind.mouse},
  )..onStart = onStart;
}

class _TouchDrag extends LongPressDraggable<Object> {
  const _TouchDrag({
    required super.data,
    required super.child,
    required super.feedback,
    required super.childWhenDragging,
    super.onDragStarted,
    super.onDragEnd,
  }) : super(
         maxSimultaneousDrags: 1,
         dragAnchorStrategy: pointerDragAnchorStrategy,
       );

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => DelayedMultiDragGestureRecognizer(
    delay: delay,
    supportedDevices: {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.unknown,
    },
  )..onStart = onStart;
}
