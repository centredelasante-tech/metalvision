'use client';
import React, { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import MetricCard from '@/components/ui/MetricCard';
import { EventTypeBadge } from '@/components/ObjectTimeline';
import type { BusinessEvent } from '@/components/ObjectTimeline';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

interface CcfProject {
  id: string;
  phase: string;
  target_end_date: string | null;
  opportunity_id: string | null;
}

interface CcfDocument {
  id: string;
  title: string | null;
  status: string;
  created_at: string;
  object_type: string | null;
  object_id: string | null;
}

interface AlertItem {
  id: string;
  label: string;
  severity: 'high' | 'medium';
  href: string;
  icon: string;
}

interface LogisticsStep {
  id: string;
  status: string;
  project_id: string;
}

interface Mandate {
  id: string;
  end_date: string | null;
  status: string;
}

// ─── Phase badge ──────────────────────────────────────────────────────────────

const PHASE_CONFIG: Record<string, { label: string; cls: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200' },
  active:    { label: 'Actif',      cls: 'text-green-700 bg-green-50 border-green-200' },
  execution: { label: 'Exécution',  cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  review:    { label: 'Révision',   cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  closed:    { label: 'Clôturé',    cls: 'text-slate-500 bg-slate-100 border-slate-200' },
};

function PhaseBadge({ phase }: { phase: string }) {
  const cfg = PHASE_CONFIG[phase] ?? { label: phase, cls: 'text-gray-600 bg-gray-100 border-gray-200' };
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2.5 py-0.5 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDateShort(iso: string): string {
  return new Date(iso).toLocaleDateString('fr-CA', { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatTimeShort(iso: string): string {
  return new Date(iso).toLocaleTimeString('fr-CA', { hour: '2-digit', minute: '2-digit' });
}

// ─── Section header ───────────────────────────────────────────────────────────

function SectionHeader({ title, icon, href, linkLabel }: { title: string; icon: string; href?: string; linkLabel?: string }) {
  return (
    <div className="flex items-center justify-between mb-4">
      <div className="flex items-center gap-2">
        <Icon name={icon as Parameters<typeof Icon>[0]['name']} size={18} className="text-primary" />
        <h2 className="text-base font-600 text-foreground">{title}</h2>
      </div>
      {href && linkLabel && (
        <Link href={href} className="text-xs text-primary hover:underline font-500 flex items-center gap-1">
          {linkLabel}
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      )}
    </div>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────

export default function CCFDashboardSection() {
  // KPI counts
  const [activeProjectsCount, setActiveProjectsCount] = useState<number | null>(null);
  const [pendingDocsCount, setPendingDocsCount] = useState<number | null>(null);
  const [pendingMandatesCount, setPendingMandatesCount] = useState<number | null>(null);
  const [recentEventsCount, setRecentEventsCount] = useState<number | null>(null);

  // Lists
  const [activeProjects, setActiveProjects] = useState<CcfProject[]>([]);
  const [incompleteDocs, setIncompleteDocs] = useState<CcfDocument[]>([]);
  const [recentEvents, setRecentEvents] = useState<BusinessEvent[]>([]);
  const [alerts, setAlerts] = useState<AlertItem[]>([]);

  const [loading, setLoading] = useState(true);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    try {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) return;

      const now = new Date();
      const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
      const fourteenDaysFromNow = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000).toISOString();

      // ── KPI: active projects count ──
      const { count: projCount } = await supabase
        .from('ccf_projects')
        .select('*', { count: 'exact', head: true })
        .neq('phase', 'closed');
      setActiveProjectsCount(projCount ?? 0);

      // ── KPI: pending documents count ──
      const { count: docCount } = await supabase
        .from('documents')
        .select('*', { count: 'exact', head: true })
        .in('status', ['draft', 'submitted']);
      setPendingDocsCount(docCount ?? 0);

      // ── KPI: pending mandates count ──
      const { count: mandateCount } = await supabase
        .from('mandates')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'pending_acceptance');
      setPendingMandatesCount(mandateCount ?? 0);

      // ── KPI: events last 7 days ──
      const { count: evtCount } = await supabase
        .from('business_events')
        .select('*', { count: 'exact', head: true })
        .gte('created_at', sevenDaysAgo);
      setRecentEventsCount(evtCount ?? 0);

      // ── Active projects list (sorted by target_end_date) ──
      const { data: projList } = await supabase
        .from('ccf_projects')
        .select('id, phase, target_end_date, opportunity_id')
        .neq('phase', 'closed')
        .order('target_end_date', { ascending: true, nullsFirst: false });
      setActiveProjects(projList ?? []);

      // ── Incomplete documents list ──
      const { data: docList } = await supabase
        .from('documents')
        .select('id, title, status, created_at, object_type, object_id')
        .in('status', ['draft', 'submitted'])
        .order('created_at', { ascending: false })
        .limit(10);
      setIncompleteDocs(docList ?? []);

      // ── Recent events list (all objects, RLS-filtered) ──
      const { data: evtList } = await supabase
        .from('business_events')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(10);
      setRecentEvents(evtList ?? []);

      // ── Alerts ──
      const alertItems: AlertItem[] = [];

      // 1. Blocked logistics steps (across all visible projects)
      const { data: blockedSteps } = await supabase
        .from('logistics_steps')
        .select('id, status, project_id')
        .eq('status', 'blocked');
      if (blockedSteps && blockedSteps.length > 0) {
        const uniqueProjects = [...new Set((blockedSteps as LogisticsStep[]).map((s) => s.project_id))];
        uniqueProjects.forEach((projectId) => {
          const count = (blockedSteps as LogisticsStep[]).filter((s) => s.project_id === projectId).length;
          alertItems.push({
            id: `blocked-${projectId}`,
            label: `${count} étape${count > 1 ? 's' : ''} logistique${count > 1 ? 's' : ''} bloquée${count > 1 ? 's' : ''} sur ce projet`,
            severity: 'high',
            href: `/projets/${projectId}`,
            icon: 'ExclamationTriangleIcon',
          });
        });
      }

      // 2. Overdue projects (target_end_date passed, phase != closed)
      const { data: overdueProjects } = await supabase
        .from('ccf_projects')
        .select('id, target_end_date, phase')
        .neq('phase', 'closed')
        .lt('target_end_date', now.toISOString())
        .not('target_end_date', 'is', null);
      if (overdueProjects && overdueProjects.length > 0) {
        (overdueProjects as CcfProject[]).forEach((p) => {
          alertItems.push({
            id: `overdue-${p.id}`,
            label: `Projet en retard — date cible dépassée (${formatDateShort(p.target_end_date!)})`,
            severity: 'high',
            href: `/projets/${p.id}`,
            icon: 'ClockIcon',
          });
        });
      }

      // 3. Rejected documents last 7 days
      const { data: rejectedDocs } = await supabase
        .from('documents')
        .select('id, title')
        .eq('status', 'rejected')
        .gte('updated_at', sevenDaysAgo);
      if (rejectedDocs && rejectedDocs.length > 0) {
        alertItems.push({
          id: 'rejected-docs',
          label: `${rejectedDocs.length} document${rejectedDocs.length > 1 ? 's' : ''} refusé${rejectedDocs.length > 1 ? 's' : ''} ces 7 derniers jours`,
          severity: 'medium',
          href: '/documents',
          icon: 'DocumentMinusIcon',
        });
      }

      // 4. Active mandates expiring within 14 days
      const { data: expiringMandates } = await supabase
        .from('mandates')
        .select('id, end_date, status')
        .eq('status', 'active')
        .not('end_date', 'is', null)
        .lte('end_date', fourteenDaysFromNow)
        .gte('end_date', now.toISOString());
      if (expiringMandates && expiringMandates.length > 0) {
        (expiringMandates as Mandate[]).forEach((m) => {
          alertItems.push({
            id: `expiring-mandate-${m.id}`,
            label: `Mandat actif expirant le ${formatDateShort(m.end_date!)} (dans moins de 14 jours)`,
            severity: 'medium',
            href: '/mandats',
            icon: 'ExclamationCircleIcon',
          });
        });
      }

      setAlerts(alertItems);
    } catch (err) {
      // Ne jamais laisser une erreur non gérée bloquer indéfiniment l'état de
      // chargement — voir INC-S01-01 (ADR-MVP.md) : l'absence de try/catch/finally
      // ici, combinée à un bug distinct (useAuth() jamais fourni par un
      // AuthProvider monté), laissait cette section bloquée sur "…" en
      // permanence, sans aucune requête réseau ni erreur visible en console.
      console.error('CCFDashboardSection: échec du chargement', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  const kpiLoading = loading;

  return (
    <div className="space-y-6 pt-2">
      {/* Divider */}
      <div className="flex items-center gap-3">
        <div className="flex-1 h-px bg-border" />
        <span className="text-xs font-600 text-muted-foreground uppercase tracking-widest px-2">
          MetalTrace CCF
        </span>
        <div className="flex-1 h-px bg-border" />
      </div>

      {/* ── KPI Cards ── */}
      <div className="grid grid-cols-2 xl:grid-cols-4 gap-4">
        <MetricCard
          label="Projets actifs"
          value={kpiLoading ? '…' : String(activeProjectsCount ?? 0)}
          icon="FolderOpenIcon"
          variant="default"
        />
        <MetricCard
          label="Documents en attente"
          value={kpiLoading ? '…' : String(pendingDocsCount ?? 0)}
          icon="DocumentTextIcon"
          variant={pendingDocsCount && pendingDocsCount > 0 ? 'accent' : 'default'}
        />
        <MetricCard
          label="Mandats en attente"
          value={kpiLoading ? '…' : String(pendingMandatesCount ?? 0)}
          icon="ClipboardDocumentCheckIcon"
          variant={pendingMandatesCount && pendingMandatesCount > 0 ? 'accent' : 'default'}
        />
        <MetricCard
          label="Événements (7 j)"
          value={kpiLoading ? '…' : String(recentEventsCount ?? 0)}
          icon="BoltIcon"
          variant="default"
        />
      </div>

      {/* ── Alerts ── */}
      {!loading && alerts.length > 0 && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4">
          <div className="flex items-center gap-2 mb-3">
            <Icon name="ExclamationTriangleIcon" size={16} className="text-red-600" />
            <h2 className="text-sm font-600 text-red-700">
              {alerts.length} alerte{alerts.length > 1 ? 's' : ''} en cours
            </h2>
          </div>
          <ul className="space-y-2">
            {alerts.map((alert) => (
              <li key={alert.id}>
                <Link
                  href={alert.href}
                  className={`flex items-start gap-2 text-sm rounded-lg px-3 py-2 transition-colors hover:bg-white/60 ${
                    alert.severity === 'high' ?'text-red-700' :'text-amber-700'
                  }`}
                >
                  <Icon
                    name={alert.icon as Parameters<typeof Icon>[0]['name']}
                    size={14}
                    className={`mt-0.5 flex-shrink-0 ${alert.severity === 'high' ? 'text-red-500' : 'text-amber-500'}`}
                  />
                  <span>{alert.label}</span>
                  <Icon name="ArrowRightIcon" size={12} className="ml-auto mt-0.5 flex-shrink-0 opacity-50" />
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* ── Two-column: Active Projects + Incomplete Documents ── */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {/* Active Projects */}
        <div className="rounded-xl border border-border bg-card p-5">
          <SectionHeader
            title="Projets actifs"
            icon="FolderOpenIcon"
            href="/projets"
            linkLabel="Tous les projets"
          />
          {loading ? (
            <div className="flex items-center gap-2 py-4 text-muted-foreground text-sm">
              <Icon name="ArrowPathIcon" size={14} className="animate-spin" />
              Chargement…
            </div>
          ) : activeProjects.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">Aucun projet actif.</p>
          ) : (
            <ul className="space-y-2">
              {activeProjects.map((p) => (
                <li key={p.id}>
                  <Link
                    href={`/projets/${p.id}`}
                    className="flex items-center justify-between gap-3 rounded-lg px-3 py-2 hover:bg-muted/50 transition-colors group"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <Icon name="FolderIcon" size={14} className="text-muted-foreground flex-shrink-0" />
                      <span className="text-sm font-500 text-foreground truncate group-hover:text-primary transition-colors">
                        Projet {p.id.slice(0, 8)}…
                      </span>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <PhaseBadge phase={p.phase} />
                      {p.target_end_date && (
                        <span className="text-xs text-muted-foreground hidden sm:inline">
                          {formatDateShort(p.target_end_date)}
                        </span>
                      )}
                      <Icon name="ArrowRightIcon" size={12} className="text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Incomplete Documents */}
        <div className="rounded-xl border border-border bg-card p-5">
          <SectionHeader
            title="Documents incomplets"
            icon="DocumentTextIcon"
            href="/documents"
            linkLabel="Tous les documents"
          />
          {loading ? (
            <div className="flex items-center gap-2 py-4 text-muted-foreground text-sm">
              <Icon name="ArrowPathIcon" size={14} className="animate-spin" />
              Chargement…
            </div>
          ) : incompleteDocs.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">Aucun document en attente.</p>
          ) : (
            <ul className="space-y-2">
              {incompleteDocs.map((doc) => (
                <li key={doc.id}>
                  <Link
                    href="/documents"
                    className="flex items-center justify-between gap-3 rounded-lg px-3 py-2 hover:bg-muted/50 transition-colors group"
                  >
                    <div className="flex items-center gap-2 min-w-0">
                      <Icon name="DocumentTextIcon" size={14} className="text-muted-foreground flex-shrink-0" />
                      <span className="text-sm font-500 text-foreground truncate group-hover:text-primary transition-colors">
                        {doc.title ?? `Document ${doc.id.slice(0, 8)}…`}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2.5 py-0.5 border ${
                        doc.status === 'draft' ?'text-gray-600 bg-gray-100 border-gray-200' :'text-amber-700 bg-amber-50 border-amber-200'
                      }`}>
                        {doc.status === 'draft' ? 'Brouillon' : 'Soumis'}
                      </span>
                      <Icon name="ArrowRightIcon" size={12} className="text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* ── Recent Events ── */}
      <div className="rounded-xl border border-border bg-card p-5">
        <SectionHeader
          title="Événements récents"
          icon="BoltIcon"
          href="/evenements"
          linkLabel="Journal complet"
        />
        {loading ? (
          <div className="flex items-center gap-2 py-4 text-muted-foreground text-sm">
            <Icon name="ArrowPathIcon" size={14} className="animate-spin" />
            Chargement…
          </div>
        ) : recentEvents.length === 0 ? (
          <p className="text-sm text-muted-foreground py-4 text-center">Aucun événement récent.</p>
        ) : (
          <ul className="divide-y divide-border">
            {recentEvents.map((evt) => (
              <li key={evt.id} className="flex flex-wrap items-center gap-3 py-2.5">
                <EventTypeBadge eventType={evt.event_type} />
                <span className="text-xs text-muted-foreground ml-auto">
                  {formatDateShort(evt.created_at)} à {formatTimeShort(evt.created_at)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
