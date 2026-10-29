import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import axios from 'axios';
import { getApiUrl } from '../../api/api';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const inp: React.CSSProperties = {
  width: '100%', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)',
  borderRadius: 12, padding: '14px 18px', color: '#fff', fontSize: 16, outline: 'none',
  boxSizing: 'border-box', fontFamily: 'inherit',
};
const label: React.CSSProperties = { display: 'block', fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.4)', letterSpacing: '1px', marginBottom: 8 };
const field: React.CSSProperties = { marginBottom: 20 };
const btn = (active = true): React.CSSProperties => ({
  width: '100%', padding: '16px', borderRadius: 14,
  background: active ? 'linear-gradient(135deg,#ff6b00,#ff9500)' : 'rgba(255,255,255,0.06)',
  border: active ? 'none' : '1px solid rgba(255,255,255,0.1)',
  color: active ? '#fff' : 'rgba(255,255,255,0.4)',
  fontSize: 16, fontWeight: 800, cursor: active ? 'pointer' : 'default',
  boxShadow: active ? '0 0 24px rgba(255,107,0,0.3)' : 'none',
});

const DriverApplication: React.FC = () => {
  const navigate = useNavigate();
  const API_URL = getApiUrl();
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState({
    first_name: '', last_name: '', email: '', phone: '',
    password: '', vehicle_type: 'car', license_number: '',
    date_of_birth: '', agree_terms: false, agree_verification: false,
  });

  const set = (k: string, v: string | boolean) => setForm(f => ({ ...f, [k]: v }));

  const handleSubmit = async () => {
    setLoading(true);
    setError('');
    try {
      const response = await axios.post(`${API_URL}/api/auth/driver/register`, {
        email: form.email, password: form.password,
        first_name: form.first_name, last_name: form.last_name,
        phone: form.phone, vehicle_type: form.vehicle_type,
        license_number: form.license_number, date_of_birth: form.date_of_birth,
      });
      localStorage.setItem('driver_token', response.data.access_token);
      localStorage.setItem('driver_id', response.data.driver_id);
      localStorage.setItem('driver_code', response.data.driver_code);
      setStep(3);
    } catch (err: any) {
      const detail = err.response?.data?.detail;
      setError(typeof detail === 'string' ? detail : Array.isArray(detail) ? detail[0]?.msg : 'Registration failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  // ── Success ──
  if (step === 3) {
    return (
      <div style={publicPageStyle}>
        <PublicNav />
        <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '120px 24px 80px' }}>
          <div style={{ textAlign: 'center', maxWidth: 480 }}>
            <div style={{ fontSize: 72, marginBottom: 24 }}>🎉</div>
            <h1 style={{ fontSize: 36, fontWeight: 900, letterSpacing: '-1px', marginBottom: 16 }}>You're in!</h1>
            <p style={{ color: 'rgba(255,255,255,0.55)', fontSize: 17, lineHeight: 1.7, marginBottom: 32 }}>
              Your driver application has been submitted. We'll review your details and reach out with next steps, including your background check.
            </p>
            <div style={{ background: 'rgba(255,107,0,0.08)', border: '1px solid rgba(255,107,0,0.2)', borderRadius: 16, padding: '24px 28px', marginBottom: 32, textAlign: 'left' }}>
              <h3 style={{ fontSize: 16, fontWeight: 700, marginBottom: 16, color: '#ff9500' }}>What happens next</h3>
              {['Email confirmation sent to ' + form.email, 'Complete your Checkr background check', 'Upload your license and insurance in the driver app', 'Once approved and your check clears, you can go online'].map((s, i) => (
                <div key={i} style={{ display: 'flex', gap: 12, alignItems: 'flex-start', marginBottom: 12 }}>
                  <div style={{ width: 24, height: 24, borderRadius: '50%', background: 'rgba(255,107,0,0.15)', border: '1px solid rgba(255,107,0,0.3)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, color: '#ff6b00', flexShrink: 0 }}>{i + 1}</div>
                  <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.65)', lineHeight: 1.5 }}>{s}</span>
                </div>
              ))}
            </div>
            <a href="https://instagram.com/dollorai" target="_blank" rel="noopener noreferrer" style={{ display: 'inline-block', background: 'linear-gradient(135deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888)', color: '#fff', textDecoration: 'none', borderRadius: 12, padding: '14px 32px', fontSize: 15, fontWeight: 700 }}>
              Follow @dollorai for launch updates
            </a>
          </div>
        </div>
        <PublicFooter />
        <style>{`* { margin:0; padding:0; box-sizing:border-box; } body { background:#0a0a0f; }`}</style>
      </div>
    );
  }

  const steps = ['Personal Info', 'Account', 'Vehicle', 'Review'];

  return (
    <div style={publicPageStyle}>
      <PublicNav ctaLabel="Back to Home" />
      <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
        <div style={{ maxWidth: 580, margin: '0 auto' }}>

          {/* Header */}
          <div style={{ textAlign: 'center', marginBottom: 48 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>💼 DRIVE WITH DOLLOR</div>
            <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>Apply to Drive</h1>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 16, lineHeight: 1.7 }}>Flat $1 platform fee. You keep the rest. No weekly quotas, no commissions.</p>
          </div>

          {/* Step progress */}
          <div style={{ display: 'flex', gap: 8, marginBottom: 40 }}>
            {steps.map((s, i) => (
              <div key={s} style={{ flex: 1, textAlign: 'center' }}>
                <div style={{ height: 3, borderRadius: 99, background: i <= step ? 'linear-gradient(135deg,#ff6b00,#ff9500)' : 'rgba(255,255,255,0.08)', marginBottom: 8, transition: 'background 0.3s' }} />
                <span style={{ fontSize: 11, color: i === step ? '#ff9500' : 'rgba(255,255,255,0.3)', fontWeight: 600, letterSpacing: '0.5px' }}>{s.toUpperCase()}</span>
              </div>
            ))}
          </div>

          {/* Form card */}
          <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 24, padding: '36px' }}>

            {/* Step 0 — Personal */}
            {step === 0 && (
              <>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                  <div style={field}>
                    <label style={label}>FIRST NAME</label>
                    <input style={inp} value={form.first_name} onChange={e => set('first_name', e.target.value)} placeholder="Jane" />
                  </div>
                  <div style={field}>
                    <label style={label}>LAST NAME</label>
                    <input style={inp} value={form.last_name} onChange={e => set('last_name', e.target.value)} placeholder="Smith" />
                  </div>
                </div>
                <div style={field}>
                  <label style={label}>PHONE NUMBER</label>
                  <input style={inp} type="tel" value={form.phone} onChange={e => set('phone', e.target.value)} placeholder="+1 (714) 555-0100" />
                </div>
                <div style={field}>
                  <label style={label}>DATE OF BIRTH</label>
                  <input style={inp} type="date" value={form.date_of_birth} onChange={e => set('date_of_birth', e.target.value)} />
                </div>
                <button style={btn(!!form.first_name && !!form.last_name && !!form.phone)} onClick={() => form.first_name && form.last_name && form.phone && setStep(1)}>
                  Continue →
                </button>
              </>
            )}

            {/* Step 1 — Account */}
            {step === 1 && (
              <>
                <div style={field}>
                  <label style={label}>EMAIL ADDRESS</label>
                  <input style={inp} type="email" value={form.email} onChange={e => set('email', e.target.value)} placeholder="you@email.com" />
                </div>
                <div style={field}>
                  <label style={label}>PASSWORD</label>
                  <input style={inp} type="password" value={form.password} onChange={e => set('password', e.target.value)} placeholder="Min. 8 characters" />
                </div>
                <div style={{ display: 'flex', gap: 12, marginTop: 8 }}>
                  <button style={{ ...btn(false), flex: '0 0 auto', width: 'auto', padding: '16px 24px' }} onClick={() => setStep(0)}>← Back</button>
                  <button style={{ ...btn(!!form.email && form.password.length >= 8), flex: 1 }} onClick={() => form.email && form.password.length >= 8 && setStep(2)}>Continue →</button>
                </div>
              </>
            )}

            {/* Step 2 — Vehicle */}
            {step === 2 && (
              <>
                <div style={field}>
                  <label style={label}>VEHICLE TYPE</label>
                  <select style={{ ...inp, cursor: 'pointer' }} value={form.vehicle_type} onChange={e => set('vehicle_type', e.target.value)}>
                    <option value="car">Car</option>
                    <option value="suv">SUV</option>
                    <option value="truck">Truck</option>
                    <option value="van">Van / Minivan</option>
                  </select>
                </div>
                <div style={field}>
                  <label style={label}>DRIVER'S LICENSE NUMBER</label>
                  <input style={inp} value={form.license_number} onChange={e => set('license_number', e.target.value)} placeholder="CA license number" />
                </div>
                <div style={{ background: 'rgba(255,107,0,0.06)', border: '1px solid rgba(255,107,0,0.15)', borderRadius: 14, padding: '20px', marginBottom: 24 }}>
                  <h4 style={{ fontSize: 14, fontWeight: 700, color: '#ff9500', marginBottom: 12 }}>Requirements</h4>
                  {['Valid CA driver\'s license', 'Insured vehicle', 'At least 21 years old', 'Pass Checkr background check'].map(r => (
                    <div key={r} style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 8, fontSize: 14, color: 'rgba(255,255,255,0.55)' }}>
                      <span style={{ color: '#ff6b00' }}>✓</span> {r}
                    </div>
                  ))}
                </div>
                <div style={{ marginBottom: 20 }}>
                  <label style={{ display: 'flex', alignItems: 'flex-start', gap: 12, cursor: 'pointer' }}>
                    <input type="checkbox" checked={form.agree_terms} onChange={e => set('agree_terms', e.target.checked)} style={{ marginTop: 3, accentColor: '#ff6b00' }} />
                    <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.5)', lineHeight: 1.5 }}>
                      I agree to the <Link to="/terms" target="_blank" style={{ color: '#ff9500' }}>Terms of Service</Link> and <Link to="/privacy" target="_blank" style={{ color: '#ff9500' }}>Privacy Policy</Link>
                    </span>
                  </label>
                </div>
                <div style={{ marginBottom: 28 }}>
                  <label style={{ display: 'flex', alignItems: 'flex-start', gap: 12, cursor: 'pointer' }}>
                    <input type="checkbox" checked={form.agree_verification} onChange={e => set('agree_verification', e.target.checked)} style={{ marginTop: 3, accentColor: '#ff6b00' }} />
                    <span style={{ fontSize: 14, color: 'rgba(255,255,255,0.5)', lineHeight: 1.5 }}>
                      I consent to a background and motor vehicle record check via Checkr
                    </span>
                  </label>
                </div>
                {error && <div style={{ color: '#f87171', fontSize: 14, marginBottom: 16, background: 'rgba(248,113,113,0.08)', border: '1px solid rgba(248,113,113,0.2)', borderRadius: 10, padding: '12px 16px' }}>{error}</div>}
                <div style={{ display: 'flex', gap: 12 }}>
                  <button style={{ ...btn(false), flex: '0 0 auto', width: 'auto', padding: '16px 24px' }} onClick={() => setStep(1)}>← Back</button>
                  <button
                    style={{ ...btn(!loading && form.agree_terms && form.agree_verification && !!form.license_number), flex: 1, opacity: loading ? 0.7 : 1 }}
                    onClick={handleSubmit}
                    disabled={loading || !form.agree_terms || !form.agree_verification || !form.license_number}
                  >
                    {loading ? 'Submitting...' : 'Submit Application →'}
                  </button>
                </div>
              </>
            )}
          </div>

          {/* Benefits below form */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 16, marginTop: 32 }}>
            {[{ icon: '💸', t: 'Flat fee, not a %', d: '$1–$3 by fare tier' }, { icon: '💵', t: '100% of tips', d: 'No fee on tips' }, { icon: '🕒', t: 'Your schedule', d: 'No minimums' }].map(c => (
              <div key={c.t} style={{ background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 16, padding: '20px 16px', textAlign: 'center' }}>
                <div style={{ fontSize: 28, marginBottom: 8 }}>{c.icon}</div>
                <div style={{ fontSize: 14, fontWeight: 700, marginBottom: 4 }}>{c.t}</div>
                <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.35)' }}>{c.d}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
      <PublicFooter />
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap');
        * { margin:0; padding:0; box-sizing:border-box; }
        body { background:#0a0a0f; }
        input::placeholder, textarea::placeholder { color:rgba(255,255,255,0.2); }
        input:focus, select:focus, textarea:focus { border-color:rgba(255,107,0,0.5) !important; }
        select option { background:#1a1a2a; color:#fff; }
      `}</style>
    </div>
  );
};

export default DriverApplication;
