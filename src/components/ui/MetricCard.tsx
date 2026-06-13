import React from 'react';
import Icon from '@/components/ui/AppIcon';

interface MetricCardProps {
  label: string;
  value: string;
  subValue?: string;
  icon: string;
  trend?: 'up' | 'down' | 'neutral' | 'alert';
  trendLabel?: string;
  variant?: 'default' | 'alert' | 'positive' | 'accent';
  className?: string;
}

const VARIANT_STYLES = {
  default: 'bg-card border-border',
  alert: 'bg-red-50 border-red-200',
  positive: 'bg-secondary border-secondary',
  accent: 'bg-amber-50 border-amber-200',
};

const ICON_BG = {
  default: 'bg-muted text-muted-foreground',
  alert: 'bg-red-100 text-red-600',
  positive: 'bg-primary/10 text-primary',
  accent: 'bg-amber-100 text-amber-700',
};

export default function MetricCard({
  label,
  value,
  subValue,
  icon,
  trend,
  trendLabel,
  variant = 'default',
  className = '',
}: MetricCardProps) {
  return (
    <div className={`rounded-xl border p-5 card-hover ${VARIANT_STYLES[variant]} ${className}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <p className="text-[13px] font-500 text-muted-foreground uppercase tracking-wide leading-none mb-3">
            {label}
          </p>
          <p className="text-hero-metric tabular-nums text-foreground leading-none">{value}</p>
          {subValue && (
            <p className="text-xs text-muted-foreground mt-1.5">{subValue}</p>
          )}
          {trendLabel && (
            <div className="flex items-center gap-1 mt-2">
              {trend === 'up' && <Icon name="ArrowUpIcon" size={12} className="text-green-600" />}
              {trend === 'down' && <Icon name="ArrowDownIcon" size={12} className="text-red-500" />}
              {trend === 'alert' && <Icon name="ExclamationTriangleIcon" size={12} className="text-amber-600" />}
              <span className={`text-xs font-500 ${
                trend === 'up' ? 'text-green-600' :
                trend === 'down' ? 'text-red-500' :
                trend === 'alert'? 'text-amber-600' : 'text-muted-foreground'
              }`}>
                {trendLabel}
              </span>
            </div>
          )}
        </div>
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${ICON_BG[variant]}`}>
          <Icon name={icon as Parameters<typeof Icon>[0]['name']} size={20} />
        </div>
      </div>
    </div>
  );
}