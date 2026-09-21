import 'package:flutter/material.dart';

import 'legal_document.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String routeName = '/privacy-policy';

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      title: 'Privacy Policy',
      subtitle:
          'What MedGuard collects, how it is used, and the controls you have '
          'over it.',
      documentLabel: 'MedGuard privacy policy',
      updatedAt: 'April 26, 2026',
      summary: [
        LegalPoint(
          icon: Icons.health_and_safety_rounded,
          text:
              'Your information is used only to run, secure and improve '
              'MedGuard.',
        ),
        LegalPoint(
          icon: Icons.block_rounded,
          text: 'Your medication data is never sold or used for advertising.',
        ),
        LegalPoint(
          icon: Icons.key_rounded,
          text: 'Sign-in is handled by Firebase and the provider you choose.',
        ),
        LegalPoint(
          icon: Icons.how_to_reg_rounded,
          text: 'You can ask to access, correct or delete your information.',
        ),
      ],
      groups: [
        LegalGroup(
          title: 'What is collected',
          clauses: [
            LegalClause(
              title: 'Scope of this policy',
              icon: Icons.policy_rounded,
              paragraphs: [
                'This Privacy Policy applies to MedGuard mobile app accounts, authentication, medication-safety workflows, local app data, and support interactions. It covers information you provide directly, information generated when you use MedGuard, and information received from sign-in providers when you choose Google, Apple, or Microsoft.',
                'MedGuard is designed as medication safety support. It is not a substitute for a licensed clinician, pharmacist, emergency service, or official medicine label.',
              ],
            ),
            LegalClause(
              title: 'Information you provide',
              icon: Icons.edit_note_rounded,
              bullets: [
                'Account details such as full name, email address, password credentials managed by Firebase Authentication, and the sign-in method you choose.',
                'Profile details such as account type or role when you provide them to tailor language and workflows.',
                'Medication-related entries you add, including medicine names, identifiers, timing details, allergies, notes, or profile factors needed for safety checks.',
                'Messages, feedback, bug reports, support requests, or other communications you send to MedGuard.',
                'Consent records showing whether you accepted the Terms & Conditions and this Privacy Policy.',
              ],
            ),
            LegalClause(
              title: 'Information collected automatically',
              icon: Icons.sensors_rounded,
              bullets: [
                'Authentication events, account identifiers, provider identifiers, and session state needed to keep you signed in securely.',
                'Device and app information such as operating system, app version, language, broad region, crash logs, and diagnostic events used to keep MedGuard reliable.',
                'Security signals such as failed sign-in attempts, unusual account activity, rate-limit events, and abuse-prevention data.',
                'Local app preferences such as onboarding completion and interface settings stored on your device.',
              ],
            ),
            LegalClause(
              title: 'Sensitive health information',
              icon: Icons.health_and_safety_rounded,
              paragraphs: [
                'Medication lists, allergies, patient-specific flags, and safety-check results may be sensitive. MedGuard treats this information as private and uses it only to provide, secure, troubleshoot, and improve the app experience.',
                'Avoid adding information about another person unless you have permission or a lawful reason to manage that person\'s medication information.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'How it is used and shared',
          clauses: [
            LegalClause(
              title: 'How MedGuard uses information',
              icon: Icons.settings_suggest_rounded,
              bullets: [
                'Create and secure your account, authenticate sign-ins, prevent unauthorized access, and recover accounts.',
                'Run medication safety checks, show interaction warnings, detect duplicate therapy, support allergy or patient-specific checks, and maintain app preferences.',
                'Provide support, respond to requests, troubleshoot bugs, and improve reliability, accessibility, and usability.',
                'Protect MedGuard, users, and the public from misuse, fraud, automated abuse, or security threats.',
                'Meet legal, regulatory, accounting, security, and compliance obligations where they apply.',
              ],
            ),
            LegalClause(
              title: 'Firebase and sign-in providers',
              icon: Icons.key_rounded,
              paragraphs: [
                'MedGuard uses Firebase Authentication to support email/password sign-in and federated sign-in. When you use Google, Apple, or Microsoft, those providers may share basic account information such as name, email, provider user ID, and profile metadata needed to authenticate you.',
                'Your relationship with Google, Apple, or Microsoft is also governed by their own privacy policies and account settings. MedGuard does not control those providers.',
              ],
            ),
            LegalClause(
              title: 'Sharing and disclosure',
              icon: Icons.share_rounded,
              bullets: [
                'Service providers: trusted vendors may process information for hosting, authentication, diagnostics, analytics, support, or security under appropriate confidentiality and data-protection obligations.',
                'Legal and safety reasons: information may be disclosed when required by law, court order, regulator, valid legal process, or to protect rights, safety, security, and app integrity.',
                'Business changes: information may be transferred as part of a merger, acquisition, financing, reorganization, or asset sale, subject to appropriate protections.',
                'With your direction: MedGuard may share information when you ask us to export, connect, or send it to another service or person.',
              ],
            ),
            LegalClause(
              title: 'What MedGuard does not do',
              icon: Icons.block_rounded,
              bullets: [
                'MedGuard does not sell your medication data.',
                'MedGuard does not use your medication data for third-party advertising.',
                'MedGuard does not intentionally collect payment card data inside the current app flow.',
                'MedGuard does not make emergency decisions or contact emergency services on your behalf.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Keeping it safe',
          clauses: [
            LegalClause(
              title: 'Data retention',
              icon: Icons.inventory_2_rounded,
              paragraphs: [
                'MedGuard keeps account information while your account is active and as long as needed to provide the service, meet legal obligations, resolve disputes, enforce agreements, protect security, and maintain backups.',
                'Local device data may remain on your device until you delete it, uninstall the app, clear app storage, or use an available delete/export control. Backup systems may retain limited copies for a reasonable period before they expire.',
              ],
            ),
            LegalClause(
              title: 'Security safeguards',
              icon: Icons.shield_rounded,
              bullets: [
                'Authentication is handled through Firebase Authentication and supported identity providers.',
                'MedGuard uses reasonable administrative, technical, and organizational safeguards appropriate to the sensitivity of medication information.',
                'No app, device, network, or storage system can be guaranteed to be completely secure. Use a strong password, protect your device, and sign out on shared devices.',
              ],
            ),
          ],
        ),
        LegalGroup(
          title: 'Your rights and changes',
          clauses: [
            LegalClause(
              title: 'Your choices and rights',
              icon: Icons.how_to_reg_rounded,
              bullets: [
                'You may update account information that the app allows you to edit.',
                'You may request access, correction, deletion, portability, or restriction of certain information where applicable law provides those rights.',
                'You may withdraw optional consent where withdrawal is available, but MedGuard may still process information needed for security, legal compliance, or service delivery.',
                'You may use device controls to limit notifications, permissions, diagnostics, or app storage where your operating system supports those controls.',
              ],
            ),
            LegalClause(
              title: 'Children and dependents',
              icon: Icons.family_restroom_rounded,
              paragraphs: [
                'MedGuard is not intended for unsupervised use by children. A parent, guardian, caregiver, or authorized professional should manage any dependent profile only where they have permission or a lawful basis to do so.',
              ],
            ),
            LegalClause(
              title: 'International use',
              icon: Icons.public_rounded,
              paragraphs: [
                'Your information may be processed in countries other than where you live. Those countries may have different data-protection laws. MedGuard uses reasonable safeguards where cross-border processing requires them.',
              ],
            ),
            LegalClause(
              title: 'Changes to this policy',
              icon: Icons.update_rounded,
              paragraphs: [
                'MedGuard may update this policy to reflect product, legal, security, or operational changes. Material changes should be presented in the app or through another reasonable notice method. Continued use after an update means the updated policy applies.',
              ],
            ),
            LegalClause(
              title: 'Contact',
              icon: Icons.support_agent_rounded,
              paragraphs: [
                'For privacy questions, access requests, corrections, deletion requests, or safety concerns, contact the MedGuard team through the support channel provided in the app or project documentation.',
              ],
            ),
          ],
        ),
      ],
    );
  }
}
