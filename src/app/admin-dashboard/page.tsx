import AppLayout from '@/components/AppLayout';
import AdminDashboardContent from './components/AdminDashboardContent';

export default function AdminDashboardPage() {
  return (
    <AppLayout activeRoute="/admin-dashboard" userRole="admin">
      <AdminDashboardContent />
    </AppLayout>
  );
}