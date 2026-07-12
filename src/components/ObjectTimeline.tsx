'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

export type CcfEventType =
  | 'organization_created' |'organization_suspended' |'member_invited' |'member_activated' |'mandate_issued' |'mandate_accepted' |'mandate_revoked' |'capability_declared' |'capability_qualified' |'opportunity_created' |'opportunity_qualified' |'project_created' |'project_phase_changed' |'document_submitted' |'document_approved' |'document_rejected' |'document_archived' |'logistics_step_updated' |'value_report_generated'
  | string; // fallback for future values

export interface BusinessEvent {
  id: string;
  event_type: CcfEventType;
  object_type: string;
  object_id: string;
  actor_id: string | null;
  organization_id: string | null;
  payload: Record<string, unknown> | null;
  created_at: string;
}

// ─── Event type mapping (extensible, with generic fallback) ──────────────────

interface EventMeta {
  label: string;
  icon: string;
  cls: string;
}

const EVENT_META: Record<string, EventMeta> = {
  organization_created:     { label: 'Organisation créée',          icon: 'BuildingOffice2Icon',      cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  organization_suspended:   { label: 'Organisation suspendue',      icon: 'NoSymbolIcon',             cls: 'text-red-600 bg-red-50 border-red-200' },
  member_invited:           { label: 'Membre invité',               icon: 'UserPlusIcon',             cls: 'text-indigo-700 bg-indigo-50 border-indigo-200' },
  member_activated:         { label: 'Membre activé',               icon: 'UserCircleIcon',           cls: 'text-green-700 bg-green-50 border-green-200' },
  mandate_issued:           { label: 'Mandat émis',                 icon: 'DocumentCheckIcon',        cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  mandate_accepted:         { label: 'Mandat accepté',              icon: 'CheckCircleIcon',          cls: 'text-green-700 bg-green-50 border-green-200' },
  mandate_revoked:          { label: 'Mandat révoqué',              icon: 'XCircleIcon',              cls: 'text-red-600 bg-red-50 border-red-200' },
  capability_declared:      { label: 'Capacité déclarée',           icon: 'CubeIcon',                 cls: 'text-cyan-700 bg-cyan-50 border-cyan-200' },
  capability_qualified:     { label: 'Capacité qualifiée',          icon: 'CheckBadgeIcon',           cls: 'text-teal-700 bg-teal-50 border-teal-200' },
  opportunity_created:      { label: 'Opportunité créée',           icon: 'LightBulbIcon',            cls: 'text-yellow-700 bg-yellow-50 border-yellow-200' },
  opportunity_qualified:    { label: 'Opportunité qualifiée',       icon: 'StarIcon',                 cls: 'text-orange-700 bg-orange-50 border-orange-200' },
  project_created:          { label: 'Projet créé',                 icon: 'FolderPlusIcon',           cls: 'text-violet-700 bg-violet-50 border-violet-200' },
  project_phase_changed:    { label: 'Phase projet modifiée',       icon: 'ArrowPathIcon',            cls: 'text-purple-700 bg-purple-50 border-purple-200' },
  document_submitted:       { label: 'Document soumis',             icon: 'DocumentArrowUpIcon',      cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  document_approved:        { label: 'Document approuvé',           icon: 'DocumentCheckIcon',        cls: 'text-green-700 bg-green-50 border-green-200' },
  document_rejected:        { label: 'Document refusé',             icon: 'DocumentMinusIcon',        cls: 'text-red-600 bg-red-50 border-red-200' },
  document_archived:        { label: 'Document archivé',            icon: 'ArchiveBoxIcon',           cls: 'text-slate-500 bg-slate-100 border-slate-200' },
  logistics_step_updated:   { label: 'Étape logistique mise à jour',icon: 'TruckIcon',                cls: 'text-sky-700 bg-sky-50 border-sky-200' },
  value_report_generated:   { label: 'Rapport de valeur généré',    icon: 'ChartBarIcon',             cls: 'text-emerald-700 bg-emerald-50 border-emerald-200' },
};

const FALLBACK_META: EventMeta = {
  label: '',
  icon: 'BoltIcon',
  cls: 'text-gray-600 bg-gray-100 border-gray-200',
};

function getEventMeta(eventType: CcfEventType): EventMeta {
  return EVENT_META[eventType] ?? { ...FALLBACK_META, label: eventType.replace(/_/g, ' ') };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('fr-CA', { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
}

// ─── EventTypeBadge ───────────────────────────────────────────────────────────

export function EventTypeBadge({ eventType }: { eventType: CcfEventType }) {
  const meta = getEventMeta(eventType);
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2.5 py-1 border ${meta.cls}`}>
      <Icon name={meta.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {meta.label}
    </span>
  );
}

// ─── ObjectTimeline ───────────────────────────────────────────────────────────

interface ObjectTimelineProps {
  object_type: string;
  object_id: string;
  /** Optional: limit number of events shown */
  limit?: number;
  /** Optional: compact mode (no payload display) */
  compact?: boolean;
}

export default function ObjectTimeline({
  object_type,
  object_id,
  limit = 50,
  compact = false,
}: ObjectTimelineProps) {
  const [events, setEvents] = useState<BusinessEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchEvents = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();
    const { data, error: err } = await supabase
      .from('business_events')
      .select('*')
      .eq('object_type', object_type)
      .eq('object_id', object_id)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (err) {
      setError(err.message);
    } else {
      setEvents(data ?? []);
    }
    setLoading(false);
  }, [object_type, object_id, limit]);

  useEffect(() => {
    fetchEvents();
  }, [fetchEvents]);

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-4 text-muted-foreground text-sm">
        <Icon name="ArrowPathIcon" size={16} className="animate-spin" />
        Chargement de l&apos;historique…
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center gap-2 py-4 text-red-600 text-sm">
        <Icon name="ExclamationCircleIcon" size={16} />
        Erreur : {error}
      </div>
    );
  }

  if (events.length === 0) {
    return (
      <div className="flex flex-col items-center gap-2 py-8 text-muted-foreground text-sm">
        <Icon name="ClockIcon" size={24} />
        <span>Aucun événement enregistré pour cet objet.</span>
      </div>
    );
  }

  return (
    <div className="relative">
      {/* Vertical line */}
      <div className="absolute left-4 top-0 bottom-0 w-px bg-border" aria-hidden="true" />

      <ol className="space-y-0">
        {events.map((evt, idx) => {
          const meta = getEventMeta(evt.event_type);
          const isLast = idx === events.length - 1;
          return (
            <li key={evt.id} className={`relative flex gap-4 ${isLast ? '' : 'pb-6'}`}>
              {/* Dot */}
              <div className={`relative z-10 flex-shrink-0 w-8 h-8 rounded-full border-2 flex items-center justify-center ${meta.cls}`}>
                <Icon name={meta.icon as Parameters<typeof Icon>[0]['name']} size={14} />
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0 pt-0.5">
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <EventTypeBadge eventType={evt.event_type} />
                  <span className="text-xs text-muted-foreground">
                    {formatDate(evt.created_at)} à {formatTime(evt.created_at)}
                  </span>
                </div>

                {!compact && evt.payload && Object.keys(evt.payload).length > 0 && (
                  <details className="mt-1">
                    <summary className="text-xs text-muted-foreground cursor-pointer hover:text-foreground transition-colors">
                      Détails du payload
                    </summary>
                    <pre className="mt-1 text-xs bg-muted rounded-md p-2 overflow-x-auto text-foreground/80 max-h-40">
                      {JSON.stringify(evt.payload, null, 2)}
                    </pre>
                  </details>
                )}
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
