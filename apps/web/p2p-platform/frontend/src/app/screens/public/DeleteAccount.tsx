import React from 'react';
import LegalLayout, { bulletList, legalSection, linkStyle } from './LegalLayout';

const DeleteAccount: React.FC = () => (
  <LegalLayout badge="🗑️ ACCOUNT" title="Delete Your Account and Data" updated="Applies to the Dollor rider and driver apps · Zietra Technologies Inc. (DBA Dollor.ai) · Last updated: October 29, 2026">
    {legalSection('Option 1: Delete in the app', <>
      <p><strong style={{ color: '#fff' }}>Rider app</strong></p>
      <ol style={{ paddingLeft: 20, margin: '8px 0 16px' }}>
        <li>Open the Dollor rider app and sign in.</li>
        <li>Go to <strong>Profile</strong> and tap <strong>Delete Account</strong> (also available under <strong>Settings &gt; Delete Account</strong>).</li>
        <li>Confirm. Your account is deleted and you are signed out.</li>
      </ol>
      <p><strong style={{ color: '#fff' }}>Driver app</strong></p>
      <ol style={{ paddingLeft: 20, marginTop: 8 }}>
        <li>Open the Dollor driver app and sign in.</li>
        <li>Go to <strong>Profile</strong> and tap <strong>Delete Account</strong>.</li>
        <li>Confirm. Your account is deleted and you are signed out.</li>
      </ol>
    </>)}

    {legalSection('Option 2: Request deletion by email', <p>If you cannot sign in or no longer have the app, email <a href="mailto:support@dollor.ai?subject=Account%20deletion%20request" style={linkStyle}>support@dollor.ai</a> with the subject "Account deletion request", from the email address registered on your account. Say whether it is a rider or driver account. We may reply to confirm it is you. We complete deletion requests within 30 days.</p>)}

    {legalSection('What is deleted and what is kept', <>
      {bulletList([
        'Removed or anonymised: your name becomes "Deleted User", and your email, phone number, addresses, photos, saved payment method references, and for drivers the vehicle and document details are removed. You can no longer sign in.',
        'Kept in anonymised form (your name and phone number removed): records of completed rides, payments and payouts, where needed for tax, accounting, fraud-prevention and California Public Utilities Commission (CPUC) regulatory purposes. Our Privacy Policy states a retention period of 7 years for these records.',
        'Held by others: card and bank details are held by Stripe, and the driver background check is run by Checkr. Each handles that data under its own privacy policy.',
        'Messages you sent to another user as part of a ride may remain visible to that person.',
      ])}
      <p style={{ marginTop: 12 }}>Deleting an account cannot be undone. You cannot delete your account while you have a ride in progress or an unpaid payout: finish or cancel it first. For an unresolved payment issue, contact support.</p>
    </>)}

    {legalSection('Questions', <p>Support: <a href="mailto:support@dollor.ai" style={linkStyle}>support@dollor.ai</a>. Privacy requests: <a href="mailto:privacy@dollor.ai" style={linkStyle}>privacy@dollor.ai</a>. See our <a href="/privacy" style={linkStyle}>Privacy Policy</a>.</p>)}
  </LegalLayout>
);

export default DeleteAccount;
