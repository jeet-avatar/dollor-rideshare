import React, { useState, useEffect } from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const ReferAndEarn: React.FC = () => {
  const [referralCode, setReferralCode] = useState('');
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const userId = localStorage.getItem('user_id') || Math.random().toString(36).substring(7).toUpperCase();
    setReferralCode('DOLLOR-' + userId.toUpperCase().slice(0, 6));
  }, []);

  const copyCode = () => {
    navigator.clipboard.writeText(referralCode).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const share = (method: 'copy' | 'twitter' | 'sms') => {
    const msg = `I'm joining Dollor — a bid-based rideshare app with a flat connection fee instead of a percentage commission. My referral code: ${referralCode}. dollor.ai`;
    if (method === 'copy') { navigator.clipboard.writeText(msg).catch(() => {}); setCopied(true); setTimeout(() => setCopied(false), 2000); }
    if (method === 'twitter') window.open(`https://twitter.com/intent/tweet?text=${encodeURIComponent(msg)}`, '_blank');
    if (method === 'sms') window.open(`sms:?body=${encodeURIComponent(msg)}`, '_blank');
  };

  const inp: React.CSSProperties = {
    flex: 1, background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 12, padding: '14px 20px', color: '#fff', fontSize: 18, fontWeight: 700,
    fontFamily: 'monospace', letterSpacing: '2px', outline: 'none',
  };

  return (
    <div style={publicPageStyle}>
      <PublicNav />
      <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
        <div style={{ maxWidth: 680, margin: '0 auto' }}>

          {/* Header */}
          <div style={{ textAlign: 'center', marginBottom: 56 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>🎁 REFER & EARN</div>
            <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>Share Dollor.<br />Earn ride credits.</h1>
            <p style={{ color: 'rgba(255,255,255,0.5)', fontSize: 16, lineHeight: 1.7 }}>For every friend who takes their first ride, you both get a credit. The more you share, the more you save.</p>
          </div>

          {/* Code card */}
          <div style={{ background: 'rgba(255,107,0,0.08)', border: '1px solid rgba(255,107,0,0.2)', borderRadius: 24, padding: '36px', marginBottom: 32, textAlign: 'center' }}>
            <p style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.4)', letterSpacing: '2px', marginBottom: 16 }}>YOUR REFERRAL CODE</p>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <input readOnly style={inp} value={referralCode} />
              <button onClick={copyCode} style={{ padding: '14px 22px', background: copied ? 'rgba(34,197,94,0.15)' : 'linear-gradient(135deg,#ff6b00,#ff9500)', border: copied ? '1px solid rgba(34,197,94,0.4)' : 'none', borderRadius: 12, color: copied ? '#22c55e' : '#fff', fontWeight: 700, fontSize: 14, cursor: 'pointer', whiteSpace: 'nowrap', transition: 'all 0.2s' }}>
                {copied ? '✓ Copied!' : 'Copy'}
              </button>
            </div>
          </div>

          {/* Share buttons */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 12, marginBottom: 48 }}>
            {[
              { icon: '🔗', label: 'Copy Link', action: () => share('copy') },
              { icon: '🐦', label: 'Tweet', action: () => share('twitter') },
              { icon: '💬', label: 'Text a Friend', action: () => share('sms') },
            ].map(b => (
              <button key={b.label} onClick={b.action} style={{ padding: '16px', background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 14, color: '#fff', fontSize: 14, fontWeight: 600, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 24 }}>{b.icon}</span>{b.label}
              </button>
            ))}
          </div>

          {/* How it works */}
          <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 20, padding: '36px', marginBottom: 32 }}>
            <h2 style={{ fontSize: 20, fontWeight: 800, marginBottom: 28, textAlign: 'center' }}>How it works</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
              {[
                { n: '1', t: 'Share your code', d: 'Send your referral code to friends and family who need reliable, affordable rides in California.' },
                { n: '2', t: 'They sign up & ride', d: 'Your friend creates an account, enters your code, and takes their first Dollor ride.' },
                { n: '3', t: 'You both earn credits', d: 'After their first completed ride, you each receive a ride credit applied to your next trip.' },
              ].map(step => (
                <div key={step.n} style={{ display: 'flex', gap: 20, alignItems: 'flex-start' }}>
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'linear-gradient(135deg,#ff6b00,#ff9500)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, fontWeight: 900, flexShrink: 0 }}>{step.n}</div>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 16, marginBottom: 6 }}>{step.t}</div>
                    <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: 14, lineHeight: 1.6 }}>{step.d}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Terms note */}
          <p style={{ color: 'rgba(255,255,255,0.25)', fontSize: 13, textAlign: 'center', lineHeight: 1.7 }}>
            Referral credits are issued after your friend completes their first ride using your code. Credits are non-transferable, expire 90 days after issue, and have no cash value. Dollor reserves the right to modify or cancel the referral program at any time.
          </p>
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
};

export default ReferAndEarn;
