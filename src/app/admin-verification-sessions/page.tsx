'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

interface VerificationSession {
  id: string;
  project_id: string;
  verifier_org: string | null;
  verifier_contact: string | null;
  scope: Record<string, unknown> | null;
  status: 'planned' | 'in_progress' | 'completed';
  report_url: string | null;
  comments: string | null;
  created_at: string;
  projects?: { name: string } | null;
}

const STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  planned:     { label: 'Planifié',  color: 'text-amber-700 bg-amber-50 border-amber-200' },
  in_progress: { label: 'En cours', color: 'text-blue-700 bg-blue-50 border-blue-200' },
  completed:   { label: 'Complété', color: 'text-green-700 bg-green-50 border-green-200' },
};

interface SessionModalProps {
  session?: VerificationSession | null;
  projects: { id: string; name: string }[];
  onClose: () => void;
  onSaved: () => void;
}

function SessionModal({ session, projects, onClose, onSaved }: SessionModalProps) {
  const [form, setForm] = useState({
    project_id: session?.project_id ?? (projects[0]?.id ?? ''),
    verifier_org: session?.verifier_org ?? '',
    verifier_contact: session?.verifier_contact ?? '',
    status: session?.status ?? 'planned',
    report_url: session?.report_url ?? '',
    comments: session?.comments ?? '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.project_id) { setError('Projet requis'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const payload = {
      project_id: form.project_id,
      verifier_org: form.verifier_org || null,
      verifier_contact: form.verifier_contact || null,
      status: form.status as 'planned' | 'in_progress' | 'completed',
      report_url: form.report_url || null,
      comments: form.comments || null,
    };
    const { error: err } = session
      ? await supabase.from('verification_sessions').update(payload).eq('id', session.id)
      : await supabase.from('verification_sessions').insert(payload);
    setSaving(false);
    if (err) { setError(err.message); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{session ? 'Modifier' : 'Nouvelle'} session de vérification</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Projet *</label>
            <select className="input w-full" value={form.project_id} onChange={e => setForm(f => ({ ...f, project_id: e.target.value }))}>
              {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Organisme vérificateur</label>
              <input className="input w-full" value={form.verifier_org} onChange={e => setForm(f => ({ ...f, verifier_org: e.target.value }))} placeholder="Bureau Veritas..." />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Contact</label>
              <input className="input w-full" value={form.verifier_contact} onChange={e => setForm(f => ({ ...f, verifier_contact: e.target.value }))} placeholder="email@veritas.ca" />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Statut</label>
              <select className="input w-full" value={form.status} onChange={e => setForm(f => ({ ...f, status: e.target.value as 'planned' | 'in_progress' | 'completed' }))}>
                <option value="planned">Planifié</option>
                <option value="in_progress">En cours</option>
                <option value="completed">Complété</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">URL rapport</label>
              <input className="input w-full" value={form.report_url} onChange={e => setForm(f => ({ ...f, report_url: e.target.value }))} placeholder="https://..." />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Commentaires</label>
            <textarea className="input w-full h-20 resize-none" value={form.comments} onChange={e => setForm(f => ({ ...f, comments: e.target.value }))} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Sauvegarde...' : 'Sauvegarder'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default function AdminVerificationSessionsPage() {
  const [sessions, setSessions] = useState<VerificationSession[]>([]);
  const [projects, setProjects] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editSession, setEditSession] = useState<VerificationSession | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');

  const fetchData = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    const [sessRes, projRes] = await Promise.all([
      supabase.from('verification_sessions').select('*, projects(name)').order('created_at', { ascending: false }),
      supabase.from('projects').select('id, name').order('name'),
    ]);
    setSessions(sessRes.data ?? []);
    setProjects(projRes.data ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = filterStatus === 'all' ? sessions : sessions.filter(s => s.status === filterStatus);

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Sessions de vérification</h1>
            <p className="text-sm text-muted-foreground mt-1">Gestion des vérifications tierces ISO 14064-2</p>
          </div>
          <button onClick={() => { setEditSession(null); setShowModal(true); }} className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600">
            <Icon name="PlusCircleIcon" size={16} />
            Nouvelle session
          </button>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          {(['planned', 'in_progress', 'completed'] as const).map(s => (
            <div key={s} className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
              <div className={`w-10 h-10 rounded-lg bg-muted flex items-center justify-center`}>
                <Icon name={s === 'completed' ? 'CheckBadgeIcon' : s === 'in_progress' ? 'ClockIcon' : 'CalendarIcon'} size={20} className={s === 'completed' ? 'text-green-600' : s === 'in_progress' ? 'text-blue-600' : 'text-amber-600'} />
              </div>
              <div>
                <p className="text-2xl font-700 text-foreground">{sessions.filter(x => x.status === s).length}</p>
                <p className="text-xs text-muted-foreground">{STATUS_CONFIG[s].label}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Filter */}
        <div className="flex gap-2 mb-4">
          {['all', 'planned', 'in_progress', 'completed'].map(s => (
            <button key={s} onClick={() => setFilterStatus(s)} className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${filterStatus === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}>
              {s === 'all' ? 'Tous' : STATUS_CONFIG[s]?.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="space-y-3">{[1,2,3].map(i => <div key={i} className="h-24 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-xl p-12 text-center">
            <Icon name="CheckBadgeIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground font-500">Aucune session trouvée</p>
          </div>
        ) : (
          <div className="space-y-3">
            {filtered.map(session => (
              <div key={session.id} className="bg-card border border-border rounded-xl p-5">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-1">
                      <p className="font-700 text-foreground">{session.verifier_org ?? 'Organisme non défini'}</p>
                      <span className={`px-2.5 py-0.5 rounded-full text-xs font-600 border ${STATUS_CONFIG[session.status]?.color}`}>
                        {STATUS_CONFIG[session.status]?.label}
                      </span>
                    </div>
                    <p className="text-sm text-muted-foreground">
                      Projet: <span className="text-foreground font-500">{session.projects?.name ?? session.project_id}</span>
                    </p>
                    {session.verifier_contact && <p className="text-xs text-muted-foreground mt-0.5">{session.verifier_contact}</p>}
                    {session.comments && <p className="text-sm text-muted-foreground mt-1 italic">{session.comments}</p>}
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    {session.report_url && (
                      <a href={session.report_url} target="_blank" rel="noopener noreferrer" className="btn-ghost p-2 rounded-lg">
                        <Icon name="ArrowTopRightOnSquareIcon" size={16} />
                      </a>
                    )}
                    <button onClick={() => { setEditSession(session); setShowModal(true); }} className="btn-ghost p-2 rounded-lg">
                      <Icon name="PencilSquareIcon" size={16} />
                    </button>
                  </div>
                </div>
                <p className="text-xs text-muted-foreground mt-2">Créé: {new Date(session.created_at).toLocaleDateString('fr-CA')}</p>
              </div>
            ))}
          </div>
        )}
      </div>

      {showModal && (
        <SessionModal
          session={editSession}
          projects={projects}
          onClose={() => { setShowModal(false); setEditSession(null); }}
          onSaved={fetchData}
        />
      )}
    </div>
  );
}
