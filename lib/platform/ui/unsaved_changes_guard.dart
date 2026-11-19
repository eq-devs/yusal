import 'package:flutter/material.dart';
import '../../app/settings.dart';

/// Keeps a publication form mounted when the user chooses to continue editing.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard(
      {super.key,
      required this.hasChanges,
      this.isBusy,
      this.changes,
      required this.child});
  final bool Function() hasChanges;
  final bool Function()? isBusy;
  final Listenable? changes;
  final Widget child;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _leaving = false, _asking = false;

  Future<void> _back() async {
    if (_asking || _leaving || (widget.isBusy?.call() ?? false)) return;
    _asking = true;
    final leave = !widget.hasChanges() ||
        await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                      title: Text(tr3(
                          '放弃未保存的内容？',
                          'Сақталмаған өзгерістерді жою керек пе?',
                          'Отменить несохранённые изменения?')),
                      content: Text(tr3(
                          '继续编辑可保留当前输入。',
                          'Өңдеуді жалғастырсаңыз, енгізілгендер сақталады.',
                          'Продолжите редактирование, чтобы сохранить введённое.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child:
                                Text(tr3('继续编辑', 'Жалғастыру', 'Продолжить'))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr3(
                                '放弃并返回', 'Жойып, қайту', 'Отменить и выйти'))),
                      ],
                    )) ==
            true;
    _asking = false;
    if (!mounted || !leave) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => widget.changes == null
      ? _guard()
      : ListenableBuilder(
          listenable: widget.changes!, builder: (_, __) => _guard());

  Widget _guard() => PopScope(
        canPop: _leaving ||
            (!(widget.isBusy?.call() ?? false) && !widget.hasChanges()),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: widget.child,
      );
}
