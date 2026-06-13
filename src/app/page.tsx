import AppLayout from '@/components/AppLayout';
import ClientDashboardContent from './components/ClientDashboardContent';

export default function ClientDashboardPage() {
  return (
    <AppLayout activeRoute="/" userRole="client">
      <ClientDashboardContent />
    </AppLayout>
  );
}