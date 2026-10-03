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
    final progress = goal > 0 ? (totals.calories / goal).clamp(0.0, 1.0) : 0.0;
    Widget metric(
      String key,
      String title,
      double value,
      Color color,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 12)),
              ),
              Text(
                '${value.toStringAsFixed(1)}${(macroGoals[key] as num? ?? 0) > 0 ? ' / ${macroGoals[key]}' : ''} г',
                style: const TextStyle(fontSize: 12, color: Color(0xFF777C75)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if ((macroGoals[key] as num? ?? 0) > 0)
            LinearProgressIndicator(
              value: (value / (macroGoals[key] as num)).clamp(0.0, 1.0),
              color: color,
              backgroundColor: const Color(0xFFE8E7E0),
              minHeight: 4,
              borderRadius: BorderRadius.circular(3),
            ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 126,
              height: 126,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 122,
                    height: 122,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      backgroundColor: const Color(0xFFE8E7E0),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_outlined,
                        color: Color(0xFFAB8455),
                        size: 22,
                      ),
                      Text(
                        totals.calories.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'из ${goal.toStringAsFixed(0)} ккал',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF777C75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  metric(
                    'proteinGoal',
                    'Белки',
                    totals.protein,
                    const Color(0xFF21A5AA),
                  ),
                  metric(
                    'fatGoal',
                    'Жиры',
                    totals.fat,
                    const Color(0xFFD7B695),
                  ),
                  metric(
                    'carbsGoal',
                    'Углеводы',
                    totals.carbs,
                    const Color(0xFFD6A654),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
