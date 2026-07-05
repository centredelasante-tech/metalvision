'use client';
import React, { useEffect, useState } from 'react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

interface VolumePoint {
  date: string;
  [metal: string]: string | number;
}

interface ValuePoint {
  date: string;
  valeur: number;
}

const METAL_COLORS: Record<string, string> = {
  fer: '#9ca3af',
  cuivre: 'var(--accent)',
  aluminium: '#93c5fd',
  acier: '#374151',
  inox: '#a78bfa',
  laiton: '#fbbf24',
  autre: '#6b7280',
};

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: { name: string; value: number; color: string }[]; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-xl shadow-modal p-3 text-xs">
      <p className="font-600 text-foreground mb-2">{label}</p>
      {payload.map((p) => (
        <div key={`tooltip-${p.name}`} className="flex items-center gap-2 mb-1">
          <div className="w-2 h-2 rounded-full" style={{ backgroundColor: p.color }} />
          <span className="text-muted-foreground capitalize">{p.name}</span>
          <span className="font-600 text-foreground tabular-nums ml-auto pl-4">
            {typeof p.value === 'number' ? p.value.toFixed(2) : p.value}
          </span>
        </div>
      ))}
    </div>
  );
};

const ValueTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-xl shadow-modal p-3 text-xs">
      <p className="font-600 text-foreground mb-1">{label}</p>
      <p className="text-primary font-700 tabular-nums">{payload[0]?.value?.toFixed(0)} $CA</p>
    </div>
  );
};

function formatDay(isoDate: string): string {
  const d = new Date(isoDate);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

export default function AdminChartsInner() {
  const [volumeData, setVolumeData] = useState<VolumePoint[]>([]);
  const [valueData, setValueData] = useState<ValuePoint[]>([]);
  const [metalKeys, setMetalKeys] = useState<string[]>([]);
  const [totalValue, setTotalValue] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const supabase = createClient();

    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const since = sevenDaysAgo.toISOString();

    supabase
      .from('raw_measurements')
      .select('metal_type_predicted, volume_estimated_m3, price_paid, created_at')
      .gte('created_at', since)
      .order('created_at', { ascending: true })
      .then(({ data, error }) => {
        if (error || !data || data.length === 0) {
          setLoading(false);
          return;
        }

        // Group by day
        const dayVolumeMap: Record<string, Record<string, number>> = {};
        const dayValueMap: Record<string, number> = {};
        const metalsSet = new Set<string>();

        data.forEach((row) => {
          const day = formatDay(row.created_at);
          const metal = (row.metal_type_predicted ?? 'autre').toLowerCase();
          const vol = Number(row.volume_estimated_m3 ?? 0);
          const price = Number(row.price_paid ?? 0);

          metalsSet.add(metal);

          if (!dayVolumeMap[day]) dayVolumeMap[day] = {};
          dayVolumeMap[day][metal] = (dayVolumeMap[day][metal] ?? 0) + vol;

          dayValueMap[day] = (dayValueMap[day] ?? 0) + price;
        });

        const metals = Array.from(metalsSet);
        setMetalKeys(metals);

        const volPoints: VolumePoint[] = Object.entries(dayVolumeMap).map(([date, metals]) => ({
          date,
          ...Object.fromEntries(Object.entries(metals).map(([k, v]) => [k, parseFloat(v.toFixed(3))])),
        }));

        const valPoints: ValuePoint[] = Object.entries(dayValueMap).map(([date, valeur]) => ({
          date,
          valeur: parseFloat(valeur.toFixed(2)),
        }));

        const total = valPoints.reduce((s, p) => s + p.valeur, 0);

        setVolumeData(volPoints);
        setValueData(valPoints);
        setTotalValue(total);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return (
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {[0, 1].map((i) => (
          <div key={i} className="bg-card rounded-xl border border-border p-5">
            <div className="h-4 bg-muted rounded w-48 mb-2 animate-pulse" />
            <div className="h-3 bg-muted rounded w-32 mb-6 animate-pulse" />
            <div className="h-[220px] bg-muted rounded-lg animate-pulse" />
          </div>
        ))}
      </div>
    );
  }

  const isEmpty = volumeData.length === 0 && valueData.length === 0;

  if (isEmpty) {
    return (
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {['Volume traité par métal', 'Valeur traitée par jour'].map((title) => (
          <div key={title} className="bg-card rounded-xl border border-border p-5">
            <h3 className="text-sm font-600 text-foreground mb-1">{title}</h3>
            <p className="text-xs text-muted-foreground mb-6">7 derniers jours</p>
            <div className="flex flex-col items-center justify-center h-[220px] gap-3">
              <Icon name="ChartBarIcon" size={32} className="text-muted-foreground" />
              <p className="text-sm text-muted-foreground">Aucune donnée sur les 7 derniers jours</p>
            </div>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
      {/* Volume by metal type */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center justify-between mb-5">
          <div>
            <h3 className="text-sm font-600 text-foreground">Volume traité par métal</h3>
            <p className="text-xs text-muted-foreground mt-0.5">7 derniers jours · m³</p>
          </div>
        </div>
        {volumeData.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[220px] gap-2">
            <Icon name="ChartBarIcon" size={28} className="text-muted-foreground" />
            <p className="text-sm text-muted-foreground">Aucune donnée</p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={volumeData} barSize={10} barGap={2}>
              <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} width={30} />
              <Tooltip content={<CustomTooltip />} />
              <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} />
              {metalKeys.map((metal) => (
                <Bar
                  key={metal}
                  dataKey={metal}
                  name={metal.charAt(0).toUpperCase() + metal.slice(1)}
                  fill={METAL_COLORS[metal] ?? '#6b7280'}
                  radius={[3, 3, 0, 0]}
                />
              ))}
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Daily processed value */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center justify-between mb-5">
          <div>
            <h3 className="text-sm font-600 text-foreground">Valeur traitée par jour</h3>
            <p className="text-xs text-muted-foreground mt-0.5">7 derniers jours · CAD</p>
          </div>
          <div className="text-right">
            <p className="text-lg font-700 tabular-nums text-primary">
              {totalValue > 0 ? `${totalValue.toFixed(0)} $CA` : '—'}
            </p>
            <p className="text-xs text-muted-foreground">Total 7 jours</p>
          </div>
        </div>
        {valueData.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[220px] gap-2">
            <Icon name="ChartBarIcon" size={28} className="text-muted-foreground" />
            <p className="text-sm text-muted-foreground">Aucune donnée</p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={220}>
            <AreaChart data={valueData}>
              <defs>
                <linearGradient id="grad-value" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--primary)" stopOpacity={0.25} />
                  <stop offset="100%" stopColor="var(--primary)" stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="date" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} width={40} />
              <Tooltip content={<ValueTooltip />} />
              <Area
                type="monotone"
                dataKey="valeur"
                stroke="var(--primary)"
                strokeWidth={2}
                fill="url(#grad-value)"
                dot={false}
                activeDot={{ r: 5, fill: 'var(--primary)' }}
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}