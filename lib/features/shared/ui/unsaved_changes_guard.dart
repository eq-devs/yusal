import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';

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
  bool _leaving = false;
  bool _asking = false;

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
                          'Отменить несохранённые изменения?',
                          'Discard unsaved changes?', ky: 'Сакталбаган өзгөртүүлөрдү өчүрөсүзбү?', uz: 'Saqlanmagan oʻzgarishlar oʻchirilsinmi?')),
                      content: Text(tr3(
                          '继续编辑可保留当前输入。',
                          'Өңдеуді жалғастырсаңыз, енгізілгендер сақталады.',
                          'Продолжите редактирование, чтобы сохранить введённое.',
                          'Keep editing to save what you entered.', ky: 'Киргизгениңизди сактоо үчүн түзөтүүнү улантыңыз.', uz: 'Kiritganlaringizni saqlash uchun tahrirlashni davom ettiring.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child:
                                Text(tr3('继续编辑', 'Жалғастыру', 'Продолжить', 'Keep editing', ky: 'Түзөтүүнү улантуу', uz: 'Tahrirlashni davom ettirish'))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr3(
                                '放弃并返回', 'Жойып, қайту', 'Отменить и выйти', 'Discard and leave', ky: 'Өчүрүп, чыгуу', uz: 'Oʻchirib, chiqish'))),
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
