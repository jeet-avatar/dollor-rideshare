import React from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const s = (title: string, children: React.ReactNode) => (
  <div style={{ marginBottom: 40 }}>
    <h2 style={{ fontSize: 20, fontWeight: 800, marginBottom: 14, color: '#fff' }}>{title}</h2>
    <div style={{ color: 'rgba(255,255,255,0.6)', fontSize: 15, lineHeight: 1.8 }}>{children}</div>
  </div>
);

const RefundPolicy: React.FC = () => (
  <div style={publicPageStyle}>
    <PublicNav />
    <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>

        <div style={{ textAlign: 'center', marginBottom: 56 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>💳 LEGAL</div>
          <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>Refund Policy</h1>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: 14 }}>Last updated: October 29, 2026 · Zietra Technologies Inc. (DBA Dollor.ai)</p>
        </div>

        <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 20, padding: '40px' }}>

          {s('Overview', <p>Dollor connects riders with independent drivers and charges a flat connection fee. Your card is authorized when you accept a bid and charged when the ride is completed.</p>)}

          {s('Cancellations and No-Shows', <>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginBottom: 16 }}>
              {[
                { stage: 'Rider cancels before the trip starts', fee: 'No charge', desc: 'The card authorization is released. Open bids on the request are closed.' },
                { stage: 'Driver cancels after a match', fee: 'No charge', desc: 'The authorization is released and the request re-opens for other drivers.' },
                { stage: 'Rider no-show', fee: '$5.00', desc: 'If the driver has arrived and waited at least 5 minutes, the driver may mark a no-show; your saved card is charged $5.00 (80% goes to the driver).' },
                { stage: 'Completed ride', fee: 'Case by case', desc: 'Contact support to dispute a charge on a completed ride (see below).' },
              ].map(r => (
                <div key={r.stage} style={{ display: 'grid', gridTemplateColumns: '1fr auto', gap: 12, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 12, padding: '16px 20px', alignItems: 'start' }}>
                  <div>
                    <div style={{ fontWeight: 700, color: '#fff', marginBottom: 4, fontSize: 14 }}>{r.stage}</div>
                    <div style={{ fontSize: 13, color: 'rgba(255,255,255,0.45)' }}>{r.desc}</div>
                  </div>
                  <div style={{ fontSize: 14, fontWeight: 800, color: '#ff9500', whiteSpace: 'nowrap' }}>{r.fee}</div>
                </div>
              ))}
            </div>
          </>)}

          {s('Dispute Resolution for Completed Rides', <>
            <p>Refunds on completed rides may be issued in the following circumstances:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {['Driver took a significantly longer route than necessary without explanation', 'Ride was charged but never completed (ghost trip)', 'You were charged for a ride you did not request', 'Safety incident during the trip substantiated by our Trust & Safety team', 'Technical error in charge amount'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
            <p style={{ marginTop: 12 }}>Please report disputes as soon as possible after the ride by emailing <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a>.</p>
          </>)}

          {s('Refund Processing', <>
            <p>Approved refunds are returned to the original payment method:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {['Refunds are returned to the original card through Stripe. Timing depends on your card issuer.'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
            <p style={{ marginTop: 12 }}>Refunds are processed through Stripe. Whether the connection fee is refunded is decided case by case.</p>
          </>)}

          {s('Chargebacks', <p>Initiating a chargeback with your bank before contacting Dollor support may result in account suspension. We encourage you to contact us first — most issues are resolved quickly and a chargeback is rarely necessary.</p>)}

          {s('Non-Refundable Items', <>
            <p>The following are not eligible for refunds:</p>
            <ul style={{ paddingLeft: 20, marginTop: 12 }}>
              {['Completed rides where service was rendered as described', 'Tips paid to drivers', 'Cancellation fees (these compensate the driver)', 'Connection fees, except where we decide otherwise case by case'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
          </>)}

          {s('Contact', <p>To dispute a charge or request a refund, email <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a> with your trip ID, date, and a description of the issue.</p>)}
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

export default RefundPolicy;
