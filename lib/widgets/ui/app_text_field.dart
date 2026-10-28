// lib/widgets/ui/app_text_field.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// Champ de saisie unifié. Dès qu'un [validator] est fourni, le champ devient
/// un [TextFormField] (validation par formulaire).
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final int minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool isDense;
  final TextCapitalization textCapitalization;

  const AppTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.errorText,
    this.helperText,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.focusNode,
    this.autofocus = false,
    this.isDense = false,
    this.textCapitalization = TextCapitalization.none,
  });

  InputDecoration _decoration(BuildContext context) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffix,
      errorText: errorText,
      helperText: helperText,
      isDense: isDense,
      alignLabelWithHint: maxLines > 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    if (validator != null) {
      return TextFormField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        maxLines: maxLines,
        minLines: minLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        focusNode: focusNode,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        style: textStyle?.copyWith(color: colors.textStrong),
        decoration: _decoration(context),
      );
    }

    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      focusNode: focusNode,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      style: textStyle?.copyWith(color: colors.textStrong),
      decoration: _decoration(context),
    );
  }
}
