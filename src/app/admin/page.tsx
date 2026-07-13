'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import { MetricCardSkeleton, TableRowSkeleton } from '@/components/ui/LoadingSkeleton';

// ─── Types ────────────────────────────────────────────────────────────────────

interface AuditLog {
  id: string;
  actor_id: string | null;
  action: 'INSERT' | 'UPDATE' | 'DELETE';
  table_name: string;
  record_id: string | null;
  created_at: string;
  actor_name?: string | null;
}

interface PlatformStats {
  organizations: number;
  members: number;
  ccfProjects: number;
  auditLogs: number;
  businessEvents: number;
  mandates: number;
}

interface MandateAction {
  code: string;
  label: string;
  description: string | null;
}

// ─── Static Catalogues ────────────────────────────────────────────────────────
// NOTE (revue PR) : mandate_actions est une vraie table seedée en base
// (supabase/migrations/20260710003000_ccf_003_mandates.sql), pas un ENUM —
// contrairement à mandate_scope/logistics_step_type/ccf_event_type ci-dessous.
// Elle est donc interrogée en direct (voir fetchMandateActions plus bas),
// jamais codée en dur : une liste inventée aurait affiché un faux catalogue
// à un admin plateforme qui s'attend à voir les vraies données.

const MANDATE_SCOPES = [
  { code: 'collecte_tri',         label: 'Collecte & tri' },
  { code: 'transport_logistique', label: 'Transport & logistique' },
  { code: 'traitement',           label: 'Traitement' },
  { code: 'certification',        label: 'Certification' },
  { code: 'financement',          label: 'Financement' },
  { code: 'coordination',         label: 'Coordination' },
];

const LOGISTICS_STEP_TYPES = [
  { code: 'ramassage',     label: 'Ramassage' },
  { code: 'chargement',    label: 'Chargement' },
  { code: 'expedition',    label: 'Expédition' },
  { code: 'transit',       label: 'Transit' },
  { code: 'livraison',     label: 'Livraison' },
  { code: 'preuve_finale', label: 'Preuve finale' },
];

const CCF_EVENT_TYPES: [string, string][] = [
  ['project_phase_changed',      "Changement de phase d'un projet CCF"],
  ['logistics_step_updated',     "Mise à jour d'une étape logistique"],
  ['value_report_generated',     "Génération d'un rapport de valeur"],
  ['mandate_accepted',           "Acceptation d'un mandat"],
  ['mandate_declined',           "Refus d'un mandat"],
  ['mandate_revoked',            "Révocation d'un mandat"],
  ['mandate_submitted',          "Soumission d'un mandat"],
  ['project_invitation_accepted',"Acceptation d'une invitation projet"],
  ['project_invitation_declined',"Refus d'une invitation projet"],
  ['document_uploaded',          "Dépôt d'un document"],
  ['document_approved',          "Approbation d'un document"],
  ['document_rejected',          "Rejet d'un document"],
];

const CONNECTORS = [
  {
    name: 'Groupe Robert',
    type: 'Transport',
    status: 'active',
    description: "Intégration API pour la création et le suivi des expéditions.",
    endpoints: ['/api/external/grouperobert/create-shipment', '/api/external/grouperobert/shipment-status'],
  },
  {
    name: 'OpenRouteService',
    type: 'Géolocalisation',
    status: 'active',
    description: "Calcul de distances et d\'itinéraires pour le suivi transport.",
    endpoints: ['/api/transport/calculate-distance'],
  },
  {
    name: 'Supabase Storage',
    type: 'Stockage',
    status: 'active',
    description: "Stockage des documents et preuves logistiques.",
    endpoints: ['Bucket: documents'],
  },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString('fr-CA', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function truncateId(id: string): string {
  return id.slice(0, 8) + '…';
}

const ACTION_COLORS: Record<string, string> = {
  INSERT: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400',
  UPDATE: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
  DELETE: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
};

// ─── Sub-components ───────────────────────────────────────────────────────────

function StatCard({
  label, value, icon, loading,
}: {
  label: string; value: number; icon: string; loading: boolean;
}) {
  if (loading) return <MetricCardSkeleton />;
  return (
    <div className="bg-card border border-border rounded-xl p-5 flex items-center gap-4">
      <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
        <Icon name={icon as Parameters<typeof Icon>[0]['name']} size={20} className="text-primary" />
      </div>
      <div>
        <p className="text-2xl font-700 text-foreground tabular-nums">{value.toLocaleString('fr-CA')}</p>
        <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
      </div>
    </div>
  );
}

function SectionTitle({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="mb-4">
      <h2 className="text-base font-700 text-foreground">{title}</h2>
      {subtitle && <p className="text-sm text-muted-foreground mt-0.5">{subtitle}</p>}
    </div>
  );
}

// ─── Access Denied ────────────────────────────────────────────────────────────

function AccessDenied() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-4 text-center px-4">
      <div className="w-16 h-16 rounded-full bg-destructive/10 flex items-center justify-center">
        <Icon name="ShieldExclamationIcon" size={32} className="text-destructive" />
      </div>
      <h1 className="text-xl font-700 text-foreground">Accès refusé</h1>
      <p className="text-sm text-muted-foreground max-w-sm">
        Cette section est réservée aux super-administrateurs de la plateforme METALTRACE.
        Votre compte ne dispose pas des droits nécessaires.
      </p>
      <p className="text-xs text-muted-foreground">
        Si vous pensez qu&apos;il s&apos;agit d&apos;une erreur, contactez l&apos;équipe technique.
      </p>
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

type TabId = 'overview' | 'audit' | 'catalogues' | 'connectors';

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'overview',   label: "Vue d'ensemble",   icon: 'ChartBarIcon' },
  { id: 'audit',      label: "Journal d'audit",  icon: 'ClipboardDocumentListIcon' },
  { id: 'catalogues', label: 'Catalogues',        icon: 'BookOpenIcon' },
  { id: 'connectors', label: 'Connecteurs',       icon: 'LinkIcon' },
];

const QUICK_LINKS = [
  { href: '/organizations',  label: 'Organisations',  icon: 'BuildingOffice2Icon',       desc: 'Gérer les organisations et membres' },
  { href: '/projets',        label: 'Projets CCF',    icon: 'FolderIcon',                desc: 'Tous les projets de la plateforme' },
  { href: '/mandats',        label: 'Mandats',        icon: 'DocumentCheckIcon',         desc: 'Mandats inter-organisations' },
  { href: '/documents',      label: 'Documents',      icon: 'FolderOpenIcon',            desc: 'Documents et preuves' },
  { href: '/evenements',     label: 'Événements',     icon: 'BoltIcon',                  desc: 'Journal des événements métier' },
  { href: '/cockpit',        label: 'Cockpit',        icon: 'PresentationChartLineIcon', desc: 'Vue direction des projets' },
];

export default function AdminPage() {
  const [accessChecked, setAccessChecked] = useState(false);
  const [isSuperAdmin, setIsSuperAdmin] = useState(false);
  const [stats, setStats] = useState<PlatformStats>({
    organizations: 0, members: 0, ccfProjects: 0,
    auditLogs: 0, businessEvents: 0, mandates: 0,
  });
  const [statsLoading, setStatsLoading] = useState(true);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [auditLoading, setAuditLoading] = useState(true);
  const [auditTableFilter, setAuditTableFilter] = useState('');
  const [auditActionFilter, setAuditActionFilter] = useState('');
  const [activeTab, setActiveTab] = useState<TabId>('overview');
  const [mandateActions, setMandateActions] = useState<MandateAction[]>([]);
  const [mandateActionsLoading, setMandateActionsLoading] = useState(true);

  // ── Access gate ─────────────────────────────────────────────────────────────
  // Probe audit_logs — RLS policy "audit_logs_superadmin_select" uses
  // is_platform_superadmin() as its USING clause. A successful query (no error)
  // confirms the current user satisfies is_platform_superadmin().
  useEffect(() => {
    const supabase = createClient();
    supabase
      .from('audit_logs')
      .select('id', { count: 'exact', head: true })
      .then(({ error }) => {
        setIsSuperAdmin(!error);
        setAccessChecked(true);
      });
  }, []);

  // ── Platform stats ──────────────────────────────────────────────────────────
  const fetchStats = useCallback(async () => {
    if (!isSuperAdmin) return;
    setStatsLoading(true);
    const supabase = createClient();
    const [orgs, members, projects, auditCount, eventsCount, mandates] = await Promise.all([
      supabase.from('organizations').select('id', { count: 'exact', head: true }),
      supabase.from('organization_members').select('id', { count: 'exact', head: true }),
      supabase.from('ccf_projects').select('id', { count: 'exact', head: true }),
      supabase.from('audit_logs').select('id', { count: 'exact', head: true }),
      supabase.from('business_events').select('id', { count: 'exact', head: true }),
      supabase.from('mandates').select('id', { count: 'exact', head: true }),
    ]);
    setStats({
      organizations: orgs.count ?? 0,
      members: members.count ?? 0,
      ccfProjects: projects.count ?? 0,
      auditLogs: auditCount.count ?? 0,
      businessEvents: eventsCount.count ?? 0,
      mandates: mandates.count ?? 0,
    });
    setStatsLoading(false);
  }, [isSuperAdmin]);

  // ── Audit logs ──────────────────────────────────────────────────────────────
  const fetchAuditLogs = useCallback(async () => {
    if (!isSuperAdmin) return;
    setAuditLoading(true);
    const supabase = createClient();
    let query = supabase
      .from('audit_logs')
      .select('id, actor_id, action, table_name, record_id, created_at')
      .order('created_at', { ascending: false })
      .limit(100);
    if (auditTableFilter) query = query.eq('table_name', auditTableFilter);
    if (auditActionFilter) query = query.eq('action', auditActionFilter);
    const { data } = await query;
    const logs = (data as AuditLog[]) ?? [];

    // Résoudre le nom de l'acteur via profiles (profiles_superadmin_select,
    // voir ADR-MVP.md §9unvicies — sans cette policy la jointure échouerait
    // silencieusement pour tout acteur hors organisation du superadmin).
    const actorIds = [...new Set(logs.map((l) => l.actor_id).filter((id): id is string => !!id))];
    if (actorIds.length > 0) {
      const { data: profilesData } = await supabase
        .from('profiles')
        .select('id, full_name, email')
        .in('id', actorIds);
      const nameById = new Map(
        ((profilesData as { id: string; full_name: string | null; email: string }[]) ?? []).map(
          (p) => [p.id, p.full_name || p.email || null]
        )
      );
      logs.forEach((l) => {
        l.actor_name = l.actor_id ? nameById.get(l.actor_id) ?? null : null;
      });
    }

    setAuditLogs(logs);
    setAuditLoading(false);
  }, [isSuperAdmin, auditTableFilter, auditActionFilter]);

  useEffect(() => {
    if (isSuperAdmin) fetchStats();
  }, [isSuperAdmin, fetchStats]);

  useEffect(() => {
    if (isSuperAdmin && activeTab === 'audit') fetchAuditLogs();
  }, [isSuperAdmin, activeTab, fetchAuditLogs]);

  // ── Mandate actions catalogue (table réelle, pas un ENUM) ────────────────────
  const fetchMandateActions = useCallback(async () => {
    if (!isSuperAdmin) return;
    setMandateActionsLoading(true);
    const supabase = createClient();
    const { data } = await supabase
      .from('mandate_actions')
      .select('code, label, description')
      .order('code');
    setMandateActions((data as MandateAction[]) ?? []);
    setMandateActionsLoading(false);
  }, [isSuperAdmin]);

  useEffect(() => {
    if (isSuperAdmin) fetchMandateActions();
  }, [isSuperAdmin, fetchMandateActions]);

  // ── Render ──────────────────────────────────────────────────────────────────

  if (!accessChecked) {
    return (
      <AppLayout activeRoute="/admin">
        <div className="flex items-center justify-center min-h-[60vh]">
          <div className="flex flex-col items-center gap-3">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            <p className="text-sm text-muted-foreground">Vérification des droits d&apos;accès…</p>
          </div>
        </div>
      </AppLayout>
    );
  }

  if (!isSuperAdmin) {
    return (
      <AppLayout activeRoute="/admin">
        <AccessDenied />
      </AppLayout>
    );
  }

  return (
    <AppLayout activeRoute="/admin">
      <div className="max-w-7xl mx-auto px-4 py-6 space-y-6">

        {/* Header */}
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-primary flex items-center justify-center flex-shrink-0">
            <Icon name="ShieldCheckIcon" size={20} className="text-primary-foreground" />
          </div>
          <div>
            <h1 className="text-xl font-700 text-foreground">Administration plateforme</h1>
            <p className="text-sm text-muted-foreground">Supervision globale METALTRACE — accès super-administrateur</p>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 border-b border-border overflow-x-auto">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors -mb-px whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
              }`}
            >
              <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={15} />
              {tab.label}
            </button>
          ))}
        </div>

        {/* ── Overview ──────────────────────────────────────────────────────── */}
        {activeTab === 'overview' && (
          <div className="space-y-6">
            <SectionTitle
              title="Statistiques globales"
              subtitle="Données en temps réel — toutes organisations confondues"
            />
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              <StatCard label="Organisations"     value={stats.organizations}  icon="BuildingOffice2Icon"       loading={statsLoading} />
              <StatCard label="Membres"           value={stats.members}        icon="UsersIcon"                 loading={statsLoading} />
              <StatCard label="Projets CCF"       value={stats.ccfProjects}    icon="FolderIcon"                loading={statsLoading} />
              <StatCard label="Mandats"           value={stats.mandates}       icon="DocumentCheckIcon"         loading={statsLoading} />
              <StatCard label="Événements métier" value={stats.businessEvents} icon="BoltIcon"                  loading={statsLoading} />
              <StatCard label="Entrées d'audit"   value={stats.auditLogs}      icon="ClipboardDocumentListIcon" loading={statsLoading} />
            </div>

            <div>
              <SectionTitle title="Accès rapide" />
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                {QUICK_LINKS.map((link) => (
                  <a
                    key={link.href}
                    href={link.href}
                    className="flex items-center gap-3 p-4 bg-card border border-border rounded-xl hover:border-primary/50 hover:bg-accent/30 transition-colors group"
                  >
                    <div className="w-9 h-9 rounded-lg bg-muted flex items-center justify-center flex-shrink-0 group-hover:bg-primary/10 transition-colors">
                      <Icon
                        name={link.icon as Parameters<typeof Icon>[0]['name']}
                        size={18}
                        className="text-muted-foreground group-hover:text-primary transition-colors"
                      />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-600 text-foreground">{link.label}</p>
                      <p className="text-xs text-muted-foreground truncate">{link.desc}</p>
                    </div>
                    <Icon name="ChevronRightIcon" size={14} className="text-muted-foreground ml-auto flex-shrink-0" />
                  </a>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* ── Audit Logs ────────────────────────────────────────────────────── */}
        {activeTab === 'audit' && (
          <div className="space-y-4">
            <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
              <SectionTitle
                title="Journal d'audit technique"
                subtitle="Opérations CRUD enregistrées automatiquement par les triggers PostgreSQL"
              />
              <button
                onClick={fetchAuditLogs}
                className="flex items-center gap-2 px-3 py-1.5 text-sm border border-border rounded-lg hover:bg-accent transition-colors flex-shrink-0"
              >
                <Icon name="ArrowPathIcon" size={14} />
                Actualiser
              </button>
            </div>

            <div className="flex flex-wrap gap-3">
              <select
                value={auditTableFilter}
                onChange={(e) => setAuditTableFilter(e.target.value)}
                className="text-sm border border-border rounded-lg px-3 py-1.5 bg-background text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option value="">Toutes les tables</option>
                {[
                  'organizations', 'organization_members', 'ccf_projects',
                  'project_participants', 'mandates', 'documents',
                  'logistics_steps', 'value_reports', 'capabilities',
                  'opportunities', 'business_events',
                ].map((t) => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>
              <select
                value={auditActionFilter}
                onChange={(e) => setAuditActionFilter(e.target.value)}
                className="text-sm border border-border rounded-lg px-3 py-1.5 bg-background text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                <option value="">Toutes les actions</option>
                <option value="INSERT">INSERT</option>
                <option value="UPDATE">UPDATE</option>
                <option value="DELETE">DELETE</option>
              </select>
            </div>

            <div className="bg-card border border-border rounded-xl overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border bg-muted/40">
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Horodatage</th>
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Action</th>
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Table</th>
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Enregistrement</th>
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Acteur</th>
                    </tr>
                  </thead>
                  <tbody>
                    {auditLoading ? (
                      Array.from({ length: 8 }).map((_, i) => <TableRowSkeleton key={i} cols={5} />)
                    ) : auditLogs.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="px-4 py-12 text-center text-muted-foreground text-sm">
                          Aucune entrée d&apos;audit trouvée
                        </td>
                      </tr>
                    ) : (
                      auditLogs.map((log) => (
                        <tr key={log.id} className="border-b border-border last:border-0 hover:bg-muted/30 transition-colors">
                          <td className="px-4 py-3 text-xs text-muted-foreground whitespace-nowrap">
                            {formatDateTime(log.created_at)}
                          </td>
                          <td className="px-4 py-3">
                            <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-600 ${ACTION_COLORS[log.action] ?? ''}`}>
                              {log.action}
                            </span>
                          </td>
                          <td className="px-4 py-3">
                            <code className="text-xs bg-muted px-1.5 py-0.5 rounded font-mono text-foreground">
                              {log.table_name}
                            </code>
                          </td>
                          <td className="px-4 py-3 text-xs text-muted-foreground font-mono">
                            {log.record_id ? truncateId(log.record_id) : '—'}
                          </td>
                          <td className="px-4 py-3 text-xs text-muted-foreground">
                            {log.actor_id ? (
                              <span className={log.actor_name ? '' : 'font-mono'}>
                                {log.actor_name ?? truncateId(log.actor_id)}
                              </span>
                            ) : (
                              <span className="italic">système</span>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
              {!auditLoading && auditLogs.length === 100 && (
                <div className="px-4 py-2 border-t border-border bg-muted/20 text-xs text-muted-foreground text-center">
                  Affichage limité aux 100 entrées les plus récentes
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── Catalogues ────────────────────────────────────────────────────── */}
        {activeTab === 'catalogues' && (
          <div className="space-y-8">

            {/* Mandate Actions */}
            <div>
              <SectionTitle
                title="Actions de mandat (mandate_actions)"
                subtitle="Table mandate_actions — actions autorisées dans les mandats inter-organisations"
              />
              <div className="bg-card border border-border rounded-xl overflow-hidden">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border bg-muted/40">
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide w-40">Code</th>
                      <th className="text-left px-4 py-3 text-xs font-600 text-muted-foreground uppercase tracking-wide">Libellé</th>
                    </tr>
                  </thead>
                  <tbody>
                    {mandateActionsLoading ? (
                      Array.from({ length: 5 }).map((_, i) => <TableRowSkeleton key={i} cols={2} />)
                    ) : mandateActions.length === 0 ? (
                      <tr>
                        <td colSpan={2} className="px-4 py-8 text-center text-muted-foreground text-sm">
                          Aucune action de mandat trouvée.
                        </td>
                      </tr>
                    ) : (
                      mandateActions.map((a) => (
                        <tr key={a.code} className="border-b border-border last:border-0 hover:bg-muted/20">
                          <td className="px-4 py-3">
                            <code className="text-xs bg-muted px-1.5 py-0.5 rounded font-mono text-foreground">{a.code}</code>
                          </td>
                          <td className="px-4 py-3 text-sm text-foreground">{a.label}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Mandate Scopes */}
            <div>
              <SectionTitle
                title="Portées de mandat (mandate_scope)"
                subtitle="ENUM Postgres — valeurs fixes, non modifiables sans migration"
              />
              <div className="flex flex-wrap gap-2">
                {MANDATE_SCOPES.map((s) => (
                  <div key={s.code} className="flex items-center gap-2 px-3 py-2 bg-card border border-border rounded-lg">
                    <code className="text-xs font-mono text-muted-foreground">{s.code}</code>
                    <span className="text-xs text-border">·</span>
                    <span className="text-sm text-foreground">{s.label}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Logistics Step Types */}
            <div>
              <SectionTitle
                title="Types d'étapes logistiques (logistics_step_type)"
                subtitle="ENUM Postgres — séquence standard d'une chaîne logistique CCF"
              />
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                {LOGISTICS_STEP_TYPES.map((s, idx) => (
                  <div key={s.code} className="flex items-center gap-3 p-3 bg-card border border-border rounded-xl">
                    <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
                      <span className="text-xs font-700 text-primary">{idx + 1}</span>
                    </div>
                    <div>
                      <p className="text-sm font-600 text-foreground">{s.label}</p>
                      <code className="text-xs text-muted-foreground font-mono">{s.code}</code>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* CCF Event Types */}
            <div>
              <SectionTitle
                title="Types d'événements métier (ccf_event_type)"
                subtitle="ENUM Postgres — événements émis par le code applicatif dans business_events"
              />
              <div className="bg-card border border-border rounded-xl overflow-hidden">
                <div className="grid grid-cols-1 sm:grid-cols-2 divide-y sm:divide-y-0 divide-border">
                  {CCF_EVENT_TYPES.map(([code, label]) => (
                    <div key={code} className="flex items-start gap-3 px-4 py-3 hover:bg-muted/20 transition-colors border-b border-border last:border-0">
                      <div className="w-1.5 h-1.5 rounded-full bg-primary mt-1.5 flex-shrink-0" />
                      <div>
                        <code className="text-xs font-mono text-muted-foreground">{code}</code>
                        <p className="text-xs text-foreground mt-0.5">{label}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

          </div>
        )}

        {/* ── Connectors ────────────────────────────────────────────────────── */}
        {activeTab === 'connectors' && (
          <div className="space-y-4">
            <SectionTitle
              title="Connecteurs externes"
              subtitle="Intégrations tierces actives sur la plateforme METALTRACE"
            />
            <div className="grid grid-cols-1 gap-4">
              {CONNECTORS.map((connector) => (
                <div key={connector.name} className="bg-card border border-border rounded-xl p-5">
                  <div className="flex items-start justify-between gap-4 mb-3">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
                        <Icon name="LinkIcon" size={18} className="text-primary" />
                      </div>
                      <div>
                        <h3 className="text-sm font-700 text-foreground">{connector.name}</h3>
                        <p className="text-xs text-muted-foreground">{connector.type}</p>
                      </div>
                    </div>
                    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-600 flex-shrink-0 ${
                      connector.status === 'active' ?'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400' :'bg-muted text-muted-foreground'
                    }`}>
                      <span className={`w-1.5 h-1.5 rounded-full ${connector.status === 'active' ? 'bg-green-500' : 'bg-muted-foreground'}`} />
                      {connector.status === 'active' ? 'Actif' : 'Inactif'}
                    </span>
                  </div>
                  <p className="text-sm text-muted-foreground mb-3">{connector.description}</p>
                  <div className="flex flex-wrap gap-2">
                    {connector.endpoints.map((ep) => (
                      <code key={ep} className="text-xs bg-muted px-2 py-1 rounded font-mono text-foreground">
                        {ep}
                      </code>
                    ))}
                  </div>
                </div>
              ))}
            </div>

            <div className="flex items-start gap-3 p-4 bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800 rounded-xl">
              <Icon name="InformationCircleIcon" size={18} className="text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-600 text-amber-800 dark:text-amber-300">Configuration des connecteurs</p>
                <p className="text-xs text-amber-700 dark:text-amber-400 mt-1">
                  Les clés API et paramètres de connexion sont gérés via les variables d&apos;environnement du serveur.
                  Aucune clé n&apos;est exposée dans cette interface.
                </p>
              </div>
            </div>
          </div>
        )}

      </div>
    </AppLayout>
  );
}
