import 'package:flutter/material.dart';

/// 全局视觉规范。参考了常见校园类 App 的克制排版：白卡片、细描边、
/// 大数字、彩色细条，但不照抄某一家的具体版式。
class TguColors {
  const TguColors._();

  /// 主文字。
  static const Color ink = Color(0xFF1B1D21);

  /// 次要文字（说明、时间、单位）。
  static const Color sub = Color(0xFF8A8F98);

  /// 极浅描边。
  static const Color line = Color(0xFFECEDF1);

  /// 页面底色，比卡片略深，卡片才浮得起来。
  static const Color page = Color(0xFFF6F7F9);

  /// 卡片底色。
  static const Color card = Colors.white;

  /// 主色取自教务登录页背景，保持和学校视觉一致。
  static const Color brand = Color(0xFF71246B);

  /// 一组柔和强调色，按索引取，用于课程左侧细条。
  static const List<Color> accents = <Color>[
    Color(0xFF4C7DF0),
    Color(0xFF7A5AF8),
    Color(0xFF12A594),
    Color(0xFFF2994A),
    Color(0xFFE05C8A),
    Color(0xFF3B82C4),
  ];

  static Color accentAt(int index) => accents[index.abs() % accents.length];

  /// 同一门课每次打开颜色一致：用名字的稳定哈希，而不是遍历序号。
  static Color accentFor(String name) {
    int hash = 0;
    for (final int unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return accentAt(hash);
  }
}

/// 标准白卡片：圆角 18、极浅描边、可选点击。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget body = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: TguColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TguColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              child: body,
            ),
    );
  }
}

/// 分组小标题：小字号、灰色、字距略宽。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.2,
                color: TguColors.sub,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 药丸形分段选择。选中项是深色实心，和页面其它大数字形成对比。
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 8),
              child: _Pill(
                label: items[i],
                selected: i == selectedIndex,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? TguColors.ink : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? TguColors.ink : TguColors.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : TguColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一组统计数字：上面大数，下面小灰标签，等宽分布。
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.items});

  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (final StatItem item in items)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: item.danger ? const Color(0xFFD93A3A) : TguColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: TguColors.sub),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class StatItem {
  const StatItem(this.value, this.label, {this.danger = false});

  final String value;
  final String label;
  final bool danger;
}

/// 带左侧细色条的一行：标题 + 一行灰色说明 + 右侧数值。
class AccentTile extends StatelessWidget {
  const AccentTile({
    super.key,
    required this.accent,
    required this.title,
    this.meta = '',
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final Color accent;
  final String title;
  final String meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final Widget body = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: TguColors.ink,
                  ),
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TguColors.sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    return onTap == null
        ? body
        : InkWell(onTap: onTap, child: body);
  }
}

/// 浅色底的小徽章，用来标「必修」「已批阅」这类状态。
class SoftBadge extends StatelessWidget {
  const SoftBadge(this.text, {super.key, this.color = TguColors.brand});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 页面统一底色，避免每页各写一遍。
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: TguColors.page, child: child);
  }
}
