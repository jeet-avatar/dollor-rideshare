import React from 'react';
import PublicNav, { PublicFooter, publicPageStyle } from '../../components/layout/PublicNav';

const s = (title: string, children: React.ReactNode) => (
  <div style={{ marginBottom: 40 }}>
    <h2 style={{ fontSize: 20, fontWeight: 800, marginBottom: 14, color: '#fff' }}>{title}</h2>
    <div style={{ color: 'rgba(255,255,255,0.6)', fontSize: 15, lineHeight: 1.8 }}>{children}</div>
  </div>
);

const ZeroTolerancePolicy: React.FC = () => (
  <div style={publicPageStyle}>
    <PublicNav />
    <div style={{ minHeight: '100vh', padding: '120px 24px 80px' }}>
      <div style={{ maxWidth: 720, margin: '0 auto' }}>

        <div style={{ textAlign: 'center', marginBottom: 56 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(255,107,0,0.1)', border: '1px solid rgba(255,107,0,0.25)', color: '#ff9500', borderRadius: 50, padding: '7px 18px', fontSize: 12, fontWeight: 700, letterSpacing: '1.5px', marginBottom: 20 }}>🛡️ SAFETY</div>
          <h1 style={{ fontSize: 'clamp(28px,5vw,44px)', fontWeight: 900, letterSpacing: '-1.5px', marginBottom: 14 }}>Zero Tolerance Policy</h1>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: 14 }}>Last updated: October 29, 2026 · Zietra Technologies Inc. (DBA Dollor.ai)</p>
        </div>

        <div style={{ background: 'rgba(255,107,0,0.06)', border: '1px solid rgba(255,107,0,0.2)', borderRadius: 20, padding: '28px 32px', marginBottom: 32 }}>
          <p style={{ fontSize: 16, fontWeight: 600, color: '#fff', lineHeight: 1.7 }}>Dollor is committed to the safety of every person on our platform. We maintain a strict zero tolerance policy for the behaviors listed below. Violations result in <strong style={{ color: '#ff9500' }}>immediate and permanent deactivation</strong> — no warnings, no second chances.</p>
        </div>

        <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 20, padding: '40px' }}>

          {s('1. Drugs and Alcohol', <>
            <p>Dollor prohibits the use, possession, or influence of alcohol, marijuana, or any controlled substance by drivers while using the Dollor platform (while online or during a ride).</p>
            <p style={{ marginTop: 12 }}>Riders who request a driver to transport them under the influence in a way that endangers others may also be permanently deactivated.</p>
            <p style={{ marginTop: 12 }}>If you believe your driver is impaired: <strong>call 911 if you are in danger and exit the vehicle when safe to do so.</strong></p>
          </>)}

          {s('2. Discrimination', <>
            <p>Dollor prohibits discrimination based on:</p>
            <ul style={{ paddingLeft: 20, marginTop: 10 }}>
              {['Race, color, national origin, or ethnicity', 'Religion or creed', 'Sex, gender identity, or sexual orientation', 'Age or disability status', 'Source of income or public assistance status'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
            <p style={{ marginTop: 12 }}>Drivers may not refuse ride requests, apply different terms, or provide inferior service based on any of the above. Riders may not request discrimination against drivers or third parties.</p>
          </>)}

          {s('3. Sexual Misconduct and Harassment', <>
            <p>Dollor has zero tolerance for any form of sexual misconduct, harassment, or inappropriate physical contact. This includes:</p>
            <ul style={{ paddingLeft: 20, marginTop: 10 }}>
              {['Unsolicited touching or physical contact', 'Verbal harassment or sexual comments', 'Requesting personal contact information for personal purposes', 'Non-consensual recording or photography', 'Any sexual conduct of any kind'].map(i => <li key={i} style={{ marginBottom: 8 }}>{i}</li>)}
            </ul>
          </>)}

          {s('4. Violence and Threatening Behavior', <>
            <p>Physical violence, threats of violence, or intimidation of any kind — toward any person, including drivers, riders, or bystanders — is grounds for immediate permanent deactivation and referral to law enforcement.</p>
          </>)}

          {s('5. Fraud and Deception', <>
            <p>Deceptive practices including creating fake accounts, manipulating ratings, submitting false reports, or circumventing the platform's fee system are prohibited and may result in legal action in addition to deactivation.</p>
          </>)}

          {s('6. How to Report a Violation', <>
            <p>If you experience or witness a zero tolerance violation:</p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 16 }}>
              {[
                { icon: '🚨', t: 'Immediate danger', d: 'Call 911. The iOS rider app has an emergency button that calls 911 from your phone.' },
                { icon: '✉️', t: 'Report after the fact', d: 'Email support@dollor.ai with your ride details and description.' },
                { icon: '⭐', t: 'In-app reporting', d: 'After your ride, rate your experience and, if needed, contact support.' },
              ].map(c => (
                <div key={c.t} style={{ display: 'flex', gap: 16, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 12, padding: '16px 20px' }}>
                  <span style={{ fontSize: 24, flexShrink: 0 }}>{c.icon}</span>
                  <div>
                    <div style={{ fontWeight: 700, color: '#fff', marginBottom: 4 }}>{c.t}</div>
                    <div style={{ fontSize: 14, color: 'rgba(255,255,255,0.5)' }}>{c.d}</div>
                  </div>
                </div>
              ))}
            </div>
          </>)}

          {s('7. Investigation Process', <>
            <p>Reported violations are reviewed by our team. Accounts under investigation may be temporarily suspended. Drivers found to have violated this policy are permanently deactivated and may be reported to the CPUC and law enforcement as required by California Public Utilities Code § 5440.5.</p>
          </>)}

          {s('8. CPUC Compliance', <>
            <p>This policy is maintained in compliance with California Public Utilities Code requirements for Transportation Network Companies. Under California law (PUC § 5440.5), Dollor is required to immediately deactivate drivers upon receiving a credible complaint of impairment or certain violations.</p>
            <p style={{ marginTop: 12 }}>To report a TNC violation to the CPUC directly, visit the CPUC Consumer Affairs website or call 1-800-649-7570.</p>
          </>)}

          {s('Contact', <p>Safety concerns and general support: <a href="mailto:support@dollor.ai" style={{ color: '#ff9500' }}>support@dollor.ai</a></p>)}
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

export default ZeroTolerancePolicy;
