import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../../motion/motion.dart';
import 'scope.dart';
import 'theme.dart';

/// Parts of the design system that several pages share. Sizes, radii and
/// colours come from `theme.dart`; nothing here has its own palette.

/// Pill-shaped search field with a clear button. One look for every list.
class SearchField extends StatelessWidget {
  const SearchField(
      {super.key,
      required this.controller,
      required this.hint,
      required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Material(
            color: t.card,
            shape: StadiumBorder(side: BorderSide(color: t.line)),
            child: Row(children: [
              const SizedBox(width: YSpace.lg),
              Icon(Icons.search, color: t.muted, size: 22),
              const SizedBox(width: YSpace.sm),
              Expanded(
                  child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: hint,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14)))),
              if (controller.text.isEmpty)
                const SizedBox(width: YSpace.lg)
              else
                IconButton(
                    tooltip: tr3('清除', 'Тазалау', 'Очистить'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    }),
            ])));
  }
}

/// A group of rows on one rounded surface, with an optional caption above:
/// the inset grouped list of a settings screen.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(
                YSpace.xs, YSpace.xxl, YSpace.xs, YSpace.sm),
            child: Semantics(
                header: true,
                child: Text(title!,
                    style: YText.labelStrong.copyWith(color: t.muted)))),
      Material(
          color: t.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.card),
              side: BorderSide(color: t.line)),
          child: Column(children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) Divider(height: 1, indent: 52, color: t.line),
              child,
            ],
          ])),
    ]);
  }
}

/// One row of a [SettingsGroup]: icon, title, an optional current value
/// and a chevron when it leads somewhere.
class SettingsRow extends StatelessWidget {
  const SettingsRow(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.value,
      this.onTap,
      this.danger = false,
      this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final color = danger ? t.crit : t.ink;
    return InkWell(
        onTap: onTap,
        child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: YSpace.lg, vertical: YSpace.sm),
                child: Row(children: [
                  Icon(icon, size: 22, color: danger ? t.crit : t.muted),
                  const SizedBox(width: YSpace.lg - 2),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(title, style: YText.body.copyWith(color: color)),
                        if (subtitle != null)
                          Text(subtitle!,
                              style: YText.caption.copyWith(color: t.muted)),
                      ])),
                  if (value != null) ...[
                    const SizedBox(width: YSpace.sm),
                    // Sized to its text and pinned to the right edge.
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(value!,
                            maxLines: 1,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: YText.label.copyWith(color: t.muted))),
                  ],
                  if (trailing != null)
                    trailing!
                  else if (onTap != null && !danger) ...[
                    const SizedBox(width: YSpace.xs),
                    Icon(Icons.chevron_right, size: 20, color: t.faint),
                  ],
                ]))));
  }
}

/// A grey block standing in for content that is loading. It breathes
/// slowly so a waiting page reads as working, not frozen; with reduce
/// motion on it stays still.
class Skeleton extends StatefulWidget {
  const Skeleton(
      {super.key, this.width, this.height = 14, this.radius = YRadius.row});
  final double? width;
  final double height, radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _breath;
  Animation<double>? _opacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _breath?.dispose();
      _breath = null;
      _opacity = null;
    } else if (_breath == null) {
      final breath = _breath =
          AnimationController(vsync: this, duration: Motion.breath)
            ..repeat(reverse: true);
      _opacity = Tween<double>(begin: 1, end: 0.45)
          .animate(CurvedAnimation(parent: breath, curve: Curves.easeInOut));
    }
  }

  @override
  void dispose() {
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
            color: YTokens.of(context).surface,
            borderRadius: BorderRadius.circular(widget.radius)));
    final opacity = _opacity;
    if (opacity == null) return block;
    return FadeTransition(opacity: opacity, child: block);
  }
}

/// One loading row: an optional avatar and two lines of text.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key, this.avatar = false, this.avatarSize = 48});
  final bool avatar;
  final double avatarSize;
  @override
  Widget build(BuildContext context) => Row(children: [
        if (avatar) ...[
          Skeleton(
              width: avatarSize, height: avatarSize, radius: avatarSize / 2),
          const SizedBox(width: YSpace.md),
        ],
        const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              FractionallySizedBox(
                  widthFactor: 0.7, child: Skeleton(height: 16)),
              SizedBox(height: YSpace.sm),
              FractionallySizedBox(widthFactor: 0.45, child: Skeleton()),
            ])),
      ]);
}

/// The outline of a list while it loads: [count] rows shaped like the
/// cards that will replace them, so the page does not jump.
class SkeletonList extends StatelessWidget {
  const SkeletonList(
      {super.key,
      this.count = 3,
      this.cover = 0,
      this.avatar = false,
      this.padding = EdgeInsets.zero});
  final int count;

  /// Height of a picture above each row's text; 0 for none.
  final double cover;
  final bool avatar;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Semantics(
      label: tr3('加载中', 'Жүктелуде', 'Загрузка'),
      child: ExcludeSemantics(
          child: Padding(
              padding: padding,
              child: Column(children: [
                for (var i = 0; i < count; i++)
                  Padding(
                      padding: const EdgeInsets.only(bottom: YSpace.xxl),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (cover > 0) ...[
                              Skeleton(
                                  height: cover,
                                  width: double.infinity,
                                  radius: YRadius.card),
                              const SizedBox(height: YSpace.md),
                            ],
                            SkeletonRow(avatar: avatar),
                          ])),
              ]))));
}

/// A whole page while it loads: the app bar with its back button, then the
/// outline of a detail page, so a pushed route is never a blank screen
/// with a spinner. [cover] is the height of a picture on top; 0 for none.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key, this.cover = 0, this.avatar = false});
  final double cover;
  final bool avatar;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(),
      body: SafeArea(
          top: false,
          child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                          YSpace.xl, YSpace.sm, YSpace.xl, YSpace.xxxl),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (cover > 0) ...[
                              Skeleton(
                                  height: cover,
                                  width: double.infinity,
                                  radius: YRadius.card),
                              const SizedBox(height: YSpace.xl),
                            ],
                            const FractionallySizedBox(
                                widthFactor: 0.6,
                                child: Skeleton(height: 24)),
                            const SizedBox(height: YSpace.md),
                            const FractionallySizedBox(
                                widthFactor: 0.85, child: Skeleton()),
                            const SizedBox(height: YSpace.sm),
                            const FractionallySizedBox(
                                widthFactor: 0.4, child: Skeleton()),
                            const SizedBox(height: YSpace.xxxl),
                            SkeletonList(count: 4, avatar: avatar),
                          ]))))));
}

/// Round icon button on a solid backing, for controls that sit on a
/// picture or a drawing and must stay visible in both themes.
class IconAction extends StatelessWidget {
  const IconAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.color,
      this.backing = true});
  final Widget icon;

  /// Read by screen readers and shown on long press.
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  /// False once the bar has a solid background of its own.
  final bool backing;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IconButton(
            tooltip: label,
            onPressed: onPressed,
            style: IconButton.styleFrom(
                backgroundColor: backing ? t.onImage : Colors.transparent,
                foregroundColor: color ?? t.ink,
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero),
            icon: icon));
  }
}

/// Shown in place of content that needs an account: what signing in gives,
/// and the button.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.text, this.body, this.icon});
  final String text;
  final String? body;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Center(
        child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                vertical: YSpace.huge, horizontal: YSpace.xxl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      color: t.accentSoft, shape: BoxShape.circle),
                  child: Icon(icon ?? Icons.lock_outline,
                      size: 28, color: t.accent)),
              const SizedBox(height: YSpace.lg),
              Text(text, textAlign: TextAlign.center, style: YText.heading),
              if (body != null) ...[
                const SizedBox(height: YSpace.sm),
                Text(body!,
                    textAlign: TextAlign.center,
                    style: YText.label.copyWith(color: t.muted)),
              ],
              const SizedBox(height: YSpace.xl),
              FilledButton(
                  key: const Key('sign-in-prompt'),
                  onPressed: () => requireLogin(context),
                  child: Text(tr3('登录或注册', 'Кіру', 'Войти'))),
            ])));
  }
}

/// One quiet line saying the platform runs on demo data; tap for the
/// details. Replaces a two-line notice above every tab.
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final title = tr3('演示模式', 'Демо режимі', 'Демо-режим');
    final body = tr3(
        '平台上的账号、聊天、作品、需求和报价是演示数据，重启后会重置。你在本机画的设计会一直保留。',
        'Платформадағы аккаунттар, чаттар, жобалар мен тапсырыстар — демо деректер, қайта іске қосқанда өшеді. Осы құрылғыда сызған жобаларыңыз сақталады.',
        'Аккаунты, чаты, дома, заявки и предложения на платформе — демо-данные, они сбрасываются при перезапуске. Проекты, нарисованные на этом устройстве, сохраняются.');
    return Semantics(
        button: true,
        label: title,
        child: InkWell(
            key: const Key('demo-notice'),
            onTap: () => showDialog<void>(
                context: context,
                builder: (context) => PlatformTheme(
                        child: AlertDialog(
                            title: Text(title),
                            content: Text(body),
                            actions: [
                          FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(tr3('知道了', 'Түсінікті', 'Понятно'))),
                        ]))),
            child: Container(
                width: double.infinity,
                color: t.surface,
                padding: const EdgeInsets.symmetric(
                    horizontal: YSpace.lg, vertical: 6),
                child: ExcludeSemantics(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.info_outline, size: 14, color: t.muted),
                      const SizedBox(width: 6),
                      Flexible(
                          child: Text(
                              '$title · ${tr3('平台数据重启后重置', 'деректер уақытша', 'данные временные')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: YText.caption.copyWith(color: t.muted))),
                    ])))));
  }
}
