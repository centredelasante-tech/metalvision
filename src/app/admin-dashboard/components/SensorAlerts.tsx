import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

const ALERTS = [
  { id: 'alert-1', container: 'CT-003', level: 92, battery: 18, type: 'capacity', severity: 'critical' as const },
  { id: 'alert-2', container: 'CT-014', level: 89, battery: 72, type: 'capacity', severity: 'critical' as const },
  { id: 'alert-3', container: 'CT-007', level: 86, battery: 45, type: 'capacity', severity: 'warning' as const },
  { id: 'alert-4', container: 'CT-011', level: 34, battery: 12, type: 'battery', severity: 'warning' as const },
  { id: 'alert-5', container: 'CT-008', level: 71, battery: 8, type: 'battery', severity: 'critical' as const },
];

const SEVERITY_STYLE = {
  critical: 'bg-red-50 border-red-200',
  warning: 'bg-amber-50 border-amber-200',
};

const SEVERITY_ICON_STYLE = {
  critical: 'text-red-600',
  warning: 'text-amber-600',
};

export default function SensorAlerts() {
  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="BellAlertIcon" size={18} className="text-red-500" />
          <h3 className="text-sm font-600 text-foreground">Alertes capteurs</h3>
        </div>
        <span className="bg-red-100 text-red-600 text-xs font-700 px-2 py-0.5 rounded-full">
          {ALERTS.length}
        </span>
      </div>
      <div className="divide-y divide-border">
        {ALERTS.map((alert) => (
          <Link
            key={alert.id}
            href="/container-detail"
            className={`flex items-start gap-3 px-4 py-3.5 row-hover transition-colors border-l-2 ${
              alert.severity === 'critical' ? 'border-l-red-500' : 'border-l-amber-500'
            }`}
          >
            <div className={`w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 ${
              alert.severity === 'critical' ? 'bg-red-100' : 'bg-amber-100'
            }`}>
              <Icon
                name={alert.type === 'capacity' ? 'ArchiveBoxIcon' : 'BoltIcon'}
                size={16}
                className={SEVERITY_ICON_STYLE[alert.severity]}
              />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-600 text-foreground">{alert.container}</span>
                <span className={`text-[11px] font-600 px-1.5 py-0.5 rounded ${
                  alert.severity === 'critical' ? 'bg-red-100 text-red-600' : 'bg-amber-100 text-amber-700'
                }`}>
                  {alert.severity === 'critical' ? 'Critique' : 'Attention'}
                </span>
              </div>
              {alert.type === 'capacity' && (
                <div className="mt-1.5">
                  <div className="flex justify-between text-xs text-muted-foreground mb-1">
                    <span>Remplissage</span>
                    <span className="tabular-nums font-600 text-red-600">{alert.level}%</span>
                  </div>
                  <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                    <div
                      className="h-full bg-red-500 rounded-full"
                      style={{ width: `${alert.level}%` }}
                    />
                  </div>
                </div>
              )}
              {alert.type === 'battery' && (
                <div className="mt-1.5 flex items-center gap-1.5">
                  <Icon name="BoltIcon" size={12} className="text-amber-600" />
                  <span className="text-xs text-amber-600 font-600">Batterie : {alert.battery}%</span>
                </div>
              )}
            </div>
          </Link>
        ))}
      </div>
      <div className="px-5 py-3 border-t border-border">
        <Link href="/container-detail" className="text-xs text-primary font-600 hover:underline flex items-center gap-1">
          Gérer tous les conteneurs
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>
    </div>
  );
}