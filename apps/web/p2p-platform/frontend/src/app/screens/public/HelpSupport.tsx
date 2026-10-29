import React, { useState } from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

interface FAQ { q: string; a: string; cat: string }

const FAQS: FAQ[] = [
  { cat: 'Rides', q: 'How do I book a ride?', a: 'Open the Dollor app, tap "Book a Ride", enter your pickup and destination, then tap "Get Estimate". Review the fare range and tap "Request Ride" — nearby online drivers can submit bids during a 5-minute window.' },
  { cat: 'Rides', q: 'How does the bidding system work?', a: 'After you request a ride, drivers who are online nearby submit bids during a 5-minute window. You can accept a bid, make a counter-offer, or decline.' },
  { cat: 'Rides', q: 'What if I need to cancel my ride?', a: 'You can cancel before the trip starts at no charge. If a driver has arrived at your pickup and waited at least 5 minutes, the driver can mark you as a no-show and your saved card is charged a $5.00 no-show fee. If a driver cancels, you are not charged.' },
  { cat: 'Payments', q: 'What is the connection fee?', a: 'Dollor charges a flat connection fee based on the fare: $1 if the fare is $35 or less, $2 up to $70, and $3 above $70, charged to the rider and separately to the driver, plus a $0.05 CPUC Access for All charge to each. It is not a percentage commission. Suggested fares include a time-of-day adjustment that is shown in the estimate before you request.' },
  { cat: 'Payments', q: 'What payment methods are accepted?', a: 'Dollor accepts credit and debit cards, processed by Stripe (Apple Pay is also offered on iOS where your device supports it). You can manage payment methods in Profile > Payment Methods.' },
  { cat: 'Payments', q: 'Where does my tip go?', a: '100% of your tip goes directly to the driver. Dollor does not take any portion of tips. You can tip through the app after your ride is complete.' },
  { cat: 'Payments', q: 'When is my card charged?', a: 'Your card is authorized when you accept a bid and the fare is captured when the ride is completed. If the ride is cancelled before the trip starts, the authorization is released.' },
  { cat: 'Drivers', q: 'How do I apply to drive with Dollor?', a: 'Download the Dollor driver app or visit dollor.ai/driver/apply. You must be at least 21, with a valid driver\'s license, vehicle insurance, and a profile photo, and complete a Checkr background check and approval before you can go online.' },
  { cat: 'Drivers', q: 'What is the background check process?', a: 'Drivers complete a background and motor vehicle record check through Checkr on Checkr\'s own page. The Dollor server does not let a driver go online until the driver is approved and the check has cleared.' },
  { cat: 'Drivers', q: 'How and when do drivers get paid?', a: 'Drivers are paid through Stripe. Complete Stripe payout onboarding in the driver app, then see Earnings for trip earnings and payouts.' },
  { cat: 'Safety', q: 'What safety features does Dollor have?', a: 'The iOS rider app includes Share trip and an emergency button that calls 911 from your phone. Drivers must be approved with a cleared Checkr background check before going online. In an emergency, call 911 directly.' },
  { cat: 'Safety', q: 'What is Dollor\'s Zero Tolerance policy?', a: 'Dollor prohibits discrimination, harassment, and driving or riding under the influence. Violations may result in suspension or deactivation. See our full Zero Tolerance Policy.' },
  { cat: 'Account', q: 'How do I update my profile or phone number?', a: 'Go to Profile in the app to update your name and phone number.' },
  { cat: 'Account', q: 'How do I delete my account?', a: 'In the app, go to Profile > Delete Account (riders can also use Settings > Delete Account). Deletion is permanent. You can also email support@dollor.ai from your registered address; requests are completed within 30 days. Details: dollor.ai/delete-account.' },
];

const CATS = ['All', 'Rides', 'Payments', 'Drivers', 'Safety', 'Account'];

const HelpSupport: React.FC = () => {
  const [search, setSearch] = useState('');
  const [cat, setCat] = useState('All');
  const [open, setOpen] = useState<string | null>(null);

  const filtered = FAQS.filter(f =>
    (cat === 'All' || f.cat === cat) &&
    (!search || f.q.toLowerCase().includes(search.toLowerCase()) || f.a.toLowerCase().includes(search.toLowerCase()))
  );

  const inp: React.CSSProperties = {
    width: '100%', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 12, padding: '14px 18px 14px 48px', color: '#fff', fontSize: 15, outline: 'none',
    fontFamily: 'inherit',
  };

  return (
    <div style={publicPageStyle}>
      <PublicNav />
      <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
        <div style={{ maxWidth: 760, margin: '0 auto' }}>

          {/* Header */}
          <div style={{ textAlign: 'center', marginBottom: 48 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>❓ HELP CENTER</div>
            <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>How can we help?</h1>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 16 }}>Find answers about rides, payments, safety, and more.</p>
          </div>

          {/* Search */}
          <div style={{ position: 'relative', marginBottom: 32 }}>
            <span style={{ position: 'absolute', left: 16, top: '50%', transform: 'translateY(-50%)', fontSize: 18, opacity: 0.4 }}>🔍</span>
            <input style={inp} placeholder="Search help articles..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>

          {/* Category filter */}
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginBottom: 32 }}>
            {CATS.map(c => (
              <button key={c} onClick={() => setCat(c)} style={{
                padding: '8px 18px', borderRadius: 50, fontSize: 13, fontWeight: 600, cursor: 'pointer',
                background: cat === c ? 'linear-gradient(135deg,#ff6b00,#ff9500)' : 'rgba(255,255,255,0.05)',
                border: cat === c ? 'none' : '1px solid rgba(255,255,255,0.1)',
                color: cat === c ? '#fff' : 'rgba(255,255,255,0.55)',
              }}>{c}</button>
            ))}
          </div>

          {/* FAQ list */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {filtered.length === 0 && (
              <div style={{ textAlign: 'center', padding: '60px 0', color: 'rgba(255,255,255,0.3)', fontSize: 16 }}>No results found. Try different keywords.</div>
            )}
            {filtered.map((f, i) => {
              const id = `${f.cat}-${i}`;
              const isOpen = open === id;
              return (
                <div key={id} style={{ background: 'rgba(255,255,255,0.03)', border: `1px solid ${isOpen ? 'rgba(255,107,0,0.3)' : 'rgba(255,255,255,0.07)'}`, borderRadius: 16, overflow: 'hidden', transition: 'border-color 0.2s' }}>
                  <button onClick={() => setOpen(isOpen ? null : id)} style={{ width: '100%', background: 'none', border: 'none', padding: '20px 24px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer', gap: 16 }}>
                    <div style={{ textAlign: 'left' }}>
                      <span style={{ fontSize: 10, fontWeight: 700, color: '#ff6b00', letterSpacing: '1px', display: 'block', marginBottom: 4 }}>{f.cat.toUpperCase()}</span>
                      <span style={{ fontSize: 16, fontWeight: 600, color: '#fff' }}>{f.q}</span>
                    </div>
                    <span style={{ fontSize: 20, color: isOpen ? '#ff6b00' : 'rgba(255,255,255,0.3)', flexShrink: 0, transition: 'transform 0.2s', transform: isOpen ? 'rotate(45deg)' : 'none' }}>+</span>
                  </button>
                  {isOpen && (
                    <div style={{ padding: '0 24px 20px', color: 'rgba(255,255,255,0.6)', lineHeight: 1.7, fontSize: 15 }}>{f.a}</div>
                  )}
                </div>
              );
            })}
          </div>

          {/* Contact section */}
          <div style={{ marginTop: 60, background: 'rgba(255,107,0,0.06)', border: '1px solid rgba(255,107,0,0.15)', borderRadius: 20, padding: '36px' }}>
            <h2 style={{ fontSize: 22, fontWeight: 800, marginBottom: 8 }}>Still need help?</h2>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 15, marginBottom: 28 }}>Email us and we will reply as soon as we can. Support is by email; we do not offer 24/7 support.</p>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 16 }}>
              {[
                { icon: '✉️', label: 'Email Support', val: 'support@dollor.ai', href: 'mailto:support@dollor.ai' },
                { icon: '🗑️', label: 'Delete Account', val: 'How to delete', href: '/delete-account' },
                { icon: '📸', label: 'Instagram', val: '@dollorai', href: 'https://instagram.com/dollorai' },
              ].map(c => (
                <a key={c.label} href={c.href} target={c.href.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 14, padding: '20px', textDecoration: 'none' }}>
                  <span style={{ fontSize: 28 }}>{c.icon}</span>
                  <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.35)', fontWeight: 600 }}>{c.label}</span>
                  <span style={{ fontSize: 14, color: '#ff9500', fontWeight: 700 }}>{c.val}</span>
                </a>
              ))}
            </div>
          </div>
        </div>
      </div>
      <PublicFooter />
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800;900&display=swap');
        * { margin:0; padding:0; box-sizing:border-box; }
        body { background:#0a0a0f; }
        input::placeholder { color:rgba(255,255,255,0.2); }
        input:focus { border-color:rgba(255,107,0,0.5) !important; }
      `}</style>
    </div>
  );
};

export default HelpSupport;
