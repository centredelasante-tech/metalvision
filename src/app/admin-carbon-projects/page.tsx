'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

interface Project {
  id: string;
  name: string;
  description: string | null;
  status: 'draft' | 'active' | 'verified';
  start_date: string | null;
  end_date: string | null;
  created_at: string;
}

const STATUS_CONFIG: Record<string, { label: string; color: string; icon: string }> = {
  draft:    { label: 'Brouillon', color: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'PencilSquareIcon' },
  active:   { label: 'Actif',     color: 'text-green-700 bg-green-50 border-green-200',  icon: 'PlayCircleIcon' },
  verified: { label: 'Vérifié',   color: 'text-blue-700 bg-blue-50 border-blue-200',     icon: 'CheckBadgeIcon' },
};

function StatusBadge({ status }: { status: string }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-600 border ${cfg.color}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

interface NewProjectModalProps {
  onClose: () => void;
  onCreated: () => void;
}

function NewProjectModal({ onClose, onCreated }: NewProjectModalProps) {
  const [form, setForm] = useState({ name: '', description: '', baseline_description: '', project_scenario_description: '', start_date: '', end_date: '' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) { setError('Le nom est requis'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: err } = await supabase.from('projects').insert({
      name: form.name,
      description: form.description || null,
      baseline_description: form.baseline_description || null,
      project_scenario_description: form.project_scenario_description || null,
      start_date: form.start_date || null,
      end_date: form.end_date || null,
      status: 'draft',
    });
    setSaving(false);
    if (err) { setError(err.message); return; }
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">Nouveau projet carbone</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Nom du projet *</label>
            <input className="input w-full" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="Ex: Recyclage Acier Montréal 2024" />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Description</label>
            <textarea className="input w-full h-20 resize-none" value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} placeholder="Description du projet..." />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Date début</label>
              <input type="date" className="input w-full" value={form.start_date} onChange={e => setForm(f => ({ ...f, start_date: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Date fin</label>
              <input type="date" className="input w-full" value={form.end_date} onChange={e => setForm(f => ({ ...f, end_date: e.target.value }))} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Description baseline</label>
            <textarea className="input w-full h-16 resize-none" value={form.baseline_description} onChange={e => setForm(f => ({ ...f, baseline_description: e.target.value }))} placeholder="Scénario de référence..." />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Scénario projet</label>
            <textarea className="input w-full h-16 resize-none" value={form.project_scenario_description} onChange={e => setForm(f => ({ ...f, project_scenario_description: e.target.value }))} placeholder="Scénario projet amélioré..." />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Création...' : 'Créer le projet'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default function AdminCarbonProjectsPage() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [filterStatus, setFilterStatus] = useState<string>('all');

  const fetchProjects = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    let query = supabase.from('projects').select('*').order('created_at', { ascending: false });
    if (filterStatus !== 'all') query = query.eq('status', filterStatus);
    const { data, error: err } = await query;
    setLoading(false);
    if (err) { setError(err.message); return; }
    setProjects(data ?? []);
  }, [filterStatus]);

  useEffect(() => { fetchProjects(); }, [fetchProjects]);

  const filtered = projects;

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Projets Carbone MRV</h1>
            <p className="text-sm text-muted-foreground mt-1">Gestion ISO 14064-2 — Monitoring, Reporting, Verification</p>
          </div>
          <button onClick={() => setShowModal(true)} className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600">
            <Icon name="PlusCircleIcon" size={16} />
            Nouveau projet
          </button>
        </div>

        {/* KPI row */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          {[
            { label: 'Total projets', value: projects.length, icon: 'FolderIcon', color: 'text-blue-600' },
            { label: 'Actifs', value: projects.filter(p => p.status === 'active').length, icon: 'PlayCircleIcon', color: 'text-green-600' },
            { label: 'Vérifiés', value: projects.filter(p => p.status === 'verified').length, icon: 'CheckBadgeIcon', color: 'text-purple-600' },
          ].map(kpi => (
            <div key={kpi.label} className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
              <div className={`w-10 h-10 rounded-lg bg-muted flex items-center justify-center ${kpi.color}`}>
                <Icon name={kpi.icon as Parameters<typeof Icon>[0]['name']} size={20} />
              </div>
              <div>
                <p className="text-2xl font-700 text-foreground">{kpi.value}</p>
                <p className="text-xs text-muted-foreground">{kpi.label}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Filter */}
        <div className="flex gap-2 mb-4">
          {['all', 'draft', 'active', 'verified'].map(s => (
            <button
              key={s}
              onClick={() => setFilterStatus(s)}
              className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${filterStatus === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}
            >
              {s === 'all' ? 'Tous' : STATUS_CONFIG[s]?.label ?? s}
            </button>
          ))}
        </div>

        {/* Projects list */}
        {loading ? (
          <div className="space-y-3">
            {[1,2,3].map(i => <div key={i} className="h-24 bg-muted rounded-xl animate-pulse" />)}
          </div>
        ) : error ? (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700 text-sm">{error}</div>
        ) : filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-xl p-12 text-center">
            <Icon name="FolderOpenIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground font-500">Aucun projet trouvé</p>
            <button onClick={() => setShowModal(true)} className="btn-primary mt-4 px-4 py-2 rounded-lg text-sm font-600">Créer le premier projet</button>
          </div>
        ) : (
          <div className="space-y-3">
            {filtered.map(project => (
              <Link key={project.id} href={`/admin-mrv-project?id=${project.id}`} className="block bg-card border border-border rounded-xl p-5 hover:border-primary/50 transition-all group">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-1">
                      <h3 className="font-700 text-foreground group-hover:text-primary transition-colors truncate">{project.name}</h3>
                      <StatusBadge status={project.status} />
                    </div>
                    {project.description && <p className="text-sm text-muted-foreground truncate">{project.description}</p>}
                    <div className="flex items-center gap-4 mt-2 text-xs text-muted-foreground">
                      {project.start_date && <span>Début: {new Date(project.start_date).toLocaleDateString('fr-CA')}</span>}
                      {project.end_date && <span>Fin: {new Date(project.end_date).toLocaleDateString('fr-CA')}</span>}
                      <span>Créé: {new Date(project.created_at).toLocaleDateString('fr-CA')}</span>
                    </div>
                  </div>
                  <Icon name="ChevronRightIcon" size={18} className="text-muted-foreground group-hover:text-primary transition-colors flex-shrink-0 mt-1" />
                </div>
              </Link>
            ))}
          </div>
        )}
      </div>

      {showModal && <NewProjectModal onClose={() => setShowModal(false)} onCreated={fetchProjects} />}
    </div>
  );
}
