import 'package:flutter/material.dart';
import '../../shared/models/entry.dart';

class NutritionSummary extends StatelessWidget {
  final NutritionTotals totals;
  final double goal;
  final Map<String, dynamic> macroGoals;
  const NutritionSummary({
    super.key,
    required this.totals,
    required this.goal,
    this.macroGoals = const {},
  });
  @override
  Widget build(BuildContext context) {
    final hasGoal = goal.isFinite && goal > 0;
    final remaining = goal - totals.calories;
    final progress = hasGoal ? (totals.calories / goal).clamp(0.0, 1.0) : 0.0;
    Widget macro(String key, String label, double value, Color color) {
      final target = (macroGoals[key] as num? ?? 0).toDouble();
      final hasTarget = target.isFinite && target > 0;
      return SizedBox(
        width: 96,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '${value.toStringAsFixed(0)}${hasTarget ? ' / ${target.toStringAsFixed(0)}' : ''} г',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (hasTarget)
                  LinearProgressIndicator(
                    value: (value / target).clamp(0.0, 1.0),
                    color: color,
                    backgroundColor: color.withValues(alpha: .15),
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(4),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        SizedBox(
          width: 210,
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .12),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasGoal
                        ? remaining < 0
                              ? 'Сверх цели'
                              : 'Осталось'
                        : 'Съедено',
                  ),
                  Text(
                    (hasGoal ? remaining.abs() : totals.calories)
                        .toStringAsFixed(0),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    hasGoal
                        ? 'Цель ${goal.toStringAsFixed(0)} ккал'
                        : 'ккал · цель не задана',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Съедено ${totals.calories.toStringAsFixed(0)} ккал',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            macro(
              'carbsGoal',
              'Углеводы',
              totals.carbs,
              const Color(0xFFAAA2D3),
            ),
            macro(
              'proteinGoal',
              'Белки',
              totals.protein,
              const Color(0xFF21A5AA),
            ),
            macro('fatGoal', 'Жиры', totals.fat, const Color(0xFFD7B695)),
          ],
        ),
      ],
    );
  }
}
