import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const API_URL = import.meta.env.VITE_API_URL || 'https://api.dollor.ai';

type Tab = 'volunteer' | 'business' | 'investor' | 'state_launch';

const TABS: { id: Tab; icon: string; label: string; color: string }[] = [
  { id: 'volunteer', icon: '🙋', label: 'Volunteer', color: '#3b82f6' },
  { id: 'business', icon: '🤝', label: 'Business Partner', color: '#8b5cf6' },
  { id: 'investor', icon: '💰', label: 'Invest / Fund', color: '#f59e0b' },
  { id: 'state_launch', icon: '🗺️', label: 'Launch My State', color: '#10b981' },
];

const inp: React.CSSProperties = {
  width: '100%', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)',
  borderRadius: 12, padding: '14px 18px', color: '#fff', fontSize: 15, outline: 'none',
  boxSizing: 'border-box', fontFamily: 'inherit',
};
const lbl: React.CSSProperties = { display: 'block', fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.35)', letterSpacing: '1.2px', marginBottom: 8 };
const field: React.CSSProperties = { marginBottom: 20 };
const sel: React.CSSProperties = { ...inp, cursor: 'pointer' };

interface FormState { name: string; email: string; [key: string]: string }

const SuccessScreen: React.FC<{ tab: Tab; email: string }> = ({ tab, email }) => {
  const msgs: Record<Tab, { title: string; body: string }> = {
    volunteer: { title: 'You\'re in!', body: 'Thank you for volunteering. We\'ll reach out within 48 hours with next steps and how you can help launch Dollor in California.' },
    business: { title: 'Partnership request received!', body: 'Our partnerships team will review your submission and get back to you within 2 business days.' },
    investor: { title: 'We\'ll be in touch!', body: 'Thank you for your interest in backing Dollor. Our team will send you our latest deck and reach out to set up a call.' },
    state_launch: { title: 'Let\'s build this together!', body: 'We\'re excited you want to bring Dollor to your state. Our expansion team will reach out within 48 hours.' },
  };
  const m = msgs[tab];
  return (
    <div style={{ background: 'rgba(74,222,128,0.07)', border: '1px solid rgba(74,222,128,0.2)', borderRadius: 20, padding: '48px 36px', textAlign: 'center' }}>
      <div style={{ fontSize: 56, marginBottom: 16 }}>🎉</div>
      <h3 style={{ fontSize: 24, fontWeight: 900, color: '#4ade80', marginBottom: 12 }}>{m.title}</h3>
      <p style={{ color: 'rgba(255,255,255,0.55)', fontSize: 15, lineHeight: 1.7, marginBottom: 8 }}>{m.body}</p>
      <p style={{ color: 'rgba(255,255,255,0.3)', fontSize: 13 }}>Confirmation sent to {email}</p>
      <a href="https://instagram.com/dollorai" target="_blank" rel="noopener noreferrer" style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 28, color: '#ff9500', textDecoration: 'none', fontSize: 14, fontWeight: 700 }}>
        Follow @dollorai for updates →
      </a>
    </div>
  );
};

const VolunteerForm: React.FC<{ onDone: (email: string) => void }> = ({ onDone }) => {
  const [f, setF] = useState({ name: '', email: '', city: '', availability: '', skills: [] as string[], message: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }));
  const toggleSkill = (s: string) => setF(p => ({ ...p, skills: p.skills.includes(s) ? p.skills.filter(x => x !== s) : [...p.skills, s] }));
  const SKILLS = ['Street Team', 'Social Media', 'Driver Recruitment', 'Community Events', 'Translation/Languages', 'Marketing Design'];

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    try {
      const details = `City: ${f.city} | Availability: ${f.availability} | Skills: ${f.skills.join(', ')} | Message: ${f.message}`;
      const res = await fetch(`${API_URL}/api/waitlist`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: f.email, name: `${f.name} [VOL] ${details}`, role: 'volunteer' }),
      });
      if (!res.ok) throw new Error('Submission failed. Please try again.');
      onDone(f.email);
    } catch (err: any) { setError(err.message); } finally { setLoading(false); }
  };

  return (
    <form onSubmit={submit}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>FULL NAME</label><input style={inp} required value={f.name} onChange={e => set('name', e.target.value)} placeholder="Jane Smith" /></div>
        <div style={field}><label style={lbl}>EMAIL</label><input style={inp} type="email" required value={f.email} onChange={e => set('email', e.target.value)} placeholder="you@email.com" /></div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>YOUR CITY</label><input style={inp} value={f.city} onChange={e => set('city', e.target.value)} placeholder="Los Angeles, CA" /></div>
        <div style={field}><label style={lbl}>AVAILABILITY</label>
          <select style={sel} value={f.availability} onChange={e => set('availability', e.target.value)}>
            <option value="">Select...</option>
            <option>Weekends only</option><option>Evenings</option><option>Full-time</option><option>Flexible</option>
          </select>
        </div>
      </div>
      <div style={field}>
        <label style={lbl}>HOW CAN YOU HELP? (SELECT ALL THAT APPLY)</label>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 4 }}>
          {SKILLS.map(s => (
            <button key={s} type="button" onClick={() => toggleSkill(s)} style={{ padding: '8px 16px', borderRadius: 50, fontSize: 13, fontWeight: 600, cursor: 'pointer', background: f.skills.includes(s) ? 'rgba(59,130,246,0.2)' : 'rgba(255,255,255,0.04)', border: `1px solid ${f.skills.includes(s) ? 'rgba(59,130,246,0.5)' : 'rgba(255,255,255,0.1)'}`, color: f.skills.includes(s) ? '#93c5fd' : 'rgba(255,255,255,0.5)' }}>{s}</button>
          ))}
        </div>
      </div>
      <div style={field}><label style={lbl}>ANYTHING ELSE WE SHOULD KNOW?</label><textarea style={{ ...inp, minHeight: 90, resize: 'vertical' }} value={f.message} onChange={e => set('message', e.target.value)} placeholder="Tell us about yourself, your community connections, languages you speak..." /></div>
      {error && <p style={{ color: '#f87171', fontSize: 14, marginBottom: 16 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ width: '100%', padding: '16px', borderRadius: 14, background: loading ? 'rgba(59,130,246,0.4)' : 'linear-gradient(135deg,#3b82f6,#6366f1)', border: 'none', color: '#fff', fontSize: 16, fontWeight: 800, cursor: loading ? 'not-allowed' : 'pointer' }}>
        {loading ? 'Submitting...' : 'Join as a Volunteer →'}
      </button>
    </form>
  );
};

const BusinessForm: React.FC<{ onDone: (email: string) => void }> = ({ onDone }) => {
  const [f, setF] = useState({ name: '', email: '', company: '', industry: '', city: '', partnership: '', message: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    try {
      const details = `Company: ${f.company} | Industry: ${f.industry} | City: ${f.city} | Partnership: ${f.partnership} | Message: ${f.message}`;
      const res = await fetch(`${API_URL}/api/waitlist`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: f.email, name: `${f.name} [BIZ] ${details}`, role: 'partner' }),
      });
      if (!res.ok) throw new Error('Submission failed. Please try again.');
      onDone(f.email);
    } catch (err: any) { setError(err.message); } finally { setLoading(false); }
  };

  return (
    <form onSubmit={submit}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>YOUR NAME</label><input style={inp} required value={f.name} onChange={e => set('name', e.target.value)} placeholder="Jane Smith" /></div>
        <div style={field}><label style={lbl}>WORK EMAIL</label><input style={inp} type="email" required value={f.email} onChange={e => set('email', e.target.value)} placeholder="jane@company.com" /></div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>COMPANY NAME</label><input style={inp} required value={f.company} onChange={e => set('company', e.target.value)} placeholder="Acme Corp" /></div>
        <div style={field}><label style={lbl}>INDUSTRY</label>
          <select style={sel} value={f.industry} onChange={e => set('industry', e.target.value)}>
            <option value="">Select...</option>
            <option>Hotel / Hospitality</option><option>Airport / Transportation Hub</option><option>Healthcare</option>
            <option>Corporate / Enterprise</option><option>Events & Venues</option><option>Real Estate</option>
            <option>Education</option><option>Retail</option><option>Other</option>
          </select>
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>CITY / REGION</label><input style={inp} value={f.city} onChange={e => set('city', e.target.value)} placeholder="Los Angeles, CA" /></div>
        <div style={field}><label style={lbl}>PARTNERSHIP TYPE</label>
          <select style={sel} value={f.partnership} onChange={e => set('partnership', e.target.value)}>
            <option value="">Select...</option>
            <option>Employee Transportation</option><option>Guest Rides</option><option>Event Shuttle</option>
            <option>Patient Transport</option><option>Corporate Accounts</option><option>Reseller / Affiliate</option><option>Other</option>
          </select>
        </div>
      </div>
      <div style={field}><label style={lbl}>TELL US MORE</label><textarea style={{ ...inp, minHeight: 100, resize: 'vertical' }} value={f.message} onChange={e => set('message', e.target.value)} placeholder="What does your team need? How many rides per month? Any specific requirements?" /></div>
      {error && <p style={{ color: '#f87171', fontSize: 14, marginBottom: 16 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ width: '100%', padding: '16px', borderRadius: 14, background: loading ? 'rgba(139,92,246,0.4)' : 'linear-gradient(135deg,#8b5cf6,#a855f7)', border: 'none', color: '#fff', fontSize: 16, fontWeight: 800, cursor: loading ? 'not-allowed' : 'pointer' }}>
        {loading ? 'Submitting...' : 'Request Partnership →'}
      </button>
    </form>
  );
};

const InvestorForm: React.FC<{ onDone: (email: string) => void }> = ({ onDone }) => {
  const [f, setF] = useState({ name: '', email: '', firm: '', role: '', checkSize: '', focus: '', message: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    try {
      const details = `Firm: ${f.firm} | Role: ${f.role} | Check: ${f.checkSize} | Focus: ${f.focus} | Message: ${f.message}`;
      const res = await fetch(`${API_URL}/api/waitlist`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: f.email, name: `${f.name} [INV] ${details}`, role: 'investor' }),
      });
      if (!res.ok) throw new Error('Submission failed. Please try again.');
      onDone(f.email);
    } catch (err: any) { setError(err.message); } finally { setLoading(false); }
  };

  return (
    <form onSubmit={submit}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>FULL NAME</label><input style={inp} required value={f.name} onChange={e => set('name', e.target.value)} placeholder="Jane Smith" /></div>
        <div style={field}><label style={lbl}>EMAIL</label><input style={inp} type="email" required value={f.email} onChange={e => set('email', e.target.value)} placeholder="jane@vc.com" /></div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>FIRM / FUND NAME</label><input style={inp} value={f.firm} onChange={e => set('firm', e.target.value)} placeholder="Sequoia Capital (or Angel)" /></div>
        <div style={field}><label style={lbl}>YOUR ROLE</label>
          <select style={sel} value={f.role} onChange={e => set('role', e.target.value)}>
            <option value="">Select...</option>
            <option>Angel Investor</option><option>VC Partner</option><option>Family Office</option>
            <option>Strategic Investor</option><option>Accelerator</option><option>Other</option>
          </select>
        </div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>CHECK SIZE RANGE</label>
          <select style={sel} value={f.checkSize} onChange={e => set('checkSize', e.target.value)}>
            <option value="">Select...</option>
            <option>Under $50K</option><option>$50K – $250K</option><option>$250K – $1M</option>
            <option>$1M – $5M</option><option>$5M+</option>
          </select>
        </div>
        <div style={field}><label style={lbl}>INVESTMENT FOCUS</label>
          <select style={sel} value={f.focus} onChange={e => set('focus', e.target.value)}>
            <option value="">Select...</option>
            <option>Mobility / Transportation</option><option>Marketplace</option><option>AI / Tech</option>
            <option>Consumer</option><option>Gig Economy</option><option>Generalist</option>
          </select>
        </div>
      </div>
      <div style={field}><label style={lbl}>MESSAGE (OPTIONAL)</label><textarea style={{ ...inp, minHeight: 90, resize: 'vertical' }} value={f.message} onChange={e => set('message', e.target.value)} placeholder="What excites you about Dollor? Any specific questions before a call?" /></div>
      {error && <p style={{ color: '#f87171', fontSize: 14, marginBottom: 16 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ width: '100%', padding: '16px', borderRadius: 14, background: loading ? 'rgba(245,158,11,0.4)' : 'linear-gradient(135deg,#f59e0b,#f97316)', border: 'none', color: '#fff', fontSize: 16, fontWeight: 800, cursor: loading ? 'not-allowed' : 'pointer' }}>
        {loading ? 'Submitting...' : 'Request Our Deck →'}
      </button>
    </form>
  );
};

const StateLaunchForm: React.FC<{ onDone: (email: string) => void }> = ({ onDone }) => {
  const [f, setF] = useState({ name: '', email: '', state: '', city: '', background: '', drivers: '', message: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }));

  const STATES = ['Alabama','Alaska','Arizona','Arkansas','Colorado','Connecticut','Delaware','Florida','Georgia','Hawaii','Idaho','Illinois','Indiana','Iowa','Kansas','Kentucky','Louisiana','Maine','Maryland','Massachusetts','Michigan','Minnesota','Mississippi','Missouri','Montana','Nebraska','Nevada','New Hampshire','New Jersey','New Mexico','New York','North Carolina','North Dakota','Ohio','Oklahoma','Oregon','Pennsylvania','Rhode Island','South Carolina','South Dakota','Tennessee','Texas','Utah','Vermont','Virginia','Washington','West Virginia','Wisconsin','Wyoming'];

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    try {
      const details = `State: ${f.state} | City: ${f.city} | Background: ${f.background} | Drivers: ${f.drivers} | Message: ${f.message}`;
      const res = await fetch(`${API_URL}/api/waitlist`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: f.email, name: `${f.name} [STATE] ${details}`, role: 'state_launch' }),
      });
      if (!res.ok) throw new Error('Submission failed. Please try again.');
      onDone(f.email);
    } catch (err: any) { setError(err.message); } finally { setLoading(false); }
  };

  return (
    <form onSubmit={submit}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>FULL NAME</label><input style={inp} required value={f.name} onChange={e => set('name', e.target.value)} placeholder="Jane Smith" /></div>
        <div style={field}><label style={lbl}>EMAIL</label><input style={inp} type="email" required value={f.email} onChange={e => set('email', e.target.value)} placeholder="you@email.com" /></div>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div style={field}><label style={lbl}>TARGET STATE</label>
          <select style={sel} required value={f.state} onChange={e => set('state', e.target.value)}>
            <option value="">Select state...</option>
            {STATES.map(s => <option key={s}>{s}</option>)}
          </select>
        </div>
        <div style={field}><label style={lbl}>PRIMARY CITY</label><input style={inp} value={f.city} onChange={e => set('city', e.target.value)} placeholder="Austin, TX" /></div>
      </div>
      <div style={field}><label style={lbl}>YOUR BACKGROUND</label>
        <select style={sel} value={f.background} onChange={e => set('background', e.target.value)}>
          <option value="">Select...</option>
          <option>Transportation / TNC operator</option><option>Entrepreneur / Business owner</option>
          <option>Driver community organizer</option><option>Investor / Funder</option>
          <option>Local government / Policy</option><option>Other</option>
        </select>
      </div>
      <div style={field}><label style={lbl}>HOW MANY DRIVERS CAN YOU BRING?</label>
        <select style={sel} value={f.drivers} onChange={e => set('drivers', e.target.value)}>
          <option value="">Select...</option>
          <option>I'm a driver myself</option><option>10–50 drivers</option><option>50–200 drivers</option>
          <option>200–500 drivers</option><option>500+ drivers</option>
        </select>
      </div>
      <div style={field}><label style={lbl}>WHY DO YOU WANT TO BRING DOLLOR TO YOUR STATE?</label><textarea style={{ ...inp, minHeight: 110, resize: 'vertical' }} required value={f.message} onChange={e => set('message', e.target.value)} placeholder="Tell us about the rideshare landscape in your area, what's broken, and how you'd help launch..." /></div>
      {error && <p style={{ color: '#f87171', fontSize: 14, marginBottom: 16 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ width: '100%', padding: '16px', borderRadius: 14, background: loading ? 'rgba(16,185,129,0.4)' : 'linear-gradient(135deg,#10b981,#059669)', border: 'none', color: '#fff', fontSize: 16, fontWeight: 800, cursor: loading ? 'not-allowed' : 'pointer' }}>
        {loading ? 'Submitting...' : 'Apply to Launch Dollor →'}
      </button>
    </form>
  );
};

const DESCRIPTIONS: Record<Tab, { headline: string; sub: string }> = {
  volunteer: { headline: 'Help us launch California', sub: 'Street teams, social media, driver recruitment — we need passionate people on the ground to make this launch a success.' },
  business: { headline: 'Partner your business with Dollor', sub: 'Hotels, airports, healthcare facilities, corporates — offer affordable, reliable rides to your customers and staff.' },
  investor: { headline: 'Back the $1 revolution', sub: 'We have the license, the tech, and the model. We\'re raising to scale California and go national. Let\'s talk.' },
  state_launch: { headline: 'Bring Dollor to your state', sub: 'Texas, New York, Florida — we\'re looking for operators and community leaders to co-launch the $1 flat fee model nationwide.' },
};

const GetInvolved: React.FC = () => {
  const [searchParams] = useSearchParams();
  const [tab, setTab] = useState<Tab>((searchParams.get('type') as Tab) || 'volunteer');
  const [done, setDone] = useState(false);
  const [doneEmail, setDoneEmail] = useState('');

  useEffect(() => {
    const t = searchParams.get('type') as Tab;
    if (t && TABS.find(x => x.id === t)) setTab(t);
  }, [searchParams]);

  const activeColor = TABS.find(t => t.id === tab)?.color || '#ff6b00';
  const desc = DESCRIPTIONS[tab];

  const handleDone = (email: string) => { setDoneEmail(email); setDone(true); };

  return (
    <div style={publicPageStyle}>
      <PublicNav ctaLabel="Join Waitlist" ctaTo="/#waitlist" />
      <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
        <div style={{ maxWidth: 700, margin: '0 auto' }}>

          {/* Header */}
          <div style={{ textAlign: 'center', marginBottom: 48 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>🤝 GET INVOLVED</div>
            <h1 style={{ fontSize: 'clamp(28px,5vw,48px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 12 }}>Be part of the movement.</h1>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 16, lineHeight: 1.7 }}>Help us bring flat-fee, bid-based rideshare to more riders and drivers.</p>
          </div>

          {/* Tab selector */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 10, marginBottom: 40 }}>
            {TABS.map(t => (
              <button key={t.id} onClick={() => { setTab(t.id); setDone(false); }} style={{
                padding: '14px 8px', borderRadius: 14, cursor: 'pointer', textAlign: 'center',
                background: tab === t.id ? `${t.color}18` : 'rgba(255,255,255,0.03)',
                border: `1px solid ${tab === t.id ? `${t.color}50` : 'rgba(255,255,255,0.08)'}`,
                color: tab === t.id ? '#fff' : 'rgba(255,255,255,0.4)',
                transition: 'all 0.2s',
              }}>
                <div style={{ fontSize: 24, marginBottom: 6 }}>{t.icon}</div>
                <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: '0.3px' }}>{t.label}</div>
              </button>
            ))}
          </div>

          {/* Active tab card */}
          <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 24, padding: '36px' }}>
            <div style={{ marginBottom: 32 }}>
              <h2 style={{ fontSize: 22, fontWeight: 800, marginBottom: 8 }}>{desc.headline}</h2>
              <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 15, lineHeight: 1.6 }}>{desc.sub}</p>
            </div>

            {done ? (
              <SuccessScreen tab={tab} email={doneEmail} />
            ) : (
              <>
                {tab === 'volunteer' && <VolunteerForm onDone={handleDone} />}
                {tab === 'business' && <BusinessForm onDone={handleDone} />}
                {tab === 'investor' && <InvestorForm onDone={handleDone} />}
                {tab === 'state_launch' && <StateLaunchForm onDone={handleDone} />}
              </>
            )}
          </div>

          {/* Other ways */}
          <div style={{ marginTop: 32, display: 'grid', gridTemplateColumns: 'repeat(2,1fr)', gap: 12 }}>
            {[
              { icon: '✉️', label: 'General inquiries', val: 'hello@dollor.ai', href: 'mailto:hello@dollor.ai' },
              { icon: '📸', label: 'Follow for updates', val: '@dollorai', href: 'https://instagram.com/dollorai' },
            ].map(c => (
              <a key={c.label} href={c.href} target={c.href.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer" style={{ display: 'flex', gap: 12, alignItems: 'center', background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 14, padding: '16px 20px', textDecoration: 'none' }}>
                <span style={{ fontSize: 22 }}>{c.icon}</span>
                <div>
                  <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontWeight: 600, marginBottom: 2 }}>{c.label}</div>
                  <div style={{ fontSize: 13, color: '#ff9500', fontWeight: 700 }}>{c.val}</div>
                </div>
              </a>
            ))}
          </div>
        </div>
      </div>
      <PublicFooter />
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800;900&display=swap');
        * { margin:0; padding:0; box-sizing:border-box; }
        body { background:#0a0a0f; }
        input::placeholder, textarea::placeholder { color:rgba(255,255,255,0.2); }
        input:focus, select:focus, textarea:focus { border-color:rgba(255,107,0,0.4) !important; }
        select option { background:#1a1a2a; color:#fff; }
      `}</style>
    </div>
  );
};

export default GetInvolved;
