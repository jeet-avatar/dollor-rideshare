import React from 'react';
import LegalLayout, { bulletList, legalSection, linkStyle } from './LegalLayout';

const DriverTerms: React.FC = () => (
  <LegalLayout badge="🚗 DRIVERS" title="Driver Partner Agreement" updated="Last updated: October 29, 2026 · Zietra Technologies Inc. (DBA Dollor.ai)">
    {legalSection('1. Independent Contractor', <>
      <p>You are an independent contractor, not an employee of Dollor.ai or Zietra Technologies Inc. You decide when to go online, which requests to bid on, and whether to bid at all. You may work for other platforms. You are responsible for your own taxes, vehicle expenses, insurance, and any license or permit your work requires. Dollor does not guarantee any minimum earnings, hours, or number of rides, and does not provide benefits.</p>
      <p style={{ marginTop: 12 }}>Dollor operates a peer-to-peer rideshare marketplace in California. Riders post a ride offer and you may bid on it. Dollor provides the technology and processes payments; the ride is provided by you. Dollor's application for a CPUC TNC permit is under CPUC review.</p>
    </>)}

    {legalSection('2. How You Are Paid', <>
      <p>You name your bid. When the rider accepts, the rider's card is authorized, and when the ride is completed the fare is captured. These amounts apply to you:</p>
      {bulletList([
        'Connection fee, flat and based on the fare: $1 if the fare is $35 or less, $2 if over $35 and up to $70, $3 if over $70. The rider is charged a separate connection fee of the same tier.',
        'CPUC Access for All charge: $0.05 to you, and a separate $0.05 to the rider, per completed trip.',
        'Tips: 100% goes to you. No fee is taken from tips.',
        'Payouts are made through Stripe. You must complete Stripe payout onboarding; bank details are entered on Stripe\'s page, not stored by Dollor.',
      ])}
      <p style={{ marginTop: 12 }}>The bid screen shows your estimated earnings after fees before you submit a bid.</p>
    </>)}

    {legalSection('3. Cancellations and No-Shows', <>
      {bulletList([
        'If you cancel after a match, the rider is not charged and the request re-opens for other drivers. Dollor tracks your cancellation rate and warns you when it is high; frequent cancellations may affect your standing.',
        'If the rider cancels before the trip starts, no fee is charged to the rider.',
        'If you arrive at pickup, wait at least 5 minutes, and the rider does not show, you may mark the rider as a no-show. The rider\'s saved card is charged $5.00 and $4.00 (80%) is paid to you, provided you have completed Stripe payout onboarding and the rider\'s card charge succeeds.',
      ])}
    </>)}

    {legalSection('4. Requirements', <>
      {bulletList([
        'Be at least 21 years old (enforced at registration and approval)',
        'Hold a valid driver\'s license and upload a photo of it',
        'Maintain valid vehicle insurance and upload proof of it',
        'Provide your vehicle information and a profile photo',
        'Complete a background check through Checkr and be approved by Dollor',
      ])}
      <p style={{ marginTop: 12 }}><strong style={{ color: '#fff' }}>You cannot go online until your account is approved and your background check has cleared.</strong> The Service blocks going online until both are complete.</p>
    </>)}

    {legalSection('5. Insurance and Licensing', <p>You are responsible for the insurance that California law and the CPUC require of a driver providing rides arranged through an online platform, including personal auto insurance that covers this activity, and for any license or permit your work requires. Dollor does not provide you insurance coverage under this agreement. Confirm with your insurer that your policy covers rideshare activity.</p>)}

    {legalSection('6. Conduct', <>
      <p>You agree to treat riders with respect, arrive promptly, communicate professionally through the app, and protect riders&rsquo; personal information. The following may result in suspension or deactivation:</p>
      {bulletList(['Harassment or discrimination', 'Operating under the influence of drugs or alcohol', 'Unsafe driving', 'Fraud or theft', 'Sharing or misusing rider information'])}
      <p style={{ marginTop: 12 }}>See also our <a href="/zero-tolerance" style={linkStyle}>Zero Tolerance Policy</a>.</p>
    </>)}

    {legalSection('7. Deactivation and Appeals', <>
      <p>Grounds include violation of these terms, a background check that does not clear or fails a re-check, a lapse in your license or insurance, safety concerns, and fraud. To appeal, contact support@dollor.ai within 30 days. We will review your case and respond within 10 business days.</p>
    </>)}

    {legalSection('8. Dispute Resolution', <p>Any disputes arising from this agreement shall be resolved through binding arbitration in accordance with the American Arbitration Association rules. You waive the right to participate in class action lawsuits.</p>)}

    {legalSection('9. Account Deletion', <p>You can delete your driver account in the driver app (Profile &gt; Delete Account) or by emailing support@dollor.ai from your registered address. See <a href="/delete-account" style={linkStyle}>how to delete your account</a>.</p>)}

    {legalSection('10. Changes and Contact', <p>We may update these terms at any time; material changes will be communicated by email or in-app notification. Contact: <a href="mailto:support@dollor.ai" style={linkStyle}>support@dollor.ai</a>, Zietra Technologies Inc. (DBA Dollor.ai), Rancho Santa Margarita, California 92688. See also the <a href="/terms" style={linkStyle}>Terms of Service</a> and <a href="/privacy" style={linkStyle}>Privacy Policy</a>.</p>)}
  </LegalLayout>
);

export default DriverTerms;
