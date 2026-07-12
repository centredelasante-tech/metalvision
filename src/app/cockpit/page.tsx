'use client';
import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import { computeProjectRisks, RiskItem } from '@/lib/projectRisks';

// ─── Types ────────────────────────────────────────────────────────────────────

type ProjectPhase = 'draft' | 'active' | 'execution' | 'review' | 'closed';
type ProjectStatus = 'draft' | 'active' | 'paused' | 'closed' | 'archived';

interface Organization {
  id: string;
  name: string;
}

interface CcfProject {
  id: string;
  opportunity_id: string;
  coordinator_org_id: string;
  phase: ProjectPhase;
  status: ProjectStatus;
  start_date: string | null;
  target_end_date: string | null;
  created_at: string;
  coordinator_org?: { name: string } | null;
  opportunity?: { title: string } | null;
}

interface LogisticsStep {
  id: string;
  project_id: string;
  status: string;
}

interface ProjectParticipant {
  id: string;
  project_id: string;
  status: string;
}

interface ValueReport {
  id: string;
  project_id: string;
  volume: number | null;
  coordination_value: number | null;
  notes: string | null;
  status: string;
  created_at: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const PHASE_CONFIG: Record<ProjectPhase, { label: string; cls: string; icon: string; progress: number }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200',    icon: 'DocumentIcon',           progress: 0 },
  active:    { label: 'Actif',      cls: 'text-green-700 bg-green-50 border-green-200',  icon: 'PlayIcon',               progress: 25 },
  execution: { label: 'Exécution',  cls: 'text-blue-700 bg-blue-50 border-blue-200',     icon: 'CogIcon',                progress: 50 },
  review:    { label: 'Révision',   cls: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'MagnifyingGlassIcon',    progress: 75 },
  closed:    { label: 'Clôturé',    cls: 'text-slate-500 bg-slate-100 border-slate-200', icon: 'CheckCircleIcon',        progress: 100 },
};

// ─── Sub-components ───────────────────────────────────────────────────────────

function PhaseBadge({ phase }: { phase: ProjectPhase }) {
  const cfg = PHASE_CONFIG[phase] ?? PHASE_CONFIG.draft;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2.5 py-1 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

function ProgressBar({ phase }: { phase: ProjectPhase }) {
  const cfg = PHASE_CONFIG[phase] ?? PHASE_CONFIG.draft;
  const pct = cfg.progress;
  const barColor =
    pct === 100 ? 'bg-slate-400' :
    pct >= 75   ? 'bg-amber-500' :
    pct >= 50   ? 'bg-blue-500'  :
    pct >= 25   ? 'bg-green-500': 'bg-gray-300';

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <span>Avancement</span>
        <span className="font-semibold text-foreground">{pct} %</span>
      </div>
      <div className="h-2.5 w-full bg-muted rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${barColor}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <div className="flex justify-between text-[10px] text-muted-foreground">
        {(['draft', 'active', 'execution', 'review', 'closed'] as ProjectPhase[]).map((p) => (
          <span key={p} className={phase === p ? 'font-semibold text-foreground' : ''}>
            {PHASE_CONFIG[p].label}
          </span>
        ))}
      </div>
    </div>
  );
}

function RiskBadge({ severity }: { severity: RiskItem['severity'] }) {
  const cls =
    severity === 'high'   ? 'text-red-700 bg-red-50 border-red-200' :
    severity === 'medium'? 'text-amber-700 bg-amber-50 border-amber-200' : 'text-blue-700 bg-blue-50 border-blue-200';
  const label = severity === 'high' ? 'Élevé' : severity === 'medium' ? 'Moyen' : 'Faible';
  return (
    <span className={`inline-flex items-center rounded-full text-[10px] font-semibold px-2 py-0.5 border ${cls}`}>
      {label}
    </span>
  );
}

// ─── Direction summary text ───────────────────────────────────────────────────

function buildSummaryText(
  project: CcfProject,
  latestReport: ValueReport | null,
  risks: RiskItem[],
): string {
  const phaseCfg = PHASE_CONFIG[project.phase] ?? PHASE_CONFIG.draft;
  const pct = phaseCfg.progress;
  const phaseLabel = phaseCfg.label.toLowerCase();

  const parts: string[] = [];
  parts.push(`Projet en phase ${phaseLabel} (${pct} % d'avancement)`);

  if (latestReport) {
    if (latestReport.volume != null) {
      parts.push(`${latestReport.volume.toLocaleString('fr-CA')} t traitées`);
    }
    if (latestReport.coordination_value != null) {
      parts.push(`valeur de coordination : ${latestReport.coordination_value.toLocaleString('fr-CA')} $`);
    }
  }

  if (risks.length === 0) {
    parts.push('aucun risque détecté');
  } else {
    const highCount = risks.filter((r) => r.severity === 'high').length;
    const medCount  = risks.filter((r) => r.severity === 'medium').length;
    const riskParts: string[] = [];
    if (highCount > 0) riskParts.push(`${highCount} risque${highCount > 1 ? 's' : ''} élevé${highCount > 1 ? 's' : ''}`);
    if (medCount > 0)  riskParts.push(`${medCount} risque${medCount > 1 ? 's' : ''} moyen${medCount > 1 ? 's' : ''}`);
    parts.push(riskParts.join(', '));
  }

  return parts.join(' · ') + '.';
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function CockpitPage() {
  const supabase = createClient();

  // Coordinator projects
  const [coordinatorProjects, setCoordinatorProjects] = useState<CcfProject[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState<string>('');

  // Project data
  const [project, setProject] = useState<CcfProject | null>(null);
  const [logisticsSteps, setLogisticsSteps] = useState<LogisticsStep[]>([]);
  const [participants, setParticipants] = useState<ProjectParticipant[]>([]);
  const [latestReport, setLatestReport] = useState<ValueReport | null>(null);

  // UI state
  const [loadingProjects, setLoadingProjects] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [errorProjects, setErrorProjects] = useState<string | null>(null);
  const [errorDetail, setErrorDetail] = useState<string | null>(null);

  // ─── Load coordinator projects ─────────────────────────────────────────────

  const loadCoordinatorProjects = useCallback(async () => {
    setLoadingProjects(true);
    setErrorProjects(null);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setErrorProjects('Non authentifié'); return; }

      // Get admin org IDs for this user
      const { data: memberships } = await supabase
        .from('organization_members')
        .select('organization_id, org_role')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .in('org_role', ['admin', 'owner']);

      const adminOrgIds = (memberships ?? []).map((m) => m.organization_id);

      if (adminOrgIds.length === 0) {
        setCoordinatorProjects([]);
        return;
      }

      // Projects where user is coordinator admin (same filter as isCoordinatorAdmin in S05)
      const { data: projects, error: projErr } = await supabase
        .from('ccf_projects')
        .select(`
          *,
          coordinator_org:organizations!ccf_projects_coordinator_org_id_fkey(name),
          opportunity:opportunities!ccf_projects_opportunity_id_fkey(title)
        `)
        .in('coordinator_org_id', adminOrgIds)
        .order('created_at', { ascending: false });

      if (projErr) throw projErr;
      setCoordinatorProjects((projects ?? []) as CcfProject[]);
    } catch (e: unknown) {
      setErrorProjects(e instanceof Error ? e.message : 'Erreur de chargement');
    } finally {
      setLoadingProjects(false);
    }
  }, [supabase]);

  useEffect(() => { loadCoordinatorProjects(); }, [loadCoordinatorProjects]);

  // ─── Load project detail ───────────────────────────────────────────────────

  const loadProjectDetail = useCallback(async (projectId: string) => {
    setLoadingDetail(true);
    setErrorDetail(null);
    setProject(null);
    setLogisticsSteps([]);
    setParticipants([]);
    setLatestReport(null);
    try {
      // Project
      const { data: projectData, error: projErr } = await supabase
        .from('ccf_projects')
        .select(`
          *,
          coordinator_org:organizations!ccf_projects_coordinator_org_id_fkey(name),
          opportunity:opportunities!ccf_projects_opportunity_id_fkey(title)
        `)
        .eq('id', projectId)
        .single();
      if (projErr) throw projErr;
      setProject(projectData as CcfProject);

      // Logistics steps (for risk calculation)
      const { data: stepsData } = await supabase
        .from('logistics_steps')
        .select('id, project_id, status')
        .eq('project_id', projectId);
      setLogisticsSteps((stepsData ?? []) as LogisticsStep[]);

      // Participants (for risk calculation)
      const { data: participantsData } = await supabase
        .from('project_participants')
        .select('id, project_id, status')
        .eq('project_id', projectId);
      setParticipants((participantsData ?? []) as ProjectParticipant[]);

      // Latest value report (created_at DESC, limit 1)
      const { data: vrData } = await supabase
        .from('value_reports')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      setLatestReport(vrData as ValueReport | null);

    } catch (e: unknown) {
      setErrorDetail(e instanceof Error ? e.message : 'Erreur de chargement du projet');
    } finally {
      setLoadingDetail(false);
    }
  }, [supabase]);

  useEffect(() => {
    if (selectedProjectId) {
      loadProjectDetail(selectedProjectId);
    } else {
      setProject(null);
      setLogisticsSteps([]);
      setParticipants([]);
      setLatestReport(null);
    }
  }, [selectedProjectId, loadProjectDetail]);

  // ─── Derived ───────────────────────────────────────────────────────────────

  const risks = useMemo(
    () => computeProjectRisks(logisticsSteps, project, participants),
    [logisticsSteps, project, participants],
  );

  const summaryText = useMemo(() => {
    if (!project) return null;
    return buildSummaryText(project, latestReport, risks);
  }, [project, latestReport, risks]);

  // ─── Render ────────────────────────────────────────────────────────────────

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto px-4 py-6 space-y-6">

        {/* ── Header ── */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-foreground flex items-center gap-2">
              <Icon name="PresentationChartLineIcon" size={24} className="text-primary" />
              Cockpit exécutif
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              Vue direction — synthèse volumes, risques et avancement d'un projet CCF
            </p>
          </div>
        </div>

        {/* ── Project selector ── */}
        <div className="bg-card border border-border rounded-xl p-5">
          <label className="block text-sm font-semibold text-foreground mb-2">
            Sélectionner un projet
          </label>

          {loadingProjects ? (
            <div className="flex items-center gap-2 text-muted-foreground text-sm py-2">
              <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              Chargement des projets…
            </div>
          ) : errorProjects ? (
            <div className="flex items-center gap-2 text-red-600 text-sm py-2">
              <Icon name="ExclamationCircleIcon" size={16} />
              {errorProjects}
            </div>
          ) : coordinatorProjects.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-8 text-center">
              <Icon name="FolderIcon" size={40} className="text-muted-foreground/40" />
              <div>
                <p className="text-sm font-medium text-foreground">Aucun projet disponible</p>
                <p className="text-xs text-muted-foreground mt-1">
                  Vous n'êtes administrateur coordinateur d'aucun projet CCF.
                </p>
              </div>
            </div>
          ) : (
            <select
              value={selectedProjectId}
              onChange={(e) => setSelectedProjectId(e.target.value)}
              className="w-full px-3 py-2.5 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            >
              <option value="">— Choisir un projet —</option>
              {coordinatorProjects.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.opportunity?.title ?? 'Projet sans titre'} · {p.coordinator_org?.name ?? '—'} · {PHASE_CONFIG[p.phase]?.label ?? p.phase}
                </option>
              ))}
            </select>
          )}
        </div>

        {/* ── No project selected ── */}
        {!selectedProjectId && !loadingProjects && coordinatorProjects.length > 0 && (
          <div className="flex flex-col items-center gap-3 py-12 text-center text-muted-foreground">
            <Icon name="PresentationChartLineIcon" size={48} className="text-muted-foreground/30" />
            <p className="text-sm">Sélectionnez un projet pour afficher le cockpit exécutif.</p>
          </div>
        )}

        {/* ── Loading detail ── */}
        {selectedProjectId && loadingDetail && (
          <div className="flex items-center justify-center py-16">
            <div className="flex flex-col items-center gap-3 text-muted-foreground">
              <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              <span className="text-sm">Chargement du cockpit…</span>
            </div>
          </div>
        )}

        {/* ── Error detail ── */}
        {selectedProjectId && errorDetail && !loadingDetail && (
          <div className="flex items-center gap-2 px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm">
            <Icon name="ExclamationCircleIcon" size={16} />
            {errorDetail}
          </div>
        )}

        {/* ── Cockpit content ── */}
        {project && !loadingDetail && (
          <div className="space-y-5">

            {/* ── Project identity ── */}
            <div className="bg-card border border-border rounded-xl p-5">
              <div className="flex items-start justify-between gap-4 flex-wrap">
                <div>
                  <h2 className="text-lg font-bold text-foreground">
                    {project.opportunity?.title ?? 'Projet sans titre'}
                  </h2>
                  <p className="text-sm text-muted-foreground mt-0.5 flex items-center gap-1.5">
                    <Icon name="BuildingOffice2Icon" size={14} />
                    {project.coordinator_org?.name ?? '—'}
                  </p>
                </div>
                <PhaseBadge phase={project.phase} />
              </div>
              {(project.start_date || project.target_end_date) && (
                <div className="flex gap-4 mt-3 text-xs text-muted-foreground">
                  {project.start_date && (
                    <span className="flex items-center gap-1">
                      <Icon name="CalendarIcon" size={12} />
                      Début : {new Date(project.start_date).toLocaleDateString('fr-CA')}
                    </span>
                  )}
                  {project.target_end_date && (
                    <span className="flex items-center gap-1">
                      <Icon name="FlagIcon" size={12} />
                      Cible : {new Date(project.target_end_date).toLocaleDateString('fr-CA')}
                    </span>
                  )}
                </div>
              )}
            </div>

            {/* ── KPI grid ── */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">

              {/* Avancement */}
              <div className="sm:col-span-3 bg-card border border-border rounded-xl p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-3">
                  Avancement
                </p>
                <ProgressBar phase={project.phase} />
              </div>

              {/* Volume */}
              <div className="bg-card border border-border rounded-xl p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-1">
                  Volume traité
                </p>
                {latestReport ? (
                  latestReport.volume != null ? (
                    <p className="text-3xl font-bold text-foreground tabular-nums">
                      {latestReport.volume.toLocaleString('fr-CA')}
                      <span className="text-base font-normal text-muted-foreground ml-1">t</span>
                    </p>
                  ) : (
                    <p className="text-sm text-muted-foreground italic">Non renseigné</p>
                  )
                ) : (
                  <p className="text-sm text-muted-foreground italic">Aucun rapport de valeur disponible</p>
                )}
                {latestReport && (
                  <p className="text-[10px] text-muted-foreground mt-1">
                    Rapport du {new Date(latestReport.created_at).toLocaleDateString('fr-CA')}
                  </p>
                )}
              </div>

              {/* Valeur de coordination */}
              <div className="bg-card border border-border rounded-xl p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-1">
                  Valeur de coordination
                </p>
                {latestReport ? (
                  latestReport.coordination_value != null ? (
                    <p className="text-3xl font-bold text-foreground tabular-nums">
                      {latestReport.coordination_value.toLocaleString('fr-CA')}
                      <span className="text-base font-normal text-muted-foreground ml-1">$</span>
                    </p>
                  ) : (
                    <p className="text-sm text-muted-foreground italic">Non renseigné</p>
                  )
                ) : (
                  <p className="text-sm text-muted-foreground italic">Aucun rapport de valeur disponible</p>
                )}
              </div>

              {/* Risques */}
              <div className={`bg-card border rounded-xl p-5 ${risks.length > 0 ? 'border-red-200 bg-red-50/30' : 'border-border'}`}>
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-1">
                  Risques détectés
                </p>
                <p className={`text-3xl font-bold tabular-nums ${risks.length > 0 ? 'text-red-600' : 'text-green-600'}`}>
                  {risks.length}
                </p>
                {risks.length === 0 && (
                  <p className="text-xs text-green-700 mt-1 flex items-center gap-1">
                    <Icon name="CheckCircleIcon" size={12} />
                    Aucun risque détecté
                  </p>
                )}
              </div>
            </div>

            {/* ── Risks detail ── */}
            <div className="bg-card border border-border rounded-xl p-5">
              <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-3">
                Détail des risques
              </p>
              {risks.length === 0 ? (
                <div className="flex items-center gap-2 text-green-700 text-sm py-2">
                  <Icon name="CheckCircleIcon" size={16} />
                  Aucun risque détecté pour ce projet.
                </div>
              ) : (
                <ul className="space-y-2">
                  {risks.map((risk, i) => (
                    <li key={i} className="flex items-start gap-3 px-3 py-2.5 rounded-lg bg-muted/50">
                      <Icon
                        name={risk.icon as Parameters<typeof Icon>[0]['name']}
                        size={16}
                        className={
                          risk.severity === 'high'   ? 'text-red-600 flex-shrink-0 mt-0.5' :
                          risk.severity === 'medium'? 'text-amber-600 flex-shrink-0 mt-0.5' : 'text-blue-600 flex-shrink-0 mt-0.5'
                        }
                      />
                      <span className="text-sm text-foreground flex-1">{risk.label}</span>
                      <RiskBadge severity={risk.severity} />
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {/* ── Direction summary ── */}
            {summaryText && (
              <div className="bg-primary/5 border border-primary/20 rounded-xl p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-primary mb-2 flex items-center gap-1.5">
                  <Icon name="DocumentTextIcon" size={14} />
                  Synthèse direction
                </p>
                <p className="text-sm text-foreground leading-relaxed">{summaryText}</p>
              </div>
            )}

            {/* ── Value report notes ── */}
            {latestReport?.notes && (
              <div className="bg-card border border-border rounded-xl p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-2">
                  Notes du dernier rapport
                </p>
                <p className="text-sm text-foreground whitespace-pre-wrap">{latestReport.notes}</p>
              </div>
            )}

          </div>
        )}
      </div>
    </AppLayout>
  );
}
