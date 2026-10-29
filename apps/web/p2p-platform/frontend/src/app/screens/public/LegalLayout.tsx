import React from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

export const linkStyle: React.CSSProperties = { color: '#ff9500' };

export function legalSection(title: string, children: React.ReactNode): React.ReactElement {
  return (
    <div style={{ marginBottom: 40 }} key={title}>
      <h2 style={{ fontSize: 20, fontWeight: 800, marginBottom: 14, color: '#fff' }}>{title}</h2>
      <div style={{ color: 'rgba(255,255,255,0.6)', fontSize: 15, lineHeight: 1.8 }}>{children}</div>
    </div>
  );
}

export function bulletList(items: string[]): React.ReactElement {
  return (
    <ul style={{ paddingLeft: 20, marginTop: 10 }}>
      {items.map(item => <li key={item} style={{ marginBottom: 8 }}>{item}</li>)}
    </ul>
  );
}

interface LegalLayoutProps {
  badge: string;
  title: string;
  updated: string;
  children: React.ReactNode;
}

const LegalLayout: React.FC<LegalLayoutProps> = ({ badge, title, updated, children }) => (
  <div style={publicPageStyle}>
    <PublicNav />
    <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>
        <div style={{ textAlign: 'center', marginBottom: 56 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>{badge}</div>
          <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>{title}</h1>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: 14 }}>{updated}</p>
        </div>
        <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 20, padding: '40px' }}>
          {children}
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

export default LegalLayout;
