import 'package:flutter/material.dart';

import '../models/detection_models.dart';

class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.risk,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final RiskLevel risk;
  final Widget? trailing;
  final VoidCallback? onTap;

  Color _riskColor(BuildContext context) {
    switch (risk) {
      case RiskLevel.low:
        return Colors.greenAccent.shade400;
      case RiskLevel.medium:
        return Colors.orangeAccent.shade200;
      case RiskLevel.high:
        return Colors.redAccent.shade200;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _riskColor(context).withOpacity(0.15),
          child: Icon(Icons.shield, color: _riskColor(context)),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing ??
            Chip(
              label: Text(risk.name.toUpperCase()),
              backgroundColor: _riskColor(context).withOpacity(0.12),
              labelStyle: TextStyle(
                color: _riskColor(context),
                fontWeight: FontWeight.bold,
              ),
            ),
      ),
    );
  }
}

