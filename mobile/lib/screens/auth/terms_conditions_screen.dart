import 'package:flutter/material.dart';

import 'legal_document.dart';

/// The Terms & Conditions, on the shared legal document layout — the same page
/// as the Privacy Policy, so the two documents a new user is asked to accept
/// read as a pair.
class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  static const String routeName = '/terms-conditions';

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Terms & Conditions',
      subtitle:
          'The agreement that covers using MedGuard. The short version comes '
          'first.',
      documentLabel: 'MedGuard terms and conditions',
      updatedAt: 'April 26, 2026',
      summary: [
        LegalPoint(
          icon: Icons.favorite_rounded,
          text:
              'Decision support — never a diagnosis, prescription, or guarantee.',
        ),
        LegalPoint(
          icon: Icons.local_hospital_rounded,
          text: 'Always confirm with a clinician or pharmacist before acting.',
        ),
        LegalPoint(
          icon: Icons.lock_rounded,
          text: 'You stay responsible for the medicines and details you enter.',
        ),
        LegalPoint(
          icon: Icons.update_rounded,
          text: 'These terms can change — we show major updates in the app.',
        ),
      ],
      groups: [
        LegalGroup(
          title: 'Getting started',
          clauses: [
            LegalClause(
              title: 'Agreement to these terms',
              icon: Icons.handshake_rounded,
              paragraphs: [
                'By creating an account, signing in, or using MedGuard, you agree to these Terms & Conditions and the Privacy Policy. If you do not agree, do not create an account or use the app.',
                'If you use MedGuard for another person or on behalf of an organization, you confirm that you have authority to do so and that you will follow any duties that apply to that relationship.',
              ],
            ),
            LegalClause(
              title: 'What MedGuard is',
              icon: Icons.favorite_rounded,
              paragraphs: [
                'MedGuard is a medication safety support tool. It can help review potential drug-drug interactions, food and drink conflicts, duplicate therapy signals, dose-range concerns, allergy risks, and patient-specific flags.',
                'MedGuard provides educational and decision-support information only. It does not diagnose, prescribe, dispense, treat, replace professional judgment, or guarantee that a medicine plan is safe.',
              ],
            ),
            LegalClause(
              title: 'Required consent for account creation',
              icon: Icons.how_to_reg_rounded,
              paragraphs: [
                'Creating a MedGuard account requires acceptance of both the Terms & Conditions and Privacy Policy. This applies to email/password registration and to Google, Apple, or Microsoft registration.',
                'If a social sign-in provider would create a new account, MedGuard may require acceptance of these documents before allowing the account to continue.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Safety comes first',
          clauses: [
            LegalClause(
              title: 'Medical and emergency disclaimer',
              icon: Icons.emergency_rounded,
              emphasized: true,
              bullets: [
                'Always consult a qualified clinician, pharmacist, or emergency service for medical decisions, urgent symptoms, severe reactions, poisoning, overdose, pregnancy concerns, or medicine changes.',
                'Do not ignore professional medical advice because of information shown in MedGuard.',
                'Do not start, stop, split, combine, substitute, or change medicine doses based only on MedGuard output.',
                'MedGuard safety checks can be incomplete, outdated, incorrectly configured, or limited by the information you enter.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Your account and data',
          clauses: [
            LegalClause(
              title: 'Eligibility and account responsibility',
              icon: Icons.verified_user_rounded,
              bullets: [
                'You must be legally able to accept these terms and use MedGuard in your location.',
                'You are responsible for the accuracy of account details and medication information you enter.',
                'You must keep your password, device, and sign-in providers secure and notify MedGuard if you suspect unauthorized access.',
                'You may not create accounts using false, misleading, unauthorized, or unlawful information.',
              ],
            ),
            LegalClause(
              title: 'Medication data and user content',
              icon: Icons.local_pharmacy_rounded,
              paragraphs: [
                'You retain responsibility for medication lists, allergies, notes, profile factors, and other content you enter. You grant MedGuard the limited permission needed to store, process, display, secure, troubleshoot, and improve the service.',
                'You must review warnings, medicine names, strengths, timing, patient factors, and source information carefully. Similar drug names, missing records, local brand differences, and data-entry mistakes can change results.',
              ],
            ),
            LegalClause(
              title: 'Third-party services',
              icon: Icons.hub_rounded,
              paragraphs: [
                'MedGuard may rely on Firebase, Google, Apple, Microsoft, operating-system services, analytics, diagnostics, databases, or other third-party tools. Those services may have separate terms, privacy notices, rate limits, outages, and configuration requirements.',
                'MedGuard is not responsible for third-party provider outages, account restrictions, identity-provider decisions, operating-system limitations, or changes to external services.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Using MedGuard',
          clauses: [
            LegalClause(
              title: 'Acceptable use',
              icon: Icons.rule_rounded,
              bullets: [
                'Use MedGuard only for lawful, personal, educational, caregiving, clinical-support, or authorized professional purposes.',
                'Do not attempt to reverse engineer, scrape, overload, probe, bypass, or disrupt MedGuard, Firebase, identity providers, or clinical data sources.',
                'Do not upload malicious code, unlawful content, abusive content, or information you do not have permission to process.',
                'Do not misrepresent MedGuard output as a final clinical decision or official medical record unless separately verified by an authorized professional.',
                'Do not use MedGuard to harm, discriminate against, exploit, or make automated high-risk decisions about another person.',
              ],
            ),
            LegalClause(
              title: 'Availability and changes',
              icon: Icons.sync_rounded,
              bullets: [
                'MedGuard may change, suspend, restrict, or discontinue features, content, authentication methods, databases, or accounts when needed for safety, security, maintenance, legal compliance, or product development.',
                'Clinical data and safety rules may be updated, corrected, expanded, or removed over time.',
                'MedGuard may impose reasonable limits on storage, requests, sign-in attempts, or usage to protect security and reliability.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Rights and ownership',
          clauses: [
            LegalClause(
              title: 'Intellectual property',
              icon: Icons.copyright_rounded,
              paragraphs: [
                'MedGuard, including its design, branding, source code, workflows, text, graphics, and compiled datasets, is protected by intellectual-property laws unless a separate license says otherwise.',
                'These terms do not transfer ownership of MedGuard or any third-party content to you. You receive only a limited, revocable, non-exclusive, non-transferable right to use the app as permitted by these terms.',
              ],
            ),
            LegalClause(
              title: 'Feedback',
              icon: Icons.lightbulb_rounded,
              paragraphs: [
                'If you send ideas, improvements, bug reports, usability notes, or other feedback, MedGuard may use that feedback without restriction or compensation, while continuing to handle personal information under the Privacy Policy.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Legal and liability',
          clauses: [
            LegalClause(
              title: 'Suspension and termination',
              icon: Icons.block_rounded,
              bullets: [
                'You may stop using MedGuard at any time.',
                'MedGuard may suspend or terminate access if you violate these terms, create risk, misuse the service, infringe rights, create security concerns, or if continued service is not commercially or legally practical.',
                'After termination, sections about medical disclaimers, intellectual property, privacy, limitation of liability, disputes, and any obligations that naturally survive will continue to apply.',
              ],
            ),
            LegalClause(
              title: 'No warranties',
              icon: Icons.report_rounded,
              paragraphs: [
                'MedGuard is provided as-is and as-available. To the maximum extent allowed by law, MedGuard disclaims warranties of accuracy, completeness, merchantability, fitness for a particular purpose, uninterrupted availability, non-infringement, and error-free operation.',
                'Medication safety information can contain omissions, delays, conflicting sources, and context-specific limitations. You use MedGuard at your own risk and must independently verify important information.',
              ],
            ),
            LegalClause(
              title: 'Limitation of liability',
              icon: Icons.balance_rounded,
              paragraphs: [
                'To the maximum extent allowed by law, MedGuard and its contributors, maintainers, service providers, and affiliates will not be liable for indirect, incidental, special, consequential, exemplary, punitive, lost-profit, lost-data, clinical, personal injury, treatment, or reliance damages arising from use of the app.',
                'Where liability cannot be excluded, liability is limited to the smallest amount permitted by applicable law.',
              ],
            ),
            LegalClause(
              title: 'Indemnity',
              icon: Icons.gpp_maybe_rounded,
              paragraphs: [
                'You agree to defend, indemnify, and hold harmless MedGuard and its contributors, maintainers, service providers, and affiliates from claims, losses, liabilities, damages, costs, and expenses arising from your misuse of MedGuard, violation of these terms, unlawful content, or infringement of another person\'s rights.',
              ],
            ),
            LegalClause(
              title: 'Governing law and disputes',
              icon: Icons.gavel_rounded,
              paragraphs: [
                'These terms should be interpreted under the laws that apply to your relationship with MedGuard, unless consumer-protection law in your location requires otherwise. Before filing a formal dispute, you agree to try to resolve concerns by contacting MedGuard through the available support channel.',
              ],
            ),
            LegalClause(
              title: 'Updates to these terms',
              icon: Icons.update_rounded,
              paragraphs: [
                'MedGuard may update these terms to reflect product, legal, safety, or operational changes. Material updates should be shown in the app or through another reasonable notice method. Continued use after an update means the updated terms apply.',
              ],
            ),
            LegalClause(
              title: 'Contact',
              icon: Icons.support_agent_rounded,
              paragraphs: [
                'Questions about these terms, account access, privacy, safety concerns, or support requests should be sent through the support channel provided in the app or project documentation.',
              ],
            ),
          ],
        ),
      ],
    );
  }
}
