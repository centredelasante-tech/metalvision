'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import { EventTypeBadge, type BusinessEvent, type CcfEventType } from '@/components/ObjectTimeline';

// ─── Types ────────────────────────────────────────────────────────────────────

interface Organization {
  id: string;
  name: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const OBJECT_TYPE_LABELS: Record<string, string> = {
  organization:    'Organisation',
  capability:      'Capacité',
  opportunity:     'Opportunité',
  project:         'Projet',
  mandate:         'Mandat',
  document:        'Document',
  logistics_step:  'Étape logistique',
  value_report:    'Rapport de valeur',
};

const OBJECT_TYPES = Object.keys(OBJECT_TYPE_LABELS);

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('fr-CA', { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
}

function truncateId(id: string): string {
  return id.slice(0, 8) + '…';
}

// ─── EventRow ─────────────────────────────────────────────────────────────────

function EventRow({
  event,
  orgMap,
  onFilterByObject,
}: {
  event: BusinessEvent;
  orgMap: Record<string, string>;
  onFilterByObject: (objectType: string, objectId: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const orgName = event.organization_id ? (orgMap[event.organization_id] ?? truncateId(event.organization_id)) : '—';
  const hasPayload = event.payload && Object.keys(event.payload).length > 0;

  return (
    <div className="border border-border rounded-xl bg-card overflow-hidden">
      <div className="flex flex-col sm:flex-row sm:items-center gap-3 px-4 py-3">
        {/* Event type badge */}
        <div className="flex-shrink-0">
          <EventTypeBadge eventType={event.event_type as CcfEventType} />
        </div>

        {/* Object info */}
        <div className="flex-1 min-w-0 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
          <span className="inline-flex items-center gap-1 text-muted-foreground">
            <Icon name="TagIcon" size={13} />
            <span className="font-medium text-foreground">
              {OBJECT_TYPE_LABELS[event.object_type] ?? event.object_type}
            </span>
          </span>
          <button
            type="button"
            onClick={() => onFilterByObject(event.object_type, event.object_id)}
            className="font-mono text-xs text-primary hover:underline truncate max-w-[140px]"
            title={`Filtrer par cet objet : ${event.object_id}`}
          >
            {truncateId(event.object_id)}
          </button>
          <span className="text-muted-foreground text-xs hidden sm:inline">·</span>
          <span className="text-muted-foreground text-xs">{orgName}</span>
        </div>

        {/* Date + expand */}
        <div className="flex items-center gap-3 flex-shrink-0">
          <span className="text-xs text-muted-foreground whitespace-nowrap">
            {formatDate(event.created_at)}&nbsp;{formatTime(event.created_at)}
          </span>
          {hasPayload && (
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="p-1 rounded-md hover:bg-muted transition-colors text-muted-foreground"
              aria-label={expanded ? 'Masquer le payload' : 'Afficher le payload'}
            >
              <Icon name={expanded ? 'ChevronUpIcon' : 'ChevronDownIcon'} size={16} />
            </button>
          )}
        </div>
      </div>

      {/* Payload */}
      {expanded && hasPayload && (
        <div className="border-t border-border bg-muted/40 px-4 py-3">
          <p className="text-xs font-semibold text-muted-foreground mb-1.5 uppercase tracking-wide">Payload</p>
          <pre className="text-xs text-foreground/80 overflow-x-auto max-h-48 whitespace-pre-wrap break-all">
            {JSON.stringify(event.payload, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function EvenementsPage() {
  const [events, setEvents] = useState<BusinessEvent[]>([]);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [orgMap, setOrgMap] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [filterOrgId, setFilterOrgId] = useState<string>('');
  const [filterObjectType, setFilterObjectType] = useState<string>('');
  const [filterObjectId, setFilterObjectId] = useState<string>('');
  const [objectIdInput, setObjectIdInput] = useState<string>('');

  // Pagination
  const [page, setPage] = useState(0);
  const PAGE_SIZE = 50;

  // ── Load user's organizations ──────────────────────────────────────────────
  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(async ({ data: { user } }) => {
      if (!user) return;
      const { data } = await supabase
        .from('organization_members')
        .select('organization_id, organizations(id, name)')
        .eq('user_id', user.id)
        .eq('status', 'active');

      if (data) {
        const orgs: Organization[] = data
          .map((m: { organization_id: string; organizations: { id: string; name: string } | null }) =>
            m.organizations ? { id: m.organizations.id, name: m.organizations.name } : null
          )
          .filter(Boolean) as Organization[];
        setOrganizations(orgs);
        const map: Record<string, string> = {};
        orgs.forEach((o) => { map[o.id] = o.name; });
        setOrgMap(map);
      }
    });
  }, []);

  // ── Fetch events ──────────────────────────────────────────────────────────
  const fetchEvents = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();

    let query = supabase
      .from('business_events')
      .select('*')
      .order('created_at', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (filterOrgId) query = query.eq('organization_id', filterOrgId);
    if (filterObjectType) query = query.eq('object_type', filterObjectType);
    if (filterObjectId) {
      query = query.eq('object_id', filterObjectId);
      if (!filterObjectType) {
        // object_id filter requires object_type for meaningful results, but we allow it alone
      }
    }

    const { data, error: err } = await query;
    if (err) {
      setError(err.message);
    } else {
      setEvents(data ?? []);
    }
    setLoading(false);
  }, [filterOrgId, filterObjectType, filterObjectId, page]);

  useEffect(() => {
    fetchEvents();
  }, [fetchEvents]);

  // Reset page when filters change
  useEffect(() => {
    setPage(0);
  }, [filterOrgId, filterObjectType, filterObjectId]);

  // ── Handlers ──────────────────────────────────────────────────────────────
  function handleFilterByObject(objectType: string, objectId: string) {
    setFilterObjectType(objectType);
    setFilterObjectId(objectId);
    setObjectIdInput(objectId);
    setPage(0);
  }

  function handleObjectIdSearch() {
    setFilterObjectId(objectIdInput.trim());
    setPage(0);
  }

  function handleClearFilters() {
    setFilterOrgId('');
    setFilterObjectType('');
    setFilterObjectId('');
    setObjectIdInput('');
    setPage(0);
  }

  const hasActiveFilters = filterOrgId || filterObjectType || filterObjectId;

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <AppLayout>
      <div className="flex flex-col h-full min-h-0">
        {/* Header */}
        <div className="flex-shrink-0 px-6 pt-6 pb-4 border-b border-border bg-background">
          <div className="flex items-center justify-between gap-4">
            <div>
              <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
                <Icon name="BoltIcon" size={22} className="text-primary" />
                Événements métier
              </h1>
              <p className="text-sm text-muted-foreground mt-0.5">
                Journal d&apos;audit des événements — lecture seule
              </p>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-muted-foreground bg-muted px-2.5 py-1 rounded-full border border-border">
                {loading ? '…' : `${events.length} événement${events.length !== 1 ? 's' : ''}`}
              </span>
              <button
                type="button"
                onClick={fetchEvents}
                disabled={loading}
                className="p-2 rounded-lg hover:bg-muted transition-colors text-muted-foreground disabled:opacity-50"
                aria-label="Rafraîchir"
              >
                <Icon name="ArrowPathIcon" size={16} className={loading ? 'animate-spin' : ''} />
              </button>
            </div>
          </div>

          {/* Filters */}
          <div className="mt-4 flex flex-wrap gap-3 items-end">
            {/* Organisation filter */}
            {organizations.length > 0 && (
              <div className="flex flex-col gap-1">
                <label className="text-xs font-medium text-muted-foreground">Organisation</label>
                <select
                  value={filterOrgId}
                  onChange={(e) => setFilterOrgId(e.target.value)}
                  className="text-sm border border-border rounded-lg px-3 py-2 bg-background text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 min-w-[180px]"
                >
                  <option value="">Toutes les organisations</option>
                  {organizations.map((org) => (
                    <option key={org.id} value={org.id}>{org.name}</option>
                  ))}
                </select>
              </div>
            )}

            {/* Object type filter */}
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-muted-foreground">Type d&apos;objet</label>
              <select
                value={filterObjectType}
                onChange={(e) => setFilterObjectType(e.target.value)}
                className="text-sm border border-border rounded-lg px-3 py-2 bg-background text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 min-w-[160px]"
              >
                <option value="">Tous les types</option>
                {OBJECT_TYPES.map((t) => (
                  <option key={t} value={t}>{OBJECT_TYPE_LABELS[t]}</option>
                ))}
              </select>
            </div>

            {/* Object ID filter */}
            <div className="flex flex-col gap-1">
              <label className="text-xs font-medium text-muted-foreground">ID d&apos;objet spécifique</label>
              <div className="flex gap-1">
                <input
                  type="text"
                  value={objectIdInput}
                  onChange={(e) => setObjectIdInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleObjectIdSearch()}
                  placeholder="UUID de l'objet…"
                  className="text-sm border border-border rounded-lg px-3 py-2 bg-background text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 w-56 font-mono"
                />
                <button
                  type="button"
                  onClick={handleObjectIdSearch}
                  className="px-3 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-medium hover:opacity-90 transition-opacity"
                >
                  <Icon name="MagnifyingGlassIcon" size={15} />
                </button>
              </div>
            </div>

            {/* Clear filters */}
            {hasActiveFilters && (
              <button
                type="button"
                onClick={handleClearFilters}
                className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors px-3 py-2 rounded-lg hover:bg-muted border border-border self-end"
              >
                <Icon name="XMarkIcon" size={15} />
                Effacer les filtres
              </button>
            )}
          </div>

          {/* Active filter chips */}
          {hasActiveFilters && (
            <div className="mt-3 flex flex-wrap gap-2">
              {filterOrgId && (
                <span className="inline-flex items-center gap-1.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-full px-2.5 py-1">
                  <Icon name="BuildingOffice2Icon" size={12} />
                  {orgMap[filterOrgId] ?? truncateId(filterOrgId)}
                  <button type="button" onClick={() => setFilterOrgId('')} className="hover:opacity-70">
                    <Icon name="XMarkIcon" size={11} />
                  </button>
                </span>
              )}
              {filterObjectType && (
                <span className="inline-flex items-center gap-1.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-full px-2.5 py-1">
                  <Icon name="TagIcon" size={12} />
                  {OBJECT_TYPE_LABELS[filterObjectType] ?? filterObjectType}
                  <button type="button" onClick={() => setFilterObjectType('')} className="hover:opacity-70">
                    <Icon name="XMarkIcon" size={11} />
                  </button>
                </span>
              )}
              {filterObjectId && (
                <span className="inline-flex items-center gap-1.5 text-xs bg-primary/10 text-primary border border-primary/20 rounded-full px-2.5 py-1 font-mono">
                  <Icon name="FingerPrintIcon" size={12} />
                  {truncateId(filterObjectId)}
                  <button type="button" onClick={() => { setFilterObjectId(''); setObjectIdInput(''); }} className="hover:opacity-70">
                    <Icon name="XMarkIcon" size={11} />
                  </button>
                </span>
              )}
            </div>
          )}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto px-6 py-4">
          {error && (
            <div className="flex items-center gap-2 p-4 rounded-xl bg-red-50 border border-red-200 text-red-700 text-sm mb-4">
              <Icon name="ExclamationCircleIcon" size={18} />
              <span>Erreur lors du chargement : {error}</span>
            </div>
          )}

          {loading ? (
            <div className="space-y-3">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="h-14 rounded-xl bg-muted animate-pulse" />
              ))}
            </div>
          ) : events.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-3 py-20 text-muted-foreground">
              <Icon name="BoltIcon" size={40} className="opacity-30" />
              <p className="text-base font-medium">Aucun événement trouvé</p>
              {hasActiveFilters && (
                <p className="text-sm">Essayez d&apos;élargir vos filtres.</p>
              )}
            </div>
          ) : (
            <div className="space-y-2">
              {events.map((evt) => (
                <EventRow
                  key={evt.id}
                  event={evt}
                  orgMap={orgMap}
                  onFilterByObject={handleFilterByObject}
                />
              ))}
            </div>
          )}

          {/* Pagination */}
          {!loading && events.length > 0 && (
            <div className="flex items-center justify-between mt-6 pt-4 border-t border-border">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}
                className="flex items-center gap-1.5 text-sm px-3 py-2 rounded-lg border border-border hover:bg-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <Icon name="ChevronLeftIcon" size={15} />
                Précédent
              </button>
              <span className="text-sm text-muted-foreground">
                Page {page + 1}
              </span>
              <button
                type="button"
                onClick={() => setPage((p) => p + 1)}
                disabled={events.length < PAGE_SIZE}
                className="flex items-center gap-1.5 text-sm px-3 py-2 rounded-lg border border-border hover:bg-muted transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                Suivant
                <Icon name="ChevronRightIcon" size={15} />
              </button>
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
