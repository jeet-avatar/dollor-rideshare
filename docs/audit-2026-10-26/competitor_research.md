> Generated 2026-10-26 by automated audit passes. Line numbers refer to the code at that time; several findings listed here were fixed afterwards (see docs/LAUNCH_READINESS_REPORT.md section 10). Verify before relying on a specific line.

# Competitor + CA regulatory research (public sources only, 2026-10-26)

Method: web search summaries of public pages; only a few official pages were opened fully. Items without an official source are marked UNVERIFIED. Status column = our status from the task context (have / partly / missing).

## 1. Rider-side comparison

| Area | What Uber/Lyft/inDrive publicly document | Source | Us |
|---|---|---|---|
| PIN verification | Uber "Verify Your Ride": 4-digit PIN in rider app, rider tells driver, driver enters it to start trip; rider can choose every trip or night only (9pm-6am). Lyft equivalent: UNVERIFIED (not found). | https://www.iphoneincanada.ca/2020/01/07/uber-pin-code-canada ; https://www.wafb.com/2020/01/07/uber-now-offering-pin-code-safety-feature-all-riders | missing |
| Off-route / long-stop / crash check-in | Uber RideCheck: GPS + phone sensors flag possible crash, unusual off-course, long stops; both rider and driver get "are you OK" prompt, can escalate to emergency button / safety line. Lyft "Smart Trip Check-In" contacts you if something unusual detected. | https://www.uber.com/us/en/newsroom/ridecheck/ ; https://www.lyft.com/rider/safety | missing |
| Audio recording | Lyft: record every ride / night only / on demand, encrypted, kept 7 days, accessible only to Safety team if attached to a report. Uber: opt-in recording from Safety Toolkit (details from third-party press, current US availability unverified). | https://www.lyft.com/safety/audiorecording ; https://africa.com/headlines/uber-raises-the-bar-on-safety-with-new-audio-recording-feature | missing |
| Emergency button | Uber in-app 911 button showing live location/vehicle/plate, auto-passed to dispatcher in a growing number of US cities. Lyft: 911 in app, 24/7 safety team, ADT professionals. | https://uber.com/us/en/ride/safety ; https://www.lyft.com/rider/safety | have (SOS) |
| Share trip / trusted contacts | Uber Trusted Contacts + share trip reminders; Lyft trusted contacts live tracking. | https://uber.com/us/en/ride/safety ; https://www.lyft.com/rider/safety | have trip share; trusted contacts partly/unknown |
| Rider verification (protects drivers) | Lyft rider verification badge (legal name, ID upload if checks fail); drivers may decline unverified riders. | https://www.lyft.com/safety/rider-verification ; https://techcrunch.com/2024/08/27/lyft-rider-verification-program | missing (rider KYC not in context) |
| Upfront price | Uber upfront fares show rider price and driver payout before accept (driver destination visibility varies by market). | https://www.ridesharingdriver.com/uber-driver-upfront-fares/ (third party) | have (negotiated price shown) |
| Price negotiation | inDrive: rider names fare, drivers accept/decline/counter, rider compares offers (fare, rating, car, ETA), can counter; no surge; local band limits around recommended fare. Uber India "Go Flex"/"Uber Flex" tests: rider picks/proposes fare, nearby drivers approve or decline. Uber CA 2020 airport test was DRIVER-set fares (up to 5x in 10% steps), not a rider offer. No Uber/Lyft US rider-offer product found. | https://www.topgear.com.ph/features/feature-articles/indrive-philippines-explainer-a4682-20231214-lfrm ; https://ts.yourstory.com/2023/10/uber-testing-a-new-flexible-pricing-feature ; https://www.intelligenttransport.com/?p=95020 | have (differentiator) |
| ETA and live tracking | Standard on both (not individually sourced here; UNVERIFIED specifics). | n/a | partly/unknown |
| Accessibility | Uber WAV option where offered; drivers must serve riders with service animals; wait-time fee may be waived for riders with disabilities (driver still paid). Lyft Access Mode for WAV in some markets; no official Lyft service-animal page found. | https://www.uber.com/ch/en/ride/uberwav/ ; https://help.uber.com/h/7f41997f-a853-46ae-8001-8ab9dee504b0 ; https://getridewise.com/blog/uber-lyft-accessibility-features-guide | partly (request exists; fee waiver and service-animal rule unknown) |
| Cancellation / no-show / wait time | Uber: wait-time grace starts at arrival or original ETA (whichever later), then wait fee accrues; disability exemption. No-show fee when driver waits at least 5 min then cancels (developer doc). Fees vary by product/region. Lyft: fees vary, $5-type figures only from third parties (UNVERIFIED). | https://help.uber.com/h/7f41997f-a853-46ae-8001-8ab9dee504b0 ; https://developer.uber.com/docs/guest-rides/guest-ride-api-build-guide/dispatch-and-cancellation | partly/unknown |
| Scheduled rides | Lyft reportedly up to 30 days ahead, late-cancel fee about $10 after match (third-party sources conflict; UNVERIFIED). Uber Reserve exists (excluded from no-show change in HK notice). | https://www.ridesharingdriver.com/lyft-schedule-ride/ ; https://www.uber.com/en-HK/blog/cancellation-fee-and-wait-time-fee | partly (UI untested) |
| Tipping, ratings, receipts | Standard on both; not individually sourced (UNVERIFIED specifics). | n/a | have |
| Dispatch policy / radius | Public docs not found. Third-party design write-ups: rank by ETA, short-timer offers (e.g. 10s) then cascade. Treat as illustrative only. | https://www.techinterview.org/post/3233461063/system-design-rideshare-dispatch/ | ours: 10 nearest, 5-min window (have); "drivers contacted" count missing |
| Notifications | Not sourced. UNVERIFIED. | n/a | partly/unknown |

## 2. Driver-side

| Area | Public finding | Source | Us |
|---|---|---|---|
| Offer acceptance / timers | Third-party: short accept timers then cascade (illustrative). inDrive drivers can accept, decline or counter with no penalty. Uber upfront: declines not counted against acceptance (Gridwise, third party). | https://gridwise.io/blog/ubers-upfront-fares-bonus-or-bust-for-rideshare-drivers ; inDrive link above | have (bid/counter); timers visible to driver unknown |
| Earnings transparency | Uber upfront payout shown before accept; destination visibility varies by market. | https://www.ridesharingdriver.com/uber-driver-upfront-fares/ | partly (waybill/receipt exists; per-offer net payout display unknown) |
| Destination filter | Uber had destination mode (2015 coverage: limited uses per day; current rules UNVERIFIED). | https://techcrunch.com/2015/11/16/uber-drivers-can-now-pick-up-riders-headed-in-the-same-direction-as-them/amp/ | missing |
| Trip Radar | Uber lets drivers see nearby trips and pick one. | https://www.uber.com/newsroom/only-on-uber/ | N/A: our bid list is the equivalent |
| Instant pay | Uber Instant Pay: up to 6 cash-outs/day, $1.25 fee on personal debit card (official page, may change). | https://www.uber.com/us/en/drive/driver-app/instant-pay/ | missing (unknown) |
| Safety for drivers | Lyft audio recording and rider verification; Uber RideCheck notifies drivers too. | links above | missing |
| KYC / deactivation / tips / navigation hand-off | Not researched to an official source. UNVERIFIED. | n/a | KYC have (Checkr); others unknown |

## 3. California requirements (regulator and legislative sources)

Caveat: the original CPUC decision text was not opened; the summary comes from search results quoting a CPUC press release copy and Assembly analyses. Verify against the decision before relying on specifics.

| Requirement | Finding | Source | Us |
|---|---|---|---|
| Background checks + zero tolerance | CPUC Sept 2013 decision (D.13-09-045) created TNC class and rules: criminal background checks, zero-tolerance drug/alcohol policy, driver training, 19-point vehicle inspection. | https://www.autorentalnews.com/113961/cpuc-establishes-rules-for-transportation-network-companies ; https://files.cpuc.ca.gov/PG&E20150130ResponseToA1312012Ruling/2013/09/SB_GT&S_0141692.pdf | partly (Checkr KYC have; zero-tolerance policy page, complaint process and 19-point inspection record unknown) |
| Statutory background check list | Chapter 740, Stats 2016 (AB 880 analysis) put background-check requirements and disqualifying offenses in statute (PUC 5445.2). DMV checks at onboarding and periodic (SB 1080 analysis). | https://acom.assembly.ca.gov/sites/acom.assembly.ca.gov/files/AB%20880%20%28Obernolte%29_0.pdf ; https://atrn.assembly.ca.gov/sites/atrn.assembly.ca.gov/files/SB%201080%20%28Roth%29.pdf | verify Checkr package matches disqualifiers; DMV pull notice UNVERIFIED |
| Minors | D.24-12-004: enhanced background checks for drivers carrying unaccompanied minors (secondary source; we should bar minors alone). | https://docs.cpuc.ca.gov/PublishedDocs/Published/G000/M202/K234/202234451.pdf (search hit, not opened) | policy unknown |
| Insurance | $1M per-incident commercial liability during trips (original decision, via press coverage). Period-by-period tiers not verified. | autorentalnews link above | unknown, confirm policy |
| Access for All (SB 1376) | $0.10 per TNC trip; TNCs must show accessibility effort (WAV) or offset via local administrators; program extended to Jan 1, 2032 (CPUC press release). | https://sfmta.com/access-all-fund ; https://docs.cpuc.ca.gov/PublishedDocs/Published/G000/M369/K679/369679506.PDF ; https://webproda.cpuc.ca.gov/news-and-updates/all-news/cpuc-makes-tnc-data-available-to-the-public-and-creates-framework-for-access-for-all-compliance | have fee; annual reporting/offset filing unknown |
| Annual reports / data | TNCs file annual reports with CPUC; confidentiality presumption ended for 2014-2019 reports. | https://webproda.cpuc.ca.gov/news-and-updates/all-news/cpuc-makes-tnc-data-available-to-the-public-and-creates-framework-for-access-for-all-compliance | missing/unknown (data logging needed: trips, accessibility requests, complaints) |
| Waybill | Not confirmed from a CPUC document in this pass (UNVERIFIED); we already generate one. | n/a | have |

## 4. Ranked top 12 additions

1. Ride PIN verification (Uber precedent): generate 4-digit PIN at bid acceptance, show to rider, driver enters to start trip; reuse accepted-offer id as the key; optional night-default.
2. Off-route / long-stop / crash check-in (RideCheck/Smart Trip Check-In): compare driver GPS to agreed route corridor, push "are you OK" to both after N min stop or deviation, escalate to SOS.
3. Rider-visible "drivers contacted / offers received" count and countdown: surface the up-to-10 dispatch count and 5-min timer on the bid screen to reduce abandonment.
4. CPUC compliance data pack: zero-tolerance policy page + reporting flow, log accessibility requests/refusals, trip counts, complaints so annual CPUC reports are a query; verify against decision text.
5. Audio recording (opt-in, encrypted, short retention, attach to safety report): Lyft model; reuse in-ride chat/call infrastructure.
6. Driver safety parity: rider verification (phone/ID or payment-verified) and drivers able to see rider rating on an offer; Lyft precedent.
7. Fair bid guardrails (inDrive precedent): suggested fare + min/max band around distance-time price, no-penalty declines/counters, so low-ball offers do not poison driver trust.
8. Cancellation / no-show / wait-time rules with disability waiver: grace from arrival, then fee that goes to driver, rider cancel-after-accept fee; waive for accessibility requests.
9. Driver earnings clarity per offer: show net payout after $1-$3 fee on each bid and in the accepted trip; supports upfront-payout expectation set by Uber.
10. Accessibility completeness: service-animal acceptance rule with cancellation penalty/deactivation path, WAV request routing, and Access-for-All reporting hook.
11. Scheduled rides hardening: run the bid window ahead of pickup (confirm 15-60 min before), driver reminder, late-cancel fee; test end to end.
12. Driver destination filter + instant payout option (Stripe instant payouts): filter offers by heading; both are widely used driver retention features, fee disclosed to driver.

Not recommended without more evidence: dispatch radius tuning (no public competitor data), audio recording details beyond opt-in.
