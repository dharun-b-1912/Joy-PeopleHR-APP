import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Shared responsive layout helpers and reusable grid components
/// for JOY PeopleHR Employee App.
class AppResponsive {
  AppResponsive._();

  /// Number of columns for metric summary cards based on available container width.
  static int metricColumnsForWidth(double width, {int maxColumns = 4}) {
    final int raw;
    if (width >= 720) {
      raw = 5;
    } else if (width >= 520) {
      raw = 4;
    } else if (width >= 330) {
      raw = 3;
    } else {
      raw = 2;
    }
    return raw.clamp(2, maxColumns);
  }

  /// Splits [items] into rows of [cols]. Items in an incomplete final row
  /// stretch to fill the full width, so no empty half-cells remain.
  static List<List<T>> chunkRows<T>(List<T> items, int cols) {
    final rows = <List<T>>[];
    for (var i = 0; i < items.length; i += cols) {
      rows.add(items.sublist(i, (i + cols) > items.length ? items.length : i + cols));
    }
    return rows;
  }

  /// Number of columns for break action buttons based on available container width.
  static int breakActionColumnsForWidth(double width) {
    if (width < 290) return 1;
    if (width < 560) return 2;
    return 3;
  }
}

class ResponsiveMetricItem {
  final String label;
  final String value;
  final Color valueColor;
  final bool highlight;

  const ResponsiveMetricItem({
    required this.label,
    required this.value,
    this.valueColor = AppColors.textPrimary,
    this.highlight = false,
  });
}

/// Adaptive equal-width metric grid using LayoutBuilder.
/// Prevents horizontal overflow and fixed-width gaps across 320px–tablet widths.
class ResponsiveMetricGrid extends StatelessWidget {
  final List<ResponsiveMetricItem> items;
  final int maxColumns;
  final double spacing;

  const ResponsiveMetricGrid({
    super.key,
    required this.items,
    this.maxColumns = 4,
    this.spacing = AppSpacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = AppResponsive.metricColumnsForWidth(
          constraints.maxWidth,
          maxColumns: maxColumns,
        );
        final rows = AppResponsive.chunkRows(items, cols);

        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < rows[r].length; c++) ...[
                      if (c > 0) SizedBox(width: spacing),
                      Expanded(child: _MetricTileCard(item: rows[r][c])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MetricTileCard extends StatelessWidget {
  final ResponsiveMetricItem item;

  const _MetricTileCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: item.highlight ? AppColors.workingGreenBg : AppColors.scaffoldBg,
        borderRadius: AppRadius.borderSm,
        border: Border.all(
          color: item.highlight
              ? AppColors.workingGreenBorder
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              item.value,
              maxLines: 1,
              style: AppTypography.titleMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: item.valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BreakActionButtonData {
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onPressed;

  const BreakActionButtonData({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onPressed,
  });
}

/// Adaptive equal-width grid of break action buttons.
/// Guarantees >= 48dp touch targets, balanced rows, and zero horizontal clipping.
class ResponsiveBreakActionGrid extends StatelessWidget {
  final List<BreakActionButtonData> actions;
  final double spacing;

  const ResponsiveBreakActionGrid({
    super.key,
    required this.actions,
    this.spacing = AppSpacing.sm,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = AppResponsive.breakActionColumnsForWidth(constraints.maxWidth);
        final rows = AppResponsive.chunkRows(actions, cols);

        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < rows[r].length; c++) ...[
                      if (c > 0) SizedBox(width: spacing),
                      Expanded(child: _BreakActionTile(action: rows[r][c])),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BreakActionTile extends StatelessWidget {
  final BreakActionButtonData action;

  const _BreakActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    return Material(
      color: enabled ? Colors.white : AppColors.surfaceSubtle,
      borderRadius: AppRadius.borderSm,
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: AppRadius.borderSm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderSm,
              border: Border.all(
                color: enabled
                    ? action.accentColor.withValues(alpha: 0.42)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: action.accentColor.withValues(alpha: enabled ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    action.icon,
                    size: 16,
                    color: enabled ? action.accentColor : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                      height: 1.2,
                    ),
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

