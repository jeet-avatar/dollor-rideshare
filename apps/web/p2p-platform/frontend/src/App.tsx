import { Routes, Route, Navigate } from 'react-router-dom';
import { useUser } from './app/context/UserContext';
import Login from './app/screens/auth/Login';
import ForgotPassword from './app/screens/auth/ForgotPassword';
import Dashboard from './app/screens/dashboard/Main';
import CoupaDashboard from './app/screens/coupaDashboard/Main';
import ZipDashboard from './app/screens/zipDashboard/Main';
import ProjectTracker from './app/screens/projectTracker/Main';
import ChangeManagement from './app/screens/changeManagement/Main';
import ChangeRequestDetail from './app/screens/changeManagement/RequestDetail';
import VendorManagement from './app/screens/vendorManagement/Main';
import DocumentReview from './app/screens/vendorManagement/DocumentReview';
import MenuReview from './app/screens/vendorManagement/MenuReview';
import Invoices from './app/screens/invoices/Invoices';
import Clients from './app/screens/clients/Clients';
import Orders from './app/screens/orders/Main';
import VendorPayouts from './app/screens/accounting/VendorPayouts';
import PlatformRevenue from './app/screens/accounting/PlatformRevenue';
import AccountingReports from './app/screens/accounting/Main';
import MainLayout from './app/components/layout/MainLayout';

// Admin - Rideshare
import RideRequests from './app/screens/rideshare/RideRequests';
import ActiveRides from './app/screens/rideshare/ActiveRides';

// Admin - Drivers
import DriversAdmin from './app/screens/drivers/DriversAdmin';

// Admin - Customers
import CustomersAdmin from './app/screens/customer/CustomersAdmin';

// Admin - Prop 22 Compliance
import Prop22Compliance from './app/screens/prop22/Prop22Compliance';

// Public Pages
import LandingPage from './app/screens/public/LandingPage';
import TermsOfService from './app/screens/public/TermsOfService';
import PrivacyPolicy from './app/screens/public/PrivacyPolicy';
import DriverTerms from './app/screens/public/DriverTerms';
import DeleteAccount from './app/screens/public/DeleteAccount';
import RestaurantApplication from './app/screens/public/RestaurantApplication';
import DriverApplication from './app/screens/public/DriverApplication';
import HelpSupport from './app/screens/public/HelpSupport';
import ReferAndEarn from './app/screens/public/ReferAndEarn';
import RefundPolicy from './app/screens/public/RefundPolicy';
import ZeroTolerancePolicy from './app/screens/public/ZeroTolerancePolicy';
import GetInvolved from './app/screens/public/GetInvolved';
import InvestorDeck from './app/screens/public/InvestorDeck';
import InvestorDeck2026 from './app/screens/public/InvestorDeck2026';

// Customer Pages
import CustomerLogin from './app/screens/auth/CustomerLogin';
import CustomerHome from './app/screens/customer/CustomerHome';
import CustomerProfile from './app/screens/customer/CustomerProfile';
import CustomerAddresses from './app/screens/customer/CustomerAddresses';
import CustomerPaymentMethods from './app/screens/customer/CustomerPaymentMethods';
import CustomerFavorites from './app/screens/customer/CustomerFavorites';
import CustomerSettings from './app/screens/customer/CustomerSettings';
import CustomerNotifications from './app/screens/customer/CustomerNotifications';
import Restaurants from './app/screens/customer/Restaurants';
import RestaurantDetail from './app/screens/customer/RestaurantDetail';
import Cart from './app/screens/customer/Cart';
import Checkout from './app/screens/customer/Checkout';
import RideBooking from './app/screens/customer/RideBooking';
import DealsPage from './app/screens/customer/DealsPage';

// Vendor Pages
import VendorLogin from './app/screens/auth/VendorLogin';
import VendorLayout from './app/components/layout/VendorLayout';
import VendorOrders from './app/screens/vendor/Orders';
import VendorProfile from './app/screens/vendor/Profile';
import VendorDashboard from './app/screens/vendor/Dashboard';
import VendorDocuments from './app/screens/vendor/Documents';
import VendorMenuManagement from './app/screens/vendor/MenuManagement';
import VendorAnalytics from './app/screens/vendor/Analytics';
import VendorAIInsights from './app/screens/vendor/AIInsights';
import VendorPaymentSettings from './app/screens/vendor/PaymentSettings';

// Driver Pages
import DriverLogin from './app/screens/auth/DriverLogin';
import DriverLayout from './app/components/layout/DriverLayout';
import DriverDeliveries from './app/screens/driver/Deliveries';
import DriverMessages from './app/screens/driver/Messages';
import DriverProfile from './app/screens/driver/Profile';
import DriverDashboard from './app/screens/driver/Dashboard';
import DriverEarnings from './app/screens/driver/Earnings';
import RideBidding from './app/screens/driver/RideBidding';
import DriverDocuments from './app/screens/driver/Documents';
import RideBids from './app/screens/customer/RideBids';

// Wrapper to provide dynamic customerId from localStorage
const RideBidsWrapper = () => {
  const customerId = parseInt(localStorage.getItem('customer_id') || '0');
  return <RideBids customerId={customerId} />;
};

/**
 * DOLLOR.AI WEB APPLICATION
 *
 * Routes:
 * - / : Public landing page
 * - /customer/* : Customer ordering and ride booking
 * - /vendor/* : Restaurant portal
 * - /driver/* : Driver portal
 * - /admin/* : Admin backend operations
 *
 * See CLAUDE.md for full documentation.
 */

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useUser();

  // Wait for auth check to complete before making decisions
  if (loading) {
    return (
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        height: '100vh',
        background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)'
      }}>
        <div style={{ textAlign: 'center', color: '#fff' }}>
          <div style={{ fontSize: '24px', marginBottom: '16px' }}>🔐</div>
          <div>Verifying authentication...</div>
        </div>
      </div>
    );
  }

  // Authentication required for admin routes
  if (!user) {
    return <Navigate to="/login" replace />;
  }

  // Verify admin role
  if (user.role !== 'admin') {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}

function App() {
  return (
    <Routes>
        {/* Public Landing Page */}
        <Route path="/" element={<LandingPage />} />

        {/* Public Pages */}
        <Route path="/terms" element={<TermsOfService />} />
        <Route path="/privacy" element={<PrivacyPolicy />} />
        <Route path="/driver-terms" element={<DriverTerms />} />
        <Route path="/delete-account" element={<DeleteAccount />} />
        <Route path="/refund" element={<RefundPolicy />} />
        <Route path="/refunds" element={<RefundPolicy />} />
        <Route path="/zero-tolerance" element={<ZeroTolerancePolicy />} />
        <Route path="/safety" element={<ZeroTolerancePolicy />} />
        <Route path="/help" element={<HelpSupport />} />
        <Route path="/support" element={<HelpSupport />} />
        <Route path="/refer" element={<ReferAndEarn />} />
        <Route path="/referral" element={<ReferAndEarn />} />

        {/* Investor Deck (Token-protected) */}
        <Route path="/investor" element={<InvestorDeck />} />
        <Route path="/investors" element={<InvestorDeck />} />
        <Route path="/deck" element={<InvestorDeck />} />

        {/* Investor Deck 2026 (Password-protected) */}
        <Route path="/investor2026" element={<InvestorDeck2026 />} />

        {/* Get Involved */}
        <Route path="/get-involved" element={<GetInvolved />} />
        <Route path="/partner" element={<GetInvolved />} />
        <Route path="/volunteer" element={<GetInvolved />} />
        <Route path="/invest" element={<GetInvolved />} />

        {/* Restaurant & Driver Applications */}
        <Route path="/restaurant/apply" element={<RestaurantApplication />} />
        <Route path="/driver/apply" element={<DriverApplication />} />

        {/* Customer Routes */}
        <Route path="/customer/login" element={<CustomerLogin />} />
        <Route path="/customer" element={<Navigate to="/customer/rides" replace />} />
        <Route path="/customer/home" element={<Navigate to="/customer/rides" replace />} />
        <Route path="/customer/dashboard" element={<Navigate to="/customer/rides" replace />} />
        <Route path="/customer/restaurants" element={<Restaurants />} />
        <Route path="/customer/restaurant/:id" element={<RestaurantDetail />} />
        <Route path="/customer/cart" element={<Cart />} />
        <Route path="/customer/checkout" element={<Checkout />} />
        <Route path="/customer/rides" element={<RideBooking />} />
        <Route path="/customer/ride" element={<RideBooking />} />
        <Route path="/customer/ride-bids" element={<RideBidsWrapper />} />
        <Route path="/customer/ride-bids/:requestId" element={<RideBidsWrapper />} />
        <Route path="/customer/deals" element={<DealsPage />} />
        <Route path="/customer/search" element={<Restaurants />} />
        <Route path="/customer/address" element={<CustomerHome />} />
        <Route path="/customer/profile" element={<CustomerProfile />} />
        <Route path="/customer/addresses" element={<CustomerAddresses />} />
        <Route path="/customer/payment-methods" element={<CustomerPaymentMethods />} />
        <Route path="/customer/favorites" element={<CustomerFavorites />} />
        <Route path="/customer/settings" element={<CustomerSettings />} />
        <Route path="/customer/notifications" element={<CustomerNotifications />} />
        <Route path="/customer/privacy-policy" element={<PrivacyPolicy />} />
        <Route path="/customer/terms" element={<TermsOfService />} />
        <Route path="/customer/help" element={<HelpSupport />} />
        <Route path="/customer/refer" element={<ReferAndEarn />} />

        {/* Vendor Routes - Aligned with iOS EnhancedDashboardView tabs */}
        <Route path="/vendor/login" element={<VendorLogin />} />
        <Route path="/vendor" element={<VendorLayout />}>
          <Route index element={<VendorOrders />} />
          <Route path="orders" element={<VendorOrders />} />
          <Route path="menu" element={<VendorMenuManagement />} />
          <Route path="analytics" element={<VendorAnalytics />} />
          <Route path="ai" element={<VendorAIInsights />} />
          <Route path="settings" element={<VendorProfile />} />
          <Route path="profile" element={<VendorProfile />} />
          <Route path="dashboard" element={<VendorDashboard />} />
          <Route path="documents" element={<VendorDocuments />} />
          <Route path="payouts" element={<VendorPaymentSettings />} />
        </Route>

        {/* Driver Routes - Aligned with iOS DriverDashboardView tabs */}
        <Route path="/driver/login" element={<DriverLogin />} />
        <Route path="/driver" element={<DriverLayout />}>
          <Route index element={<RideBidding />} />
          <Route path="bidding" element={<RideBidding />} />
          <Route path="history" element={<DriverDeliveries />} />
          <Route path="messages" element={<DriverMessages />} />
          <Route path="profile" element={<DriverProfile />} />
          <Route path="documents" element={<DriverDocuments />} />
          <Route path="dashboard" element={<DriverDashboard />} />
          <Route path="earnings" element={<DriverEarnings />} />
        </Route>

        {/* Admin Auth Routes */}
        <Route path="/login" element={<Login />} />
        <Route path="/forgot-password" element={<ForgotPassword />} />

        {/* Admin Portal - Backend Operations */}
        <Route path="/admin" element={<ProtectedRoute><MainLayout /></ProtectedRoute>}>
          <Route index element={<Dashboard />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="coupa-dashboard" element={<CoupaDashboard />} />
          <Route path="zip-dashboard" element={<ZipDashboard />} />
          <Route path="vendor-management" element={<VendorManagement />} />
          <Route path="document-review" element={<DocumentReview />} />
          <Route path="menu-review" element={<MenuReview />} />
          <Route path="orders" element={<Orders />} />
          <Route path="rideshare/requests" element={<RideRequests />} />
          <Route path="rideshare/active" element={<ActiveRides />} />
          <Route path="drivers" element={<DriversAdmin />} />
          <Route path="customers" element={<CustomersAdmin />} />
          <Route path="accounting/vendor-payouts" element={<VendorPayouts />} />
          <Route path="accounting/platform-revenue" element={<PlatformRevenue />} />
          <Route path="accounting/reports" element={<AccountingReports />} />
          <Route path="invoices" element={<Invoices />} />
          <Route path="project-tracker" element={<ProjectTracker />} />
          <Route path="change-management" element={<ChangeManagement />} />
          <Route path="change-management/:crId" element={<ChangeRequestDetail />} />
          <Route path="clients" element={<Clients />} />
          <Route path="prop22" element={<Prop22Compliance />} />
        </Route>

        {/* Fallback */}
        <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default App;
