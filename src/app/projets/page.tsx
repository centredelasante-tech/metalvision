'use client';
import React, { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import { getErrorMessage } from '@/lib/getErrorMessage';

type ProjectPhase = 'draft' | 'active' | 'execution' | 'review' | 'closed';
type ProjectStatus = 'draft' | 'active' | 'paused' | 'closed' | 'archived';

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

const PHASE_CONFIG: Record<ProjectPhase, { label: string; cls: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200' },
  active:    { label: 'Actif',      cls: 'text-green-700 bg-green-50 border-green-200' },
  execution: { label: 'Exécution',  cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  review:    { label: 'Révision',   cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  closed:    { label: 'Clôturé',    cls: 'text-slate-500 bg-slate-100 border-slate-200' },
};

export default function ProjetsPage() {
  const supabase = createClient();
  const [projects, setProjects] = useState<CcfProject[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filterPhase, setFilterPhase] = useState<ProjectPhase | 'all'>('all');

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: err } = await supabase
        .from('ccf_projects')
        .select(`
          *,
          coordinator_org:organizations!ccf_projects_coordinator_org_id_fkey(name),
          opportunity:opportunities!ccf_projects_opportunity_id_fkey(title)
        `)
        .order('created_at', { ascending: false });
      if (err) throw err;
      setProjects((data ?? []) as CcfProject[]);
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur de chargement'));
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => { loadData(); }, [loadData]);

  const filtered = filterPhase === 'all' ? projects : projects.filter((p) => p.phase === filterPhase);

  return (
    <AppLayout>
      <div className="max-w-5xl mx-auto px-4 py-6 space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-foreground">Projets CCF</h1>
            <p className="text-sm text-muted-foreground mt-0.5">{projects.length} projet{projects.length !== 1 ? 's' : ''} accessible{projects.length !== 1 ? 's' : ''}</p>
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-2">
          {(['all', 'draft', 'active', 'execution', 'review', 'closed'] as const).map((phase) => (
            <button
              key={phase}
              onClick={() => setFilterPhase(phase)}
              className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${
                filterPhase === phase
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'bg-card text-muted-foreground border-border hover:bg-muted'
              }`}
            >
              {phase === 'all' ? 'Tous' : PHASE_CONFIG[phase].label}
            </button>
          ))}
        </div>

        {/* Error */}
        {error && (
          <div className="flex items-center gap-2 px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm">
            <Icon name="ExclamationCircleIcon" size={16} />
            {error}
          </div>
        )}

        {/* Loading */}
        {loading ? (
          <div className="flex items-center justify-center py-16">
            <div className="flex flex-col items-center gap-3 text-muted-foreground">
              <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              <span className="text-sm">Chargement…</span>
            </div>
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-3 py-16 text-muted-foreground">
            <Icon name="FolderIcon" size={40} />
            <p className="text-sm">Aucun projet trouvé.</p>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map((project) => {
              const phaseCfg = PHASE_CONFIG[project.phase] ?? PHASE_CONFIG.draft;
              return (
                <Link
                  key={project.id}
                  href={`/projets/${project.id}`}
                  className="flex items-center gap-4 bg-card border border-border rounded-xl px-5 py-4 hover:bg-muted transition-colors group"
                >
                  <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center flex-shrink-0">
                    <Icon name="FolderIcon" size={18} className="text-primary" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate group-hover:text-primary transition-colors">
                      {project.opportunity?.title ?? `Projet ${project.id.slice(0, 8)}`}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {project.coordinator_org?.name ?? '—'}
                      {project.start_date && ` · ${new Date(project.start_date).toLocaleDateString('fr-CA')}`}
                    </p>
                  </div>
                  <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2.5 py-1 border ${phaseCfg.cls}`}>
                    {phaseCfg.label}
                  </span>
                  <Icon name="ChevronRightIcon" size={16} className="text-muted-foreground flex-shrink-0" />
                </Link>
              );
            })}
          </div>
        )}
      </div>
    </AppLayout>
  );
}
