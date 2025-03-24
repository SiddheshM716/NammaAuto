import 'package:flutter/material.dart';

class MenuItemData {
  final IconData icon;
  final String label;
  final Color color;

  MenuItemData({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const MenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 24,
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}