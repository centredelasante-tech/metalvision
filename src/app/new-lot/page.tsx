import { Suspense } from 'react';
import AppLayout from '@/components/AppLayout';
import NewLotWizard from './components/NewLotWizard';

export default function NewLotPage() {
  return (
    <AppLayout activeRoute="/new-lot" userRole="client">
      <Suspense fallback={<div className="max-w-2xl mx-auto p-8 text-center text-muted-foreground text-sm">Chargement…</div>}>
        <NewLotWizard />
      </Suspense>
    </AppLayout>
  );
}