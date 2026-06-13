import AppLayout from '@/components/AppLayout';
import NewLotWizard from './components/NewLotWizard';

export default function NewLotPage() {
  return (
    <AppLayout activeRoute="/new-lot" userRole="client">
      <NewLotWizard />
    </AppLayout>
  );
}