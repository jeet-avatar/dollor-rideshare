import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, Link } from 'react-router-dom';

const API_URL = import.meta.env.VITE_API_URL || 'https://api.dollor.ai';

const LandingPage: React.FC = () => {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [role, setRole] = useState<'rider' | 'driver' | 'volunteer' | 'partner' | 'investor' | 'state_launch'>('rider');
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState('');
  const [waitlistCount, setWaitlistCount] = useState<number | null>(null);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const waitlistRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    fetch(`${API_URL}/api/waitlist/count`)
      .then(r => r.json())
      .then(d => setWaitlistCount(d.count))
      .catch(() => {});
  }, []);

  const scrollToWaitlist = () => {
    waitlistRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    setSubmitting(true);
    setError('');
    try {
      const res = await fetch(`${API_URL}/api/waitlist`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, name, role }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || 'Something went wrong');
      setSubmitted(true);
      setWaitlistCount(c => (c ?? 0) + 1);
    } catch (err: any) {
      setError(err.message || 'Could not save. Please try again.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div style={{ fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif", background: '#0a0a0f', color: '#fff', overflowX: 'hidden' }}>

      {/* NAV */}
      <nav style={{
        position: 'fixed', top: 0, left: 0, right: 0, zIndex: 100,
        background: scrolled ? 'rgba(10,10,15,0.95)' : 'transparent',
        backdropFilter: scrolled ? 'blur(20px)' : 'none',
        borderBottom: scrolled ? '1px solid rgba(255,255,255,0.06)' : 'none',
        transition: 'all 0.3s ease',
        padding: '18px 0',
      }}>
        <div style={{ maxWidth: 1200, margin: '0 auto', padding: '0 24px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 36, background: 'linear-gradient(135deg, #ff6b00, #ff9500)', borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, fontWeight: 900 }}>D</div>
            <span style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-0.5px' }}>dollor<span style={{ color: '#ff6b00' }}>.ai</span></span>
          </div>
          <div style={{ display: 'flex', gap: 32, alignItems: 'center' }}>
            <div className="nav-links-desktop" style={{ display: 'flex', gap: 28 }}>
              <a href="#why" style={{ color: 'rgba(255,255,255,0.7)', textDecoration: 'none', fontSize: 15, fontWeight: 500 }}>Why Dollor</a>
              <Link to="/driver/apply" style={{ color: 'rgba(255,255,255,0.7)', textDecoration: 'none', fontSize: 15, fontWeight: 500 }}>Drive with Us</Link>
              <a href="#partner" style={{ color: 'rgba(255,255,255,0.7)', textDecoration: 'none', fontSize: 15, fontWeight: 500 }}>Partner</a>
            </div>
            <Link to="/customer/login" style={{
              background: 'linear-gradient(135deg, #ff6b00, #ff9500)',
              color: '#fff', borderRadius: 10, padding: '10px 22px',
              fontSize: 14, fontWeight: 700, textDecoration: 'none', letterSpacing: '0.2px',
            }}>Book a Ride →</Link>
          </div>
        </div>
      </nav>

      {/* HERO */}
      <section style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '120px 24px 80px', textAlign: 'center', position: 'relative', overflow: 'hidden' }}>
        {/* bg glows */}
        <div style={{ position: 'absolute', top: '10%', left: '50%', transform: 'translateX(-50%)', width: 700, height: 700, background: 'radial-gradient(circle, rgba(255,107,0,0.12) 0%, transparent 70%)', pointerEvents: 'none' }} />
        <div style={{ position: 'absolute', bottom: '5%', right: '5%', width: 400, height: 400, background: 'radial-gradient(circle, rgba(139,92,246,0.08) 0%, transparent 70%)', pointerEvents: 'none' }} />

        {/* Badge */}
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.12)', border: '1px solid rgba(255,107,0,0.3)', color: '#ff9500', borderRadius: 50, padding: '8px 20px', fontSize: 13, fontWeight: 600, marginBottom: 32, letterSpacing: '0.3px' }}>
          <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#ff6b00', display: 'inline-block', animation: 'pulse 2s infinite' }} />
          WEB APP LIVE · CALIFORNIA RIDESHARE MARKETPLACE
        </div>

        <h1 style={{ fontSize: 'clamp(36px, 7vw, 80px)', fontWeight: 900, lineHeight: 1.05, marginBottom: 24, letterSpacing: '-2px', maxWidth: 900 }}>
          We're coming to<br />
          <span style={{ background: 'linear-gradient(135deg, #ff6b00, #ff9500, #ffcc00)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>save California.</span>
        </h1>

        <p style={{ fontSize: 'clamp(16px, 2.5vw, 22px)', color: 'rgba(255,255,255,0.6)', maxWidth: 620, lineHeight: 1.7, marginBottom: 16 }}>
          Riders post an offer and independent drivers bid. Dollor charges a flat <strong style={{ color: '#fff' }}>$1–$3</strong> connection fee by fare tier, not a percentage of the fare.
          Rideshare in <strong style={{ color: '#fff' }}>California</strong>.
        </p>

        <p style={{ fontSize: 14, color: 'rgba(255,255,255,0.35)', marginBottom: 48, letterSpacing: '0.3px' }}>
          Peer-to-peer rideshare · 5-minute bidding window · Tips go 100% to the driver
        </p>

        <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', justifyContent: 'center', marginBottom: 32 }}>
          <Link to="/customer/login" style={{
            display: 'inline-flex', alignItems: 'center', gap: 8,
            background: 'linear-gradient(135deg, #ff6b00, #ff9500)',
            color: '#fff', borderRadius: 14, padding: '18px 40px',
            fontSize: 17, fontWeight: 800, textDecoration: 'none', letterSpacing: '-0.2px',
            boxShadow: '0 0 40px rgba(255,107,0,0.4)',
          }}>
            📍 Book a Ride Now
          </Link>
          <Link to="/driver/login" style={{
            display: 'inline-flex', alignItems: 'center', gap: 8,
            background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.15)',
            color: '#fff', borderRadius: 14, padding: '18px 40px',
            fontSize: 17, fontWeight: 700, textDecoration: 'none',
          }}>
            🚗 Drive with Dollor
          </Link>
        </div>
        <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.3)', marginBottom: 48 }}>
          Use on any browser · iOS app under App Store review
        </p>

        {/* Trust badges */}
        <div style={{ display: 'flex', gap: 32, flexWrap: 'wrap', justifyContent: 'center', alignItems: 'center' }}>
          {[
            { icon: '🤝', text: 'Riders post an offer, drivers bid' },
            { icon: '✅', text: 'Drivers need a cleared Checkr check to go online' },
            { icon: '🌐', text: 'Web App Live Now' },
          ].map(b => (
            <div key={b.text} style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'rgba(255,255,255,0.5)', fontSize: 14 }}>
              <span>{b.icon}</span> {b.text}
            </div>
          ))}
        </div>
      </section>

      {/* STATS STRIP */}
      <div style={{ borderTop: '1px solid rgba(255,255,255,0.06)', borderBottom: '1px solid rgba(255,255,255,0.06)', padding: '40px 24px' }}>
        <div style={{ maxWidth: 900, margin: '0 auto', display: 'flex', gap: 0, flexWrap: 'wrap', justifyContent: 'center' }}>
          {[
            { value: '$1–$3', label: 'Flat connection fee per ride', sub: 'By fare tier, not a %' },
            { value: '100%', label: 'Tips kept by driver', sub: 'Every cent' },
            { value: '5 min', label: 'Bidding window', sub: 'Accept, counter or decline' },
            { value: '$0.05', label: 'CPUC Access for All charge', sub: 'Each for rider and driver' },
          ].map((s, i) => (
            <div key={i} style={{ textAlign: 'center', padding: '12px 40px', borderRight: i < 3 ? '1px solid rgba(255,255,255,0.06)' : 'none' }}>
              <div style={{ fontSize: 'clamp(28px,4vw,42px)', fontWeight: 900, background: 'linear-gradient(135deg,#ff6b00,#ffcc00)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>{s.value}</div>
              <div style={{ fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,0.8)', marginBottom: 2 }}>{s.label}</div>
              <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.35)' }}>{s.sub}</div>
            </div>
          ))}
        </div>
      </div>

      {/* WHY DOLLOR */}
      <section id="why" style={{ padding: '100px 24px' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto' }}>
          <div style={{ textAlign: 'center', marginBottom: 64 }}>
            <div style={{ color: '#ff6b00', fontSize: 13, fontWeight: 700, letterSpacing: '2px', marginBottom: 12 }}>WHY DOLLOR</div>
            <h2 style={{ fontSize: 'clamp(28px,4vw,48px)', fontWeight: 900, letterSpacing: '-1px', marginBottom: 16 }}>Built different. For everyone.</h2>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 17, maxWidth: 520, margin: '0 auto' }}>A flat connection fee by fare tier instead of a percentage commission.</p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px,1fr))', gap: 20 }}>
            {[
              { icon: '💸', title: 'Flat Connection Fee', desc: 'A flat $1, $2 or $3 connection fee by fare tier (plus a $0.05 CPUC charge), charged to the rider and to the driver. Suggested fares include a time-of-day adjustment that is shown before you request.' },
              { icon: '🚗', title: 'Drivers Keep More', desc: 'Drivers bid their own price per trip and keep 100% of tips. The platform fee is flat, not a percentage.' },
              { icon: '🔍', title: 'Full Transparency', desc: 'See the fare and fee breakdown before you request a ride.' },
              { icon: '⚡', title: 'Bids From Nearby Drivers', desc: 'Online drivers near your pickup can bid on your request for 5 minutes. You accept, counter or decline.' },
              { icon: '🛡️', title: 'Safety First', desc: 'Drivers must complete a Checkr background check and be approved before going online. Live ride tracking and in-app chat. The iOS app adds Share trip and an emergency button that calls 911.' },
              { icon: '💳', title: 'Stripe Payouts', desc: 'Drivers are paid through Stripe after completed trips. Tips are 100% the driver\'s.' },
            ].map(card => (
              <div key={card.title} style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 20, padding: '36px 32px', transition: 'all 0.2s' }}>
                <div style={{ fontSize: 36, marginBottom: 20 }}>{card.icon}</div>
                <h3 style={{ fontSize: 19, fontWeight: 800, marginBottom: 12, letterSpacing: '-0.3px' }}>{card.title}</h3>
                <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 15, lineHeight: 1.7 }}>{card.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* COMING SOON SERVICES */}
      <section style={{ padding: '80px 24px', background: 'rgba(255,255,255,0.015)', borderTop: '1px solid rgba(255,255,255,0.06)', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ maxWidth: 1000, margin: '0 auto' }}>
          <div style={{ textAlign: 'center', marginBottom: 56 }}>
            <div style={{ color: '#ff6b00', fontSize: 13, fontWeight: 700, letterSpacing: '2px', marginBottom: 12 }}>EXPANDING SOON</div>
            <h2 style={{ fontSize: 'clamp(26px,4vw,44px)', fontWeight: 900, letterSpacing: '-1px', marginBottom: 12 }}>One app. Every journey.</h2>
            <p style={{ color: 'rgba(255,255,255,0.45)', fontSize: 16 }}>Rideshare is just the beginning. Join now to be first when we launch these.</p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px,1fr))', gap: 16 }}>
            {[
              { icon: '✈️', title: 'Airport Pickups', desc: 'Flat-rate SNA, LAX, LGB runs. Track your flight, we track your gate.' },
              { icon: '📦', title: 'Courier & Packages', desc: 'Same-day courier for businesses and individuals across California.' },
              { icon: '👑', title: 'VIP Service', desc: 'Premium vehicles, priority matching, dedicated driver availability.' },
              { icon: '🔄', title: 'Recurring Rides', desc: 'Schedule your daily commute once, ride every day automatically.' },
              { icon: '🏢', title: 'Corporate Accounts', desc: 'Centralized billing, ride approvals, and expense reporting for teams.' },
            ].map(s => (
              <div key={s.title} style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 16, padding: '28px 24px', position: 'relative' }}>
                <div style={{ position: 'absolute', top: 14, right: 14, background: 'rgba(139,92,246,0.15)', border: '1px solid rgba(139,92,246,0.3)', color: '#a78bfa', borderRadius: 50, padding: '3px 10px', fontSize: 10, fontWeight: 700, letterSpacing: '1px' }}>SOON</div>
                <div style={{ fontSize: 30, marginBottom: 14 }}>{s.icon}</div>
                <h4 style={{ fontSize: 16, fontWeight: 800, marginBottom: 8 }}>{s.title}</h4>
                <p style={{ color: 'rgba(255,255,255,0.45)', fontSize: 13, lineHeight: 1.6 }}>{s.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* DRIVER SECTION */}
      <section style={{ padding: '100px 24px' }}>
        <div style={{ maxWidth: 1000, margin: '0 auto', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 64, alignItems: 'center' }}>
          <div>
            <div style={{ color: '#ff6b00', fontSize: 13, fontWeight: 700, letterSpacing: '2px', marginBottom: 16 }}>FOR DRIVERS</div>
            <h2 style={{ fontSize: 'clamp(26px,4vw,44px)', fontWeight: 900, letterSpacing: '-1px', marginBottom: 20 }}>Your car.<br />Your rules.<br />Your earnings.</h2>
            <p style={{ color: 'rgba(255,255,255,0.55)', fontSize: 16, lineHeight: 1.8, marginBottom: 32 }}>
              Dollor charges a flat connection fee by fare tier ($1, $2 or $3) instead of a percentage. On a $20 fare the fee is $1, plus a $0.05 CPUC charge. Tips are yours.
            </p>
            {[
              'Set your own price per trip',
              'Accept only the rides you want',
              'Keep 100% of every tip',
              'Payouts through Stripe',
              'Checkr background check required before you go online',
            ].map(item => (
              <div key={item} style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
                <div style={{ width: 22, height: 22, borderRadius: '50%', background: 'rgba(255,107,0,0.15)', border: '1px solid rgba(255,107,0,0.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, color: '#ff6b00', flexShrink: 0 }}>✓</div>
                <span style={{ fontSize: 15, color: 'rgba(255,255,255,0.8)' }}>{item}</span>
              </div>
            ))}
            <Link to="/driver/apply" style={{
              display: 'inline-block', marginTop: 32,
              background: 'linear-gradient(135deg, #ff6b00, #ff9500)',
              color: '#fff', textDecoration: 'none', borderRadius: 12, padding: '16px 36px',
              fontSize: 16, fontWeight: 700,
            }}>Apply to Drive →</Link>
          </div>

          {/* earnings card */}
          <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 24, padding: 40 }}>
            <div style={{ marginBottom: 24, color: 'rgba(255,255,255,0.4)', fontSize: 13, fontWeight: 600, letterSpacing: '1px' }}>EXAMPLE — FARE, FEES AND DRIVER EARNINGS</div>
            {[
              { route: 'Irvine → LAX', fare: '$48', fee: '-$2.05', earn: '$45.95' },
              { route: 'Irvine → Newport Beach', fare: '$18', fee: '-$1.05', earn: '$16.95' },
              { route: 'Costa Mesa → Anaheim', fare: '$22', fee: '-$1.05', earn: '$20.95' },
              { route: 'Tip from a rider', fare: '$5', fee: '$0', earn: '$5.00' },
            ].map(r => (
              <div key={r.route} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 0', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.6)' }}>{r.route}</span>
                <div style={{ display: 'flex', gap: 20, alignItems: 'center' }}>
                  <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.4)', textDecoration: 'line-through' }}>{r.fare}</span>
                  <span style={{ fontSize: 13, color: '#f87171' }}>{r.fee}</span>
                  <span style={{ fontSize: 15, fontWeight: 800, color: '#4ade80', minWidth: 36, textAlign: 'right' }}>{r.earn}</span>
                </div>
              </div>
            ))}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: 20 }}>
              <span style={{ fontSize: 16, fontWeight: 700 }}>Total</span>
              <span style={{ fontSize: 26, fontWeight: 900, color: '#4ade80' }}>$88.85</span>
            </div>
            <div style={{ marginTop: 8, color: 'rgba(255,255,255,0.35)', fontSize: 12 }}>Illustrative only. Fees: $1 / $2 / $3 connection fee by fare tier plus a $0.05 CPUC charge. Fares are set by driver bids.</div>
          </div>
        </div>
      </section>

      {/* LAUNCH TIMELINE */}
      <section style={{ padding: '80px 24px', background: 'rgba(255,255,255,0.015)', borderTop: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ maxWidth: 700, margin: '0 auto', textAlign: 'center' }}>
          <div style={{ color: '#ff6b00', fontSize: 13, fontWeight: 700, letterSpacing: '2px', marginBottom: 12 }}>WHAT'S HAPPENING NOW</div>
          <h2 style={{ fontSize: 'clamp(24px,3.5vw,40px)', fontWeight: 900, letterSpacing: '-1px', marginBottom: 48 }}>We're almost there.</h2>
          <div style={{ textAlign: 'left' }}>
            {[
              { done: true, label: 'iOS App Submitted to Apple', date: 'In Review', detail: 'Customer + Driver apps awaiting App Store approval' },
              { done: false, label: 'App Store Launch', date: 'Coming Soon', detail: 'Join the waitlist to get notified the moment we go live' },
              { done: false, label: 'California Launch', date: 'Coming Soon', detail: 'Statewide rideshare launch — riders and drivers across CA' },
              { done: false, label: 'Android App', date: 'Following shortly', detail: 'Google Play submission in progress' },
              { done: false, label: 'National Expansion', date: '2027', detail: 'Texas, New York, Florida and beyond — partner with us to bring Dollor to your state' },
            ].map((item, i) => (
              <div key={i} style={{ display: 'flex', gap: 20, marginBottom: 8 }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  <div style={{ width: 32, height: 32, borderRadius: '50%', background: item.done ? 'linear-gradient(135deg,#ff6b00,#ff9500)' : 'rgba(255,255,255,0.06)', border: item.done ? 'none' : '1px solid rgba(255,255,255,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, flexShrink: 0 }}>
                    {item.done ? '✓' : '○'}
                  </div>
                  {i < 4 && <div style={{ width: 1, flex: 1, background: 'rgba(255,255,255,0.06)', margin: '4px 0', minHeight: 40 }} />}
                </div>
                <div style={{ paddingBottom: 32 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 4 }}>
                    <span style={{ fontSize: 16, fontWeight: 700, color: item.done ? '#fff' : 'rgba(255,255,255,0.5)' }}>{item.label}</span>
                    <span style={{ fontSize: 12, fontWeight: 600, color: item.done ? '#ff9500' : 'rgba(255,255,255,0.3)', background: item.done ? 'rgba(255,149,0,0.1)' : 'rgba(255,255,255,0.04)', border: `1px solid ${item.done ? 'rgba(255,149,0,0.3)' : 'rgba(255,255,255,0.08)'}`, borderRadius: 50, padding: '2px 10px' }}>{item.date}</span>
                  </div>
                  <p style={{ fontSize: 14, color: 'rgba(255,255,255,0.38)', margin: 0 }}>{item.detail}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* BE A PARTNER */}
      <section id="partner" style={{ padding: '100px 24px', background: 'rgba(255,255,255,0.015)', borderTop: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto' }}>
          <div style={{ textAlign: 'center', marginBottom: 64 }}>
            <div style={{ color: '#ff6b00', fontSize: 13, fontWeight: 700, letterSpacing: '2px', marginBottom: 12 }}>GET INVOLVED</div>
            <h2 style={{ fontSize: 'clamp(28px,4vw,52px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 16 }}>
              This is bigger than a app.<br />
              <span style={{ background: 'linear-gradient(135deg,#ff6b00,#ffcc00)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>Help us change the industry.</span>
            </h2>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 17, maxWidth: 580, margin: '0 auto', lineHeight: 1.7 }}>
              We're building a flat-fee, bid-based rideshare marketplace — we need believers, builders, and backers at our side.
            </p>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px,1fr))', gap: 20 }}>
            {[
              {
                icon: '🙋',
                color: '#3b82f6',
                title: 'Volunteers',
                desc: 'Help spread the word in your city. Street teams, social media, driver recruitment — we need boots on the ground to make California launch a success.',
                cta: 'Volunteer with us',
                to: '/get-involved?type=volunteer',
              },
              {
                icon: '🤝',
                color: '#8b5cf6',
                title: 'Business Partners',
                desc: 'Hotels, venues, airports, healthcare facilities — partner with Dollor to offer reliable, affordable rides to your customers and staff.',
                cta: 'Explore partnerships',
                to: '/get-involved?type=business',
              },
              {
                icon: '💰',
                color: '#f59e0b',
                title: 'Funders & Investors',
                desc: 'We have the license, the tech, and the model. We\'re raising to scale California and go national. If you believe drivers deserve more, let\'s talk.',
                cta: 'Request our deck',
                to: '/get-involved?type=investor',
              },
              {
                icon: '🗺️',
                color: '#10b981',
                title: 'Launch in Your State',
                desc: 'Ready to bring the $1 flat fee model to Texas, New York, or Florida? We\'re looking for state-level operators and partners to co-launch Dollor nationwide.',
                cta: 'Apply to launch',
                to: '/get-involved?type=state_launch',
              },
            ].map(card => (
              <div key={card.title} style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 24, padding: '36px 32px', display: 'flex', flexDirection: 'column' }}>
                <div style={{ width: 52, height: 52, borderRadius: 16, background: `${card.color}18`, border: `1px solid ${card.color}30`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 26, marginBottom: 20 }}>{card.icon}</div>
                <h3 style={{ fontSize: 20, fontWeight: 800, marginBottom: 12, letterSpacing: '-0.3px' }}>{card.title}</h3>
                <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 14, lineHeight: 1.7, flex: 1, marginBottom: 24 }}>{card.desc}</p>
                <Link to={card.to} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: card.color, textDecoration: 'none', fontSize: 14, fontWeight: 700, borderTop: '1px solid rgba(255,255,255,0.06)', paddingTop: 20 }}>
                  {card.cta} →
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* WAITLIST FORM */}
      <section ref={waitlistRef} style={{ padding: '100px 24px', position: 'relative', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 800, height: 800, background: 'radial-gradient(circle, rgba(255,107,0,0.08) 0%, transparent 70%)', pointerEvents: 'none' }} />
        <div style={{ maxWidth: 560, margin: '0 auto', textAlign: 'center', position: 'relative' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 24 }}>
            🔥 BE FIRST
          </div>
          <h2 style={{ fontSize: 'clamp(28px,5vw,52px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 16 }}>
            Get early access.<br />
            <span style={{ background: 'linear-gradient(135deg,#ff6b00,#ffcc00)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>Ride for less.</span>
          </h2>
          <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 16, lineHeight: 1.7, marginBottom: 40 }}>
            Join the waitlist and we'll notify you the moment Dollor goes live in California. Early members get priority access and launch-day perks.
          </p>

          {waitlistCount !== null && waitlistCount > 0 && (
            <div style={{ marginBottom: 28, fontSize: 14, color: 'rgba(255,255,255,0.4)' }}>
              <span style={{ fontWeight: 700, color: '#ff9500' }}>{waitlistCount.toLocaleString()}</span> people already on the list
            </div>
          )}

          {submitted ? (
            <div style={{ background: 'rgba(74,222,128,0.08)', border: '1px solid rgba(74,222,128,0.25)', borderRadius: 20, padding: '40px 32px' }}>
              <div style={{ fontSize: 48, marginBottom: 16 }}>🎉</div>
              <h3 style={{ fontSize: 22, fontWeight: 800, color: '#4ade80', marginBottom: 12 }}>You're on the list!</h3>
              <p style={{ color: 'rgba(255,255,255,0.55)', fontSize: 15, lineHeight: 1.6 }}>
                We'll message you the moment Dollor goes live. Watch our Instagram for daily updates on launch progress.
              </p>
              <a href="https://instagram.com/dollorai" target="_blank" rel="noopener noreferrer" style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 24, color: '#ff9500', textDecoration: 'none', fontSize: 15, fontWeight: 700 }}>
                Follow @dollorai on Instagram →
              </a>
            </div>
          ) : (
            <form onSubmit={handleSubmit} style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 24, padding: '40px 36px', textAlign: 'left' }}>
              <div style={{ marginBottom: 20 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.5)', letterSpacing: '0.5px', marginBottom: 8 }}>YOUR NAME</label>
                <input
                  type="text"
                  value={name}
                  onChange={e => setName(e.target.value)}
                  placeholder="Jane Smith"
                  style={{ width: '100%', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 12, padding: '14px 18px', color: '#fff', fontSize: 16, outline: 'none', boxSizing: 'border-box' }}
                />
              </div>
              <div style={{ marginBottom: 20 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.5)', letterSpacing: '0.5px', marginBottom: 8 }}>EMAIL ADDRESS *</label>
                <input
                  type="email"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder="you@email.com"
                  required
                  style={{ width: '100%', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 12, padding: '14px 18px', color: '#fff', fontSize: 16, outline: 'none', boxSizing: 'border-box' }}
                />
              </div>
              <div style={{ marginBottom: 32 }}>
                <label style={{ display: 'block', fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.5)', letterSpacing: '0.5px', marginBottom: 12 }}>I WANT TO</label>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 10 }}>
                  {([
                    { val: 'rider', label: '🚗 Ride' },
                    { val: 'driver', label: '💼 Drive' },
                    { val: 'volunteer', label: '🙋 Volunteer' },
                    { val: 'partner', label: '🤝 Partner' },
                    { val: 'investor', label: '💰 Invest' },
                    { val: 'state_launch', label: '🗺️ My State' },
                  ] as const).map(r => (
                    <button
                      key={r.val}
                      type="button"
                      onClick={() => setRole(r.val)}
                      style={{
                        padding: '12px 8px', borderRadius: 12, border: `1px solid ${role === r.val ? 'rgba(255,107,0,0.6)' : 'rgba(255,255,255,0.1)'}`,
                        background: role === r.val ? 'rgba(255,107,0,0.15)' : 'rgba(255,255,255,0.03)',
                        color: role === r.val ? '#ff9500' : 'rgba(255,255,255,0.5)',
                        fontWeight: 700, fontSize: 12, cursor: 'pointer',
                      }}
                    >
                      {r.label}
                    </button>
                  ))}
                </div>
              </div>
              {error && <div style={{ color: '#f87171', fontSize: 14, marginBottom: 16 }}>{error}</div>}
              <button
                type="submit"
                disabled={submitting}
                style={{
                  width: '100%', padding: '18px', borderRadius: 14,
                  background: submitting ? 'rgba(255,107,0,0.5)' : 'linear-gradient(135deg,#ff6b00,#ff9500)',
                  border: 'none', color: '#fff', fontSize: 17, fontWeight: 800,
                  cursor: submitting ? 'not-allowed' : 'pointer', letterSpacing: '-0.2px',
                  boxShadow: submitting ? 'none' : '0 0 30px rgba(255,107,0,0.35)',
                }}
              >
                {submitting ? 'Saving your spot...' : "Reserve My Spot →"}
              </button>
              <p style={{ textAlign: 'center', marginTop: 16, color: 'rgba(255,255,255,0.25)', fontSize: 12 }}>
                No spam. Just launch updates. Unsubscribe anytime.
              </p>
            </form>
          )}
        </div>
      </section>

      {/* INSTAGRAM CTA */}
      <section style={{ padding: '60px 24px', background: 'rgba(255,255,255,0.015)', borderTop: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ maxWidth: 600, margin: '0 auto', textAlign: 'center' }}>
          <div style={{ fontSize: 40, marginBottom: 16 }}>📲</div>
          <h3 style={{ fontSize: 26, fontWeight: 900, marginBottom: 12 }}>Daily launch updates on Instagram</h3>
          <p style={{ color: 'rgba(255,255,255,0.45)', fontSize: 15, marginBottom: 28 }}>
            Follow <strong style={{ color: '#fff' }}>@dollorai</strong> for behind-the-scenes updates, driver spotlights, and the exact moment we go live.
          </p>
          <a
            href="https://instagram.com/dollorai"
            target="_blank"
            rel="noopener noreferrer"
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 10,
              background: 'linear-gradient(135deg, #f09433, #e6683c, #dc2743, #cc2366, #bc1888)',
              color: '#fff', textDecoration: 'none', borderRadius: 14, padding: '16px 36px',
              fontSize: 16, fontWeight: 800,
            }}
          >
            Follow @dollorai
          </a>
        </div>
      </section>

      {/* FOOTER */}
      <footer style={{ borderTop: '1px solid rgba(255,255,255,0.06)', padding: '48px 24px 32px' }}>
        <div style={{ maxWidth: 1100, margin: '0 auto', display: 'flex', flexWrap: 'wrap', gap: 40, justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
              <div style={{ width: 32, height: 32, background: 'linear-gradient(135deg,#ff6b00,#ff9500)', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 900 }}>D</div>
              <span style={{ fontSize: 18, fontWeight: 800 }}>dollor<span style={{ color: '#ff6b00' }}>.ai</span></span>
            </div>
            <p style={{ color: 'rgba(255,255,255,0.35)', fontSize: 13, maxWidth: 280, lineHeight: 1.7 }}>
              Peer-to-peer rideshare marketplace operated by Zietra Technologies Inc., Rancho Santa Margarita, CA 92688.
            </p>
          </div>
          <div style={{ display: 'flex', gap: 56, flexWrap: 'wrap' }}>
            <div>
              <h4 style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.4)', letterSpacing: '1px', marginBottom: 16 }}>COMPANY</h4>
              {[
                { label: 'Privacy Policy', to: '/privacy' },
                { label: 'Terms of Service', to: '/terms' },
                { label: 'Zero Tolerance Policy', to: '/zero-tolerance' },
                { label: 'Safety', to: '/safety' },
              ].map(l => (
                <div key={l.label} style={{ marginBottom: 10 }}>
                  <Link to={l.to} style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none', fontSize: 14 }}>{l.label}</Link>
                </div>
              ))}
            </div>
            <div>
              <h4 style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.4)', letterSpacing: '1px', marginBottom: 16 }}>CONTACT</h4>
              {[
                { label: 'support@dollor.ai', href: 'mailto:support@dollor.ai' },
                { label: 'drivers@dollor.ai', href: 'mailto:drivers@dollor.ai' },
                { label: '@dollorai', href: 'https://instagram.com/dollorai' },
              ].map(l => (
                <div key={l.label} style={{ marginBottom: 10 }}>
                  <a href={l.href} target={l.href.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none', fontSize: 14 }}>{l.label}</a>
                </div>
              ))}
            </div>
          </div>
        </div>
        <div style={{ maxWidth: 1100, margin: '32px auto 0', paddingTop: 24, borderTop: '1px solid rgba(255,255,255,0.05)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 12 }}>
          <p style={{ color: 'rgba(255,255,255,0.25)', fontSize: 13 }}>© 2026 Zietra Technologies Inc. All rights reserved.</p>
          <p style={{ color: 'rgba(255,255,255,0.2)', fontSize: 12 }}>Zietra Technologies Inc. (DBA Dollor.ai)</p>
        </div>
      </footer>

      {/* Mobile sticky launch bar */}
      <div className="mobile-launch-bar" style={{
        display: 'none', position: 'fixed', bottom: 0, left: 0, right: 0, zIndex: 200,
        background: 'rgba(10,10,15,0.97)', backdropFilter: 'blur(20px)',
        borderTop: '1px solid rgba(255,107,0,0.2)',
        padding: '12px 16px', paddingBottom: 'max(12px, env(safe-area-inset-bottom))',
        gap: 10,
      }}>
        <Link to="/customer/login" style={{
          flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
          background: '#ff6b00', color: '#fff', borderRadius: 12, padding: '14px 16px',
          fontSize: 15, fontWeight: 800, textDecoration: 'none',
        }}>📍 Book a Ride</Link>
        <Link to="/driver/login" style={{
          flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
          background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.12)',
          color: '#fff', borderRadius: 12, padding: '14px 16px',
          fontSize: 15, fontWeight: 700, textDecoration: 'none',
        }}>🚗 Drive</Link>
      </div>

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap');
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background: #0a0a0f; }
        input::placeholder { color: rgba(255,255,255,0.25); }
        input:focus { border-color: rgba(255,107,0,0.5) !important; }
        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.5; transform: scale(0.8); }
        }
        @media (max-width: 768px) {
          .nav-links-desktop { display: none !important; }
          section > div[style*="grid-template-columns: 1fr 1fr"] { grid-template-columns: 1fr !important; }
          div[style*="grid-template-columns: 1fr 1fr"] { grid-template-columns: 1fr !important; }
          .mobile-launch-bar { display: flex !important; }
          /* Add padding so footer doesn't hide behind bar */
          footer { padding-bottom: 80px !important; }
        }
        @media (max-width: 640px) {
          div[style*="borderRight"] { border-right: none !important; border-bottom: 1px solid rgba(255,255,255,0.06); }
        }
      `}</style>
    </div>
  );
};

export default LandingPage;
