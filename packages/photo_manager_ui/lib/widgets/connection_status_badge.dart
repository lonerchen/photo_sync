import 'package:flutter/material.dart';

/// Displays the current connection status as a colored dot with a label.
///
/// States:
/// - connected: green dot + "Connected"
/// - connecting: amber pulsing dot + "Connecting…"
/// - disconnected: red dot + "Disconnected"
class ConnectionStatusBadge extends StatefulWidget {
  const ConnectionStatusBadge({
    super.key,
    required this.isConnected,
    required this.isConnecting,
  });

  final bool isConnected;
  final bool isConnecting;

  @override
  State<ConnectionStatusBadge> createState() => _ConnectionStatusBadgeState();
}

class _ConnectionStatusBadgeState extends State<ConnectionStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _resolve();
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isConnecting)
          FadeTransition(opacity: _pulse, child: dot)
        else
          dot,
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  (Color, String) _resolve() {
    if (widget.isConnected) return (Colors.green, 'Connected');
    if (widget.isConnecting) return (Colors.amber, 'Connecting…');
    return (Colors.red, 'Disconnected');
  }
}
