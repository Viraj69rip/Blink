import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

/// A lightweight, floating liquid-glass navigation bar.
///
/// Tab emphasis follows [PageController.page] so the capsule, icon, and label
/// stay in sync during [PageController.animateToPage] transitions.
class BlinkNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final PageController pageController;

  const BlinkNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.pageController,
  });

  static const List<_NavItemData> _items = [
    _NavItemData(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Command',
    ),
    _NavItemData(
      icon: Icons.brush_outlined,
      activeIcon: Icons.brush_rounded,
      label: 'Draw',
    ),
    _NavItemData(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
    ),
    _NavItemData(
      icon: Icons.info_outline_rounded,
      activeIcon: Icons.info_rounded,
      label: 'About',
    ),
  ];

  double _pagePosition() {
    if (!pageController.hasClients) return currentIndex.toDouble();
    return (pageController.page ?? currentIndex.toDouble())
        .clamp(0.0, (_items.length - 1).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 12),
      child: SizedBox(
        height: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            clipBehavior: Clip.antiAlias,
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF20242D).withValues(alpha: 0.78),
                      const Color(0xFF080A0F).withValues(alpha: 0.86),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 0.9,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const _GlassHighlight(),
                    AnimatedBuilder(
                      animation: pageController,
                      builder: (context, _) {
                        final page = _pagePosition();

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            _ActiveCapsule(
                              page: page,
                              itemCount: _items.length,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: List.generate(_items.length, (index) {
                                  final item = _items[index];
                                  final emphasis =
                                      (1 - (page - index).abs()).clamp(0.0, 1.0);
                                  return Expanded(
                                    child: _NavItem(
                                      icon: item.icon,
                                      activeIcon: item.activeIcon,
                                      label: item.label,
                                      emphasis: emphasis,
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        onTap(index);
                                      },
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _GlassHighlight extends StatelessWidget {
  const _GlassHighlight();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.16),
              Colors.transparent,
            ],
            stops: const [0, 0.38],
          ),
        ),
      ),
    );
  }
}

class _ActiveCapsule extends StatelessWidget {
  final double page;
  final int itemCount;

  const _ActiveCapsule({
    required this.page,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / itemCount;
            final capsuleWidth = itemWidth - 8;
            final left = 4 + page * itemWidth;

            return Transform.translate(
              offset: Offset(left, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: capsuleWidth,
                  height: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.055),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(31),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.13),
                        width: 0.75,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final double emphasis;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.emphasis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = Color.lerp(
      Colors.white.withValues(alpha: 0.50),
      BlinkColors.textPrimary,
      emphasis,
    )!;

    return Semantics(
      button: true,
      selected: emphasis > 0.65,
      label: label,
      child: _NavTapTarget(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1 - emphasis).clamp(0.0, 1.0),
                        child: Icon(icon, size: 24, color: foreground),
                      ),
                      Opacity(
                        opacity: emphasis.clamp(0.0, 1.0),
                        child: Icon(activeIcon, size: 24, color: foreground),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                    letterSpacing: 0.1,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Isolated press-scale feedback so parent [AnimatedBuilder] rebuilds do not
/// fight with local [setState] during tab transitions.
class _NavTapTarget extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _NavTapTarget({
    required this.child,
    required this.onTap,
  });

  @override
  State<_NavTapTarget> createState() => _NavTapTargetState();
}

class _NavTapTargetState extends State<_NavTapTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: BlinkConstants.animDurationFast,
        curve: BlinkConstants.animCurve,
        child: widget.child,
      ),
    );
  }
}
