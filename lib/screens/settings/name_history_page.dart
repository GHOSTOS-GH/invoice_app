// lib/screens/settings/name_history_page.dart
// Sous-page des paramètres : noms mémorisés pour l'autocomplétion.

import 'package:flutter/material.dart';

import '../../services/history_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/ui/ui.dart';

enum NameHistoryKind { clients, products }

class NameHistoryPage extends StatefulWidget {
  final NameHistoryKind kind;

  const NameHistoryPage({super.key, required this.kind});

  @override
  State<NameHistoryPage> createState() => _NameHistoryPageState();
}

class _NameHistoryPageState extends State<NameHistoryPage> {
  final HistoryService _historyService = HistoryService();
  List<String> _names = [];
  bool _isLoading = true;

  bool get _isClients => widget.kind == NameHistoryKind.clients;

  String get _title => _isClients ? 'Clients' : 'Historique des articles';

  String get _emptyLabel =>
      _isClients ? 'Aucun client enregistré' : 'Aucun historique article';

  IconData get _emptyIcon =>
      _isClients ? Icons.person_off_outlined : Icons.inventory_2_outlined;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = _isClients
        ? await _historyService.getClientNames()
        : await _historyService.getProductNames();
    if (!mounted) return;
    setState(() {
      _names = names;
      _isLoading = false;
    });
  }

  Future<void> _delete(String name) async {
    if (_isClients) {
      await _historyService.deleteClientName(name);
    } else {
      await _historyService.deleteProductName(name);
    }
    if (!mounted) return;
    setState(() => _names.remove(name));
  }

  Future<void> _edit(String oldName) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _NameEditDialog(initialValue: oldName),
    );
    if (updated == null || !mounted) return;

    if (_isClients) {
      await _historyService.deleteClientName(oldName);
      await _historyService.saveClientName(updated);
    } else {
      await _historyService.deleteProductName(oldName);
      await _historyService.saveProductName(updated);
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    AppSnack.success(context, 'Nom mis à jour');
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer'),
        content: Text(
          _isClients
              ? 'Vider tout l\'historique clients ?'
              : 'Vider tout l\'historique articles ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Vider',
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (_isClients) {
      await _historyService.clearClientNames();
    } else {
      await _historyService.clearProductNames();
    }
    if (!mounted) return;
    setState(() => _names.clear());
    AppSnack.neutral(context, 'Historique vidé');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_names.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Tout vider',
              onPressed: _clearAll,
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 4)
          : _names.isEmpty
              ? EmptyState(
                  icon: _emptyIcon,
                  title: _emptyLabel,
                  message:
                      'Les noms saisis dans les factures sont mémorisés ici '
                      'pour l\'autocomplétion.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: _names.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final name = _names[index];
                    return AppCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        leading: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        title: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: colors.primary,
                              tooltip: 'Modifier',
                              onPressed: () => _edit(name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              color: colors.danger,
                              tooltip: 'Supprimer',
                              onPressed: () => _delete(name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _NameEditDialog extends StatefulWidget {
  final String initialValue;

  const _NameEditDialog({required this.initialValue});

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Nom',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
