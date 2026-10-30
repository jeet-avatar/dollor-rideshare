import React from 'react';
import LegalLayout, { bulletList, legalSection, linkStyle } from './LegalLayout';

const TermsOfService: React.FC = () => (
  <LegalLayout badge="📄 LEGAL" title="Terms of Service" updated="Last updated: October 29, 2026 · Zietra Technologies Inc. (DBA Dollor.ai)">
    {legalSection('1. Acceptance of Terms', <p>By downloading, accessing, or using the Dollor applications or website (the "Service") operated by Zietra Technologies Inc., doing business as Dollor.ai ("Dollor", "we", or "us"), you agree to be bound by these Terms of Service and our <a href="/privacy" style={linkStyle}>Privacy Policy</a>. Drivers also agree to the <a href="/driver-terms" style={linkStyle}>Driver Terms</a>. If you do not agree, do not use the Service.</p>)}

    {legalSection('2. What Dollor Is', <>
      <p>Dollor is a peer-to-peer rideshare marketplace for California. Riders post a ride offer and independent drivers bid on it. Dollor provides the technology that connects them and processes payment. Dollor does not own vehicles, does not employ drivers, and does not provide transportation itself. Drivers are independent contractors.</p>
      <p style={{ marginTop: 12 }}>Dollor operates under a California Public Utilities Commission (CPUC) Transportation Network Company permit, number TNC0050982-N, issued in October 2026.</p>
    </>)}

    {legalSection('3. How a Ride Works', <>
      {bulletList([
        'The rider enters a pickup and destination and posts a ride request with an offer. A fare estimate and fee breakdown are shown first.',
        'The request is open for bids for 5 minutes. Drivers who are online and nearby may bid.',
        'The rider may accept a bid, counter-offer, or decline. A request that is not accepted in the bidding window expires.',
        'When a bid is accepted, the rider\'s card is authorized through Stripe for the agreed fare. It is not charged at that point.',
        'When the trip is completed, the authorized amount is captured. The rider may add an optional tip after the trip.',
      ])}
      <p style={{ marginTop: 12 }}>If the card cannot be authorized at the match, the ride is cancelled. Suggested fares include a time-of-day adjustment (higher at morning and evening peak hours, lower in the early afternoon), which is shown in the estimate before you post a request.</p>
    </>)}

    {legalSection('4. Eligibility', <>
      <p>Riders must be at least 18, provide accurate account information, and keep a valid payment card on file. Drivers must also:</p>
      {bulletList([
        'Be at least 21 years old (enforced at registration and approval)',
        'Hold a valid driver\'s license, and provide proof of vehicle insurance, vehicle details, and a profile photo',
        'Complete a background check through Checkr and be approved by Dollor',
      ])}
      <p style={{ marginTop: 12 }}>The Service does not let a driver go online until the driver is approved and the background check has cleared. Drivers are responsible for their own license, registration, insurance, and any permit California law or the CPUC requires of them. See the <a href="/driver-terms" style={linkStyle}>Driver Terms</a>.</p>
    </>)}

    {legalSection('5. Fees and Payments', <>
      {bulletList([
        'Fare: the bid price the rider accepts, paid to the driver.',
        'Connection fee: a flat fee based on the fare, charged to the rider and, separately, to the driver: $1 if the fare is $35 or less, $2 if over $35 and up to $70, $3 if over $70.',
        'CPUC Access for All charge: $0.05 charged to the rider and $0.05 charged to the driver per completed trip.',
        'Tips: optional; 100% goes to the driver.',
      ])}
      <p style={{ marginTop: 12 }}>Payments are processed by Stripe. Dollor does not store full card numbers. Drivers are paid out through Stripe.</p>
    </>)}

    {legalSection('6. Cancellations and Refunds', <>
      {bulletList([
        'A rider can cancel before the trip starts at no charge. The card authorization is released.',
        'A rider cannot cancel once the trip is in progress.',
        'If a driver cancels after a match, the rider is not charged and the request re-opens for other drivers.',
        'No-show: if the driver has arrived at pickup and waited at least 5 minutes, the driver may mark the rider as a no-show. The ride is cancelled and the rider\'s saved card is charged a $5.00 no-show fee, of which 80% ($4.00) is paid to the driver.',
      ])}
      <p style={{ marginTop: 12 }}>For refund or charge questions, email <a href="mailto:support@dollor.ai" style={linkStyle}>support@dollor.ai</a> with your trip details. Chargebacks started outside this process may result in account suspension.</p>
    </>)}

    {legalSection('7. User Conduct', <>
      <p>You agree not to:</p>
      {bulletList(['Use the Service for any unlawful purpose', 'Harass, threaten, or discriminate against any user', 'Provide false information during registration', 'Attempt to defraud the payment system', 'Use the Service while impaired by alcohol or drugs'])}
      <p style={{ marginTop: 12 }}>Violations may result in suspension or termination of your account. See our <a href="/zero-tolerance" style={linkStyle}>Zero Tolerance Policy</a>.</p>
    </>)}

    {legalSection('8. Safety', <>
      <p>Drivers must be approved with a cleared Checkr background check before going online. Riders and drivers rate each other after a trip and can message in the app. The iOS rider app includes Share trip and an emergency button that calls 911 from your phone. In an emergency call 911 directly; Dollor is not an emergency service. A background check does not guarantee safety, and Dollor does not guarantee the conduct of any driver or rider. Report concerns to <a href="mailto:support@dollor.ai" style={linkStyle}>support@dollor.ai</a>.</p>
    </>)}

    {legalSection('9. Account Deletion', <p>You can delete your account in the app (Profile &gt; Delete Account) or by emailing support@dollor.ai from your registered address. See <a href="/delete-account" style={linkStyle}>how to delete your account</a>.</p>)}

    {legalSection('10. Limitation of Liability', <>
      <p>To the maximum extent permitted by law, Dollor's liability for any claim arising out of or relating to these Terms or the Service shall not exceed the greater of: (a) the amount you paid to Dollor in the 12 months preceding the claim; or (b) $100.</p>
      <p style={{ marginTop: 12 }}>Dollor is not liable for: driver conduct, accidents caused by drivers, lost or damaged property, or any indirect, incidental, or consequential damages.</p>
    </>)}

    {legalSection('11. Dispute Resolution', <p>Any disputes arising from these Terms shall be resolved through binding arbitration in California under the rules of the American Arbitration Association (AAA). You waive the right to a jury trial and class action participation. Small claims court actions under $10,000 are exempt from this arbitration clause.</p>)}

    {legalSection('12. Governing Law', <p>These Terms are governed by the laws of the State of California, without regard to conflict of law provisions. Any action not subject to arbitration shall be brought in the courts of Riverside County, California.</p>)}

    {legalSection('13. Changes to Terms', <p>We may modify these Terms at any time. Material changes will be communicated via email or in-app notification. Continued use of the Service after changes constitutes acceptance.</p>)}

    {legalSection('14. Contact', <p>Questions about these Terms? Email <a href="mailto:support@dollor.ai" style={linkStyle}>support@dollor.ai</a> or write to Zietra Technologies Inc., Rancho Santa Margarita, California 92688.</p>)}
  </LegalLayout>
);

export default TermsOfService;
