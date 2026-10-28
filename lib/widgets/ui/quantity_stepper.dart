// lib/widgets/ui/quantity_stepper.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Sélecteur de quantité : boutons − / + et saisie directe au clavier.
class QuantityStepper extends StatefulWidget {
  final TextEditingController controller;
  final int min;
  final int? max;
  final ValueChanged<int>? onChanged;
  final String label;
  final bool enabled;

  const QuantityStepper({
    super.key,
    required this.controller,
    this.min = 1,
    this.max,
    this.onChanged,
    this.label = 'Quantité *',
    this.enabled = true,
  });

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Les boutons − / + doivent se refléter même quand le texte change hors
  /// de ce widget (pré-remplissage, remise à zéro).
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  int get _value => int.tryParse(widget.controller.text.trim()) ?? 0;

  void _step(int delta) {
    if (!widget.enabled) return;
    final current = _value == 0 ? widget.min : _value;
    var next = current + delta;
    if (next < widget.min) next = widget.min;
    final max = widget.max;
    if (max != null && next > max) next = max;
    widget.controller.text = next.toString();
    widget.controller.selection =
        TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final canDecrease = widget.enabled && _value > widget.min;
    final canIncrease =
        widget.enabled && (widget.max == null || _value < widget.max!);

    return Row(
      children: [
        _StepButton(
          icon: Icons.remove,
          tooltip: 'Diminuer la quantité',
          onPressed: canDecrease ? () => _step(-1) : null,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (text) {
              widget.onChanged?.call(int.tryParse(text.trim()) ?? 0);
            },
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: colors.textStrong, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: widget.label,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _StepButton(
          icon: Icons.add,
          tooltip: 'Augmenter la quantité',
          onPressed: canIncrease ? () => _step(1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: kMinTapTarget,
      height: kMinTapTarget,
      child: Material(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          iconSize: 20,
          icon: Icon(
            icon,
            color: onPressed == null ? colors.textMuted : colors.primary,
          ),
        ),
      ),
    );
  }
}
