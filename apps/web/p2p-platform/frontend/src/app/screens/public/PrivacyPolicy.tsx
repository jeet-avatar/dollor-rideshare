import React from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const section = (title: string, children: React.ReactNode) => (
  <div style={{ marginBottom: 40 }}>
    <h2 style={{ fontSize: 20, fontWeight: 800, marginBottom: 16, color: '#fff', letterSpacing: '-0.5px' }}>{title}</h2>
    <div style={{ color: 'rgba(255,255,255,0.6)', fontSize: 15, lineHeight: 1.8 }}>{children}</div>
  </div>
);

const PrivacyPolicy: React.FC = () => (
  <div style={publicPageStyle}>
    <PublicNav />
    <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>

        <div style={{ textAlign: 'center', marginBottom: 56 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>🔒 LEGAL</div>
          <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>Privacy Policy</h1>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: 14 }}>Last updated: October 29, 2026 · Zietra Technologies Inc. (DBA Dollor.ai)</p>
        </div>

        <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 20, padding: '40px' }}>

          {section('1. Who We Are', <>
            <p>Dollor is a peer-to-peer rideshare marketplace operated by Zietra Technologies Inc., doing business as Dollor.ai ("Dollor", "we", "us", or "our"), a California-based technology company.</p>
            <p style={{ marginTop: 12 }}>Contact: <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a></p>
          </>)}

          {section('2. Information We Collect', <>
            <p style={{ marginBottom: 12 }}>We collect information you provide directly and information generated through your use of the platform:</p>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
              {[
                { t: 'Account Information', d: 'Name, email, phone number, profile photo (drivers), driver license and insurance document photos (drivers), saved addresses (riders), optional accessibility request' },
                { t: 'Payment Information', d: 'Payment cards are entered into the Stripe card form (we store Stripe tokens and the card brand and last 4 digits); drivers enter bank details on the Stripe page' },
                { t: 'Location Data', d: 'Precise location while the app is in use (riders) and while online (drivers, including in the background on iOS)' },
                { t: 'Device Information', d: 'Device type, OS, app version, IP address, push notification token; on Android, basic app-interaction analytics (Firebase)' },
                { t: 'Trip Information', d: 'Pickup/dropoff, route, fare, timestamps' },
                { t: 'Communications', d: 'In-app messages between riders and drivers' },
              ].map(i => (
                <div key={i.t} style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 12, padding: '16px' }}>
                  <div style={{ fontSize: 13, fontWeight: 700, color: '#ff9500', marginBottom: 6 }}>{i.t}</div>
                  <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.5)' }}>{i.d}</div>
                </div>
              ))}
            </div>
          </>)}

          {section('3. How We Use Your Information', <>
            <p>We use your information to:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {['Provide, maintain, and improve the Dollor platform', 'Match riders with drivers and facilitate rides', 'Process payments and prevent fraud', 'Send trip receipts, safety alerts, and account notifications', 'Run driver background checks through Checkr', 'Comply with CPUC regulations and applicable law', 'Resolve disputes and provide customer support'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
          </>)}

          {section('4. Information Sharing', <>
            <p>We share information only as necessary to operate the platform:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {[
                'Between riders and drivers — names, photos, vehicle info, and real-time location during an active trip',
                'Stripe — for payment processing (subject to Stripe\'s Privacy Policy)',
                'Checkr — for driver background checks (drivers enter their identity details on Checkr\'s page; we receive the result)',
                'Law enforcement — when required by law or to protect safety',
                'Firebase (Google) — push notifications, and on Android analytics',
              ].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
            <p style={{ marginTop: 12 }}>We do not sell your personal information to third parties.</p>
          </>)}

          {section('5. Location Data', <>
            <p>Location data is core to our service. Rider apps collect precise location while the app is in use, to set your pickup point and show nearby drivers. Driver apps collect precise location while the driver is online, including in the background on iOS. You can revoke location permission in your device settings, which will limit your ability to use the app.</p>
          </>)}

          {section('6. Data Retention', <>
            <p>We retain your account data for as long as your account is active. Trip and payment records are retained for 7 years for tax and regulatory purposes. You can delete your account in the app (Profile &gt; Delete Account) or by email request (completed within 30 days); see dollor.ai/delete-account. Records we are required to keep may be retained after deletion.</p>
          </>)}

          {section('7. Your Rights (California Residents)', <>
            <p>Under the California Consumer Privacy Act (CCPA), you have the right to:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {['Know what personal information we collect and how it is used', 'Request deletion of your personal information', 'Opt out of the sale of personal information (we do not sell data)', 'Non-discrimination for exercising your rights'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
            <p style={{ marginTop: 12 }}>To exercise these rights, email <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a>.</p>
          </>)}

          {section('8. Security', <>
            <p>We implement industry-standard security measures including encryption in transit (TLS), encrypted payment processing via Stripe, and access controls. However, no system is perfectly secure. If you believe your account has been compromised, contact us immediately.</p>
          </>)}

          {section('9. Changes to This Policy', <>
            <p>We may update this Privacy Policy periodically. We will notify you of material changes via email or in-app notification. Continued use of the platform after changes constitutes acceptance.</p>
          </>)}

          {section('10. Contact', <>
            <p>Questions about this policy? Contact us at <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a> or write to: Zietra Technologies Inc., Rancho Santa Margarita, California.</p>
          </>)}
        </div>
      </div>
    </div>
    <PublicFooter />
    <style>{`
      @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800;900&display=swap');
      * { margin:0; padding:0; box-sizing:border-box; }
      body { background:#0a0a0f; }
    `}</style>
  </div>
);

export default PrivacyPolicy;
