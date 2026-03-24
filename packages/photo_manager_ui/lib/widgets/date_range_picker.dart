import 'package:flutter/material.dart';

/// A widget that lets the user pick a date range via preset options or a
/// custom calendar dialog.
///
/// Calls [onChanged] with a [DateTimeRange] when a selection is made, or
/// `null` when "All time" is chosen.
class DateRangePicker extends StatefulWidget {
  const DateRangePicker({super.key, required this.onChanged});

  final ValueChanged<DateTimeRange?> onChanged;

  @override
  State<DateRangePicker> createState() => _DateRangePickerState();
}

class _DateRangePickerState extends State<DateRangePicker> {
  _Preset _selected = _Preset.allTime;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final preset in _Preset.values)
          ChoiceChip(
            label: Text(preset.label),
            selected: _selected == preset,
            onSelected: (_) => _onPresetTapped(context, preset),
          ),
      ],
    );
  }

  Future<void> _onPresetTapped(BuildContext context, _Preset preset) async {
    if (preset == _Preset.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: now,
        initialDateRange: DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        ),
      );
      if (range == null) return; // user cancelled
      setState(() => _selected = _Preset.custom);
      widget.onChanged(range);
      return;
    }

    setState(() => _selected = preset);
    widget.onChanged(preset.toRange());
  }
}

enum _Preset {
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  last3Months('Last 3 months'),
  allTime('All time'),
  custom('Custom…');

  const _Preset(this.label);
  final String label;

  DateTimeRange? toRange() {
    final now = DateTime.now();
    return switch (this) {
      _Preset.last7Days => DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        ),
      _Preset.last30Days => DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        ),
      _Preset.last3Months => DateTimeRange(
          start: DateTime(now.year, now.month - 3, now.day),
          end: now,
        ),
      _Preset.allTime => null,
      _Preset.custom => null, // handled separately
    };
  }
}
