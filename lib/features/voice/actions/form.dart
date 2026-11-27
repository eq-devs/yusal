import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/screen.dart';

/// Failure code when the page has nothing to send.
const nothingToSubmit = 'nothing_to_submit';

final formActions = [
  AppAction(
    id: 'form.fill',
    title: const L3(
        '填写表单', 'Пішінді толтыру', 'Заполнить форму', 'Fill in the form',
        ky: 'Форманы толтуруу', uz: 'Formani toʻldirish'),
    examples: const L3(
        '找两个瓦工，日薪一万五',
        'Екі қалаушы керек, күніне он бес мың',
        'Нужны два каменщика, пятнадцать тысяч в день',
        'Need two masons, fifteen thousand a day',
        ky: 'Эки дубалчы керек, күнүнө он беш миң',
        uz: 'Ikki gʻishtchi kerak, kuniga oʻn besh ming'),
    params: const {'values': Param.fields()},
    when: (ctx) => VoiceScreens.current?.fields.isNotEmpty ?? false,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final fields = {
        for (final f in VoiceScreens.current?.fields ?? const <VoiceField>[])
          f.name: f
      };
      final values = args.fields('values');
      // All or nothing: one bad value and no field changes.
      for (final MapEntry(key: name, :value) in values.entries) {
        if (!(fields[name]?.accepts(value) ?? false)) {
          return ActionResult.fail(ActionCodes.badArgs, say: {'field': name});
        }
      }
      for (final MapEntry(key: name, :value) in values.entries) {
        fields[name]!.write(value!);
      }
      return ActionResult.ok(changed: [...values.keys]);
    },
  ),
  AppAction(
    id: 'form.submit',
    title: const L3('提交或发送', 'Жіберу', 'Отправить', 'Send',
        ky: 'Жөнөтүү', uz: 'Yuborish'),
    examples:
        const L3('发送', 'Жібер', 'Отправь', 'Send it', ky: 'Жөнөт', uz: 'Yubor'),
    when: (ctx) => VoiceScreens.current?.voiceSubmit != null,
    risk: Risk.outbound,
    run: (ctx, args) async {
      final submit = VoiceScreens.current?.voiceSubmit;
      if (submit == null) return const ActionResult.fail(nothingToSubmit);
      await submit();
      return const ActionResult.ok();
    },
  ),
];
