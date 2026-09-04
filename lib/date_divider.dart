// date_divider.dart
//
// Rótulo/linha separadora de data na timeline de mensagens (1:1 e grupo) —
// mesmo padrão visual de WhatsApp/Telegram: "Hoje", "Ontem" ou "dd/mm/aaaa"
// aparece toda vez que o dia muda entre uma mensagem e a seguinte.

import 'package:flutter/material.dart';

String dateDividerLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) return 'Hoje';
  if (difference == 1) return 'Ontem';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

/// Mesma data (dia/mês/ano) — usado para decidir se um novo divisor precisa
/// aparecer entre dois itens consecutivos da timeline.
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class DateDivider extends StatelessWidget {
  const DateDivider({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              dateDividerLabel(date),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
