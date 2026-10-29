import React, { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';

const PublicNav: React.FC<{ ctaLabel?: string; ctaTo?: string }> = ({
  ctaLabel = 'Join Waitlist',
  ctaTo = '/#waitlist',
}) => {
  const [scrolled, setScrolled] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <nav style={{
      position: 'fixed', top: 0, left: 0, right: 0, zIndex: 100,
      background: scrolled ? 'rgba(10,10,15,0.97)' : 'rgba(10,10,15,0.85)',
      backdropFilter: 'blur(20px)',
      borderBottom: '1px solid rgba(255,255,255,0.06)',
      padding: '16px 0',
    }}>
      <div style={{ maxWidth: 1100, margin: '0 auto', padding: '0 24px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: 10, textDecoration: 'none' }}>
          <div style={{ width: 34, height: 34, background: 'linear-gradient(135deg,#ff6b00,#ff9500)', borderRadius: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 17, fontWeight: 900, color: '#fff' }}>D</div>
          <span style={{ fontSize: 19, fontWeight: 800, color: '#fff', letterSpacing: '-0.5px' }}>dollor<span style={{ color: '#ff6b00' }}>.ai</span></span>
        </Link>
        <div style={{ display: 'flex', gap: 28, alignItems: 'center' }}>
          <Link to="/driver/apply" style={{ color: 'rgba(255,255,255,0.6)', textDecoration: 'none', fontSize: 14, fontWeight: 500, display: 'none' }} className="nav-link-hide-mobile">Drive with Us</Link>
          <Link to="/help" style={{ color: 'rgba(255,255,255,0.6)', textDecoration: 'none', fontSize: 14, fontWeight: 500 }}>Help</Link>
          <button
            onClick={() => navigate('/')}
            style={{ background: 'linear-gradient(135deg,#ff6b00,#ff9500)', color: '#fff', border: 'none', borderRadius: 10, padding: '10px 20px', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}
          >
            {ctaLabel}
          </button>
        </div>
      </div>
    </nav>
  );
};

export const PublicFooter: React.FC = () => (
  <footer style={{ borderTop: '1px solid rgba(255,255,255,0.06)', padding: '48px 24px 32px', background: '#0a0a0f' }}>
    <div style={{ maxWidth: 1100, margin: '0 auto', display: 'flex', flexWrap: 'wrap', gap: 40, justifyContent: 'space-between' }}>
      <div>
        <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: 10, textDecoration: 'none', marginBottom: 12 }}>
          <div style={{ width: 30, height: 30, background: 'linear-gradient(135deg,#ff6b00,#ff9500)', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 900, color: '#fff', fontSize: 15 }}>D</div>
          <span style={{ fontSize: 17, fontWeight: 800, color: '#fff' }}>dollor<span style={{ color: '#ff6b00' }}>.ai</span></span>
        </Link>
        <p style={{ color: 'rgba(255,255,255,0.3)', fontSize: 13, maxWidth: 260, lineHeight: 1.7 }}>Peer-to-peer rideshare marketplace<br />Zietra Technologies Inc., Rancho Santa Margarita, CA</p>
      </div>
      <div style={{ display: 'flex', gap: 48, flexWrap: 'wrap' }}>
        <div>
          <h4 style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.35)', letterSpacing: '1.5px', marginBottom: 14 }}>LEGAL</h4>
          {[
            { label: 'Privacy Policy', to: '/privacy' },
            { label: 'Terms of Service', to: '/terms' },
            { label: 'Driver Terms', to: '/driver-terms' },
            { label: 'Delete Account', to: '/delete-account' },
            { label: 'Zero Tolerance', to: '/zero-tolerance' },
            { label: 'Refund Policy', to: '/refund' },
          ].map(l => (
            <div key={l.label} style={{ marginBottom: 10 }}>
              <Link to={l.to} style={{ color: 'rgba(255,255,255,0.45)', textDecoration: 'none', fontSize: 14 }}>{l.label}</Link>
            </div>
          ))}
        </div>
        <div>
          <h4 style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.35)', letterSpacing: '1.5px', marginBottom: 14 }}>CONTACT</h4>
          {[
            { label: 'Support', href: '/support' },
            { label: 'support@dollor.ai', href: 'mailto:support@dollor.ai' },
            { label: '@dollorai on Instagram', href: 'https://instagram.com/dollorai' },
          ].map(l => (
            <div key={l.label} style={{ marginBottom: 10 }}>
              <a href={l.href} target={l.href.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer" style={{ color: 'rgba(255,255,255,0.45)', textDecoration: 'none', fontSize: 14 }}>{l.label}</a>
            </div>
          ))}
        </div>
      </div>
    </div>
    <div style={{ maxWidth: 1100, margin: '28px auto 0', paddingTop: 20, borderTop: '1px solid rgba(255,255,255,0.05)', display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
      <p style={{ color: 'rgba(255,255,255,0.2)', fontSize: 13 }}>© 2026 Zietra Technologies Inc. All rights reserved.</p>
      <p style={{ color: 'rgba(255,255,255,0.15)', fontSize: 12 }}>Dollor.ai is a technology marketplace; rides are provided by independent drivers</p>
    </div>
  </footer>
);

export const publicPageStyle: React.CSSProperties = {
  fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, sans-serif",
  background: '#0a0a0f',
  color: '#fff',
  minHeight: '100vh',
};

export default PublicNav;
