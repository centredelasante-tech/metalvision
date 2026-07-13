'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import type { ContainerData } from './QRScannerContent';

interface ManualEntryProps {
  onResult: (container: ContainerData | null, error: string | null) => void;
}

export default function ManualEntry({ onResult }: ManualEntryProps) {
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [inputError, setInputError] = useState<string | null>(null);

  const handleSearch = async () => {
    const trimmed = code.trim();
    if (!trimmed) {
      setInputError('Veuillez saisir un code QR.');
      return;
    }
    setInputError(null);
    setLoading(true);

    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();

    const { data: memberData } = await supabase
      .from('organization_members')
      .select('organization_id')
      .eq('user_id', user?.id)
      .limit(1)
      .single();

    const userCompanyId = memberData?.organization_id ?? null;

    const { data: containers, error } = await supabase
      .from('containers')
      .select('id, name, location, status, company_id, qr_code')
      .eq('qr_code', trimmed)
      .eq('status', 'active')
      .limit(1);

    if (error || !containers || containers.length === 0) {
      setLoading(false);
      onResult(null, 'Conteneur introuvable ou inactif. Vérifiez le code et réessayez.');
      return;
    }

    const container = containers[0] as ContainerData;

    if (userCompanyId && container.company_id !== userCompanyId) {
      setLoading(false);
      onResult(null, "Ce conteneur appartient à une autre entreprise. Vous n'êtes pas autorisé à y accéder.");
      return;
    }

    // GPS avec timeout 10s
    const getGPS = (): Promise<{ lat: number | null; lng: number | null; accuracy: number | null }> =>
      new Promise((resolve) => {
        if (!navigator.geolocation) return resolve({ lat: null, lng: null, accuracy: null });
        const timer = setTimeout(() => resolve({ lat: null, lng: null, accuracy: null }), 10000);
        navigator.geolocation.getCurrentPosition(
          (pos) => {
            clearTimeout(timer);
            resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude, accuracy: pos.coords.accuracy });
          },
          () => {
            clearTimeout(timer);
            resolve({ lat: null, lng: null, accuracy: null });
          }
        );
      });

    const gps = await getGPS();

    const { error: scanError } = await supabase.from('scan_events').insert({
      container_id: container.id,
      company_id: container.company_id,
      user_id: user?.id,
      action_type: 'collecte',
      gps_lat: gps.lat,
      gps_lng: gps.lng,
      gps_accuracy_m: gps.accuracy,
      scanned_at: new Date().toISOString(),
    });

    if (scanError) {
      console.warn('scan_event insertion failed (non-blocking):', scanError);
    }

    setLoading(false);
    onResult(container, null);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') handleSearch();
  };

  return (
    <div className="bg-card rounded-xl border border-border p-5">
      <div className="flex items-center gap-2 mb-1">
        <Icon name="PencilSquareIcon" size={18} className="text-primary" />
        <h3 className="text-base font-600 text-foreground">Saisie manuelle</h3>
      </div>
      <p className="text-xs text-muted-foreground mb-5">
        Entrez le code QR inscrit sur le conteneur (ex : QR-CT-001, CT-003)
      </p>

      <div className="space-y-3">
        <div>
          <label className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-1.5 block">
            Code QR du conteneur
          </label>
          <div className="flex gap-3">
            <div className="flex-1 relative">
              <div className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
                <Icon name="QrCodeIcon" size={16} className="text-muted-foreground" />
              </div>
              <input
                type="text"
                value={code}
                onChange={(e) => { setCode(e.target.value); setInputError(null); }}
                onKeyDown={handleKeyDown}
                placeholder="QR-CT-001"
                className="w-full pl-9 pr-4 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm font-500 focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground"
                autoComplete="off"
                autoCapitalize="characters"
              />
            </div>
            <button
              type="button"
              onClick={handleSearch}
              disabled={loading}
              className="px-5 py-2.5 rounded-lg text-sm font-600 btn-primary flex items-center gap-2 min-h-[44px] disabled:opacity-60"
            >
              {loading ? (
                <div className="w-4 h-4 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              ) : (
                <Icon name="MagnifyingGlassIcon" size={16} className="text-primary-foreground" />
              )}
              <span className="hidden sm:inline">{loading ? 'Recherche…' : 'Rechercher'}</span>
            </button>
          </div>
          {inputError && (
            <p className="text-xs text-red-600 mt-1.5 flex items-center gap-1">
              <Icon name="ExclamationCircleIcon" size={12} />
              {inputError}
            </p>
          )}
        </div>

        <p className="text-[11px] text-muted-foreground">
          Le code est généralement imprimé sous le QR code sur l'étiquette du conteneur.
        </p>
      </div>
    </div>
  );
}