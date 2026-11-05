import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Optional review after a mutually ended cooperation, on a few clear
/// dimensions. Each dimension can be left out.
class ReviewPage extends StatefulWidget {
  const ReviewPage(
      {super.key,
      required this.cooperationId,
      required this.otherName,
      this.ratingPro = true});
  final String cooperationId, otherName;

  /// The owner rates the pro's work; the pro rates the owner.
  final bool ratingPro;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final scores = <String, int>{};
  final text = TextEditingController();

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('评价', 'Пікір', 'Отзыв'),
        bottom: BusyButton(
            label: tr3('提交评价', 'Жіберу', 'Отправить'),
            onPressed: scores.isEmpty
                ? null
                : () async {
                    final ok = await attempt(
                        context,
                        () => context.repos.submitReview(
                            widget.cooperationId, scores, text.text),
                        success:
                            tr3('已提交，双方都提交后公开', 'Жіберілді', 'Отправлено'));
                    if (ok != null && context.mounted) Navigator.pop(context);
                  }),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              tr3('评价 ${widget.otherName}', '${widget.otherName} туралы',
                  'Отзыв о ${widget.otherName}'),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              tr3(
                  '只评你实际经历的维度。双方都提交或 14 天后同时公开，降低报复性评价。',
                  'Тек өзіңіз көргенді бағалаңыз. Екеуі де жазғанда ашылады.',
                  'Оценивайте только то, что видели. Отзывы откроются одновременно.'),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 16),
          for (final d in widget.ratingPro
              ? proReviewDimensions
              : ownerReviewDimensions) ...[
            Text(dimensionName(d),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Row(children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                    tooltip: '$i',
                    onPressed: () => setState(() =>
                        scores[d] == i ? scores.remove(d) : scores[d] = i),
                    icon: Icon(
                        (scores[d] ?? 0) >= i
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: (scores[d] ?? 0) >= i ? t.ink : t.faint,
                        size: 30)),
            ]),
            const SizedBox(height: 6),
          ],
          TextField(
              controller: text,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                  labelText:
                      tr3('说说经历（可选）', 'Пікір (міндетті емес)', 'Комментарий'))),
        ]));
  }
}
