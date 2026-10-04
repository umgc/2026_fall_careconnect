import '../models/help_article.dart';
import '../models/help_category.dart';
import '../models/help_role.dart';
import '../models/help_section.dart';
import 'help_content_ids.dart';

/// Compiled into the app: reading Help needs no network, database, or plugin.
const bundledHelpCategories = <HelpCategory>[
  HelpCategory(
    id: HelpCategoryIds.gettingStarted,
    title: 'Getting Started',
    description: 'Find your way around CareConnect and the Help Center.',
  ),
  HelpCategory(
      id: HelpCategoryIds.medications,
      title: 'Medications',
      description: 'View medication details and record a dose.'),
  HelpCategory(
      id: HelpCategoryIds.checkIns,
      title: 'Daily Check-Ins',
      description:
          'Share how you are feeling and understand check-in options.'),
  HelpCategory(
      id: HelpCategoryIds.appointments,
      title: 'Appointments',
      description: 'Find scheduled care visits.'),
  HelpCategory(
      id: HelpCategoryIds.messaging,
      title: 'Messaging',
      description: 'Connect with your caregiver.'),
  HelpCategory(
      id: HelpCategoryIds.account,
      title: 'Account and Settings',
      description: 'Get help signing in and resetting your password.'),
];

final bundledHelpArticles = List<HelpArticle>.unmodifiable([
  HelpArticle(
    id: HelpArticleIds.gettingStarted,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Getting started with CareConnect',
    summary: 'Learn where to find your care information and everyday tools.',
    roles: [HelpRole.patient],
    sections: [
      const HelpParagraph(
          text: 'Your Patient Home brings together care information, '
              'medication reminders, and scheduled visits. The information shown depends '
              'on what has been added to your account.'),
      HelpSteps(steps: [
        'Sign in with your CareConnect account and open Home.',
        'Use Health to open Daily Check-In, or Symptoms to view the symptom and allergy tracker.',
        'Use Messages to find your conversations.',
        'Open Menu for Medication Tracker, Calendar Assistant, and Settings.',
        'In Settings, scroll to General and select Help to return to the Help Center.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'My care information is missing.',
            solution:
                'Check that you are signed in to the correct Patient account and '
                'have a connection. Ask your caregiver to check that your account is linked and your information has been added.'),
      ]),
      HelpRelatedArticles(articleIds: [
        HelpArticleIds.recordingDose,
        HelpArticleIds.dailyCheckIn,
        HelpArticleIds.messagingCaregiver
      ]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.recordingDose,
    categoryId: HelpCategoryIds.medications,
    title: 'Viewing medications and recording a dose',
    summary:
        'Find your medication list and use a Home reminder to mark a dose taken.',
    roles: [HelpRole.patient],
    sections: [
      HelpSteps(steps: [
        'Open Menu and select Medication Tracker to view medication names, dosages, and schedules.',
        'Return to Home and find Medication Reminders.',
        'Locate the reminder for the dose you have taken and select Mark Taken.',
        'Check that the reminder shows Taken. If an error appears, the update may not have been saved.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'There is no medication or reminder listed.',
            solution:
                'Check your connection and ask your caregiver to review the medication information on your account.'),
        const HelpTroubleshootingTip(
            problem: 'Mark Taken did not save.',
            solution:
                'Check your connection and reload Home to check the reminder status before trying again.'),
      ]),
      HelpRelatedArticles(articleIds: [HelpArticleIds.messagingCaregiver]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.dailyCheckIn,
    categoryId: HelpCategoryIds.checkIns,
    title: 'Completing a daily check-in',
    summary:
        'Choose your mood, add notes, and understand the current submission limit.',
    roles: [HelpRole.patient],
    sections: [
      const HelpParagraph(
          text: 'Daily Check-In lets you choose a mood and enter notes. '
              'In this version, Submit Check-In displays a mock confirmation; it does not '
              'save or send those responses to your caregiver. Use Messages if you need to share them.'),
      HelpSteps(steps: [
        'Select Health in the Patient navigation to open Daily Check-In.',
        'Review any Assigned Check-In Questionnaire shown on the screen.',
        'Select your mood under How are you feeling today?',
        'Enter any notes under Any symptoms or notes?',
        'Select Submit Check-In to see the current demo confirmation. Send your update in Messages if your caregiver needs to receive it.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'Submit Check-In is disabled.',
            solution: 'Select a mood first to enable the button.'),
        const HelpTroubleshootingTip(
            problem: 'No questionnaire is assigned.',
            solution:
                'Ask your caregiver whether a questionnaire should be assigned to your account.'),
        const HelpTroubleshootingTip(
            problem: 'Video recording is unavailable.',
            solution:
                'Camera support depends on your device. You can still choose a mood and enter notes; use Messages to share an update.'),
      ]),
      HelpRelatedArticles(articleIds: [HelpArticleIds.messagingCaregiver]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.viewingAppointments,
    categoryId: HelpCategoryIds.appointments,
    title: 'Viewing appointments',
    summary: 'Find upcoming care visits and their scheduled date and time.',
    roles: [HelpRole.patient],
    sections: [
      const HelpParagraph(
          text: 'Home lists upcoming scheduled care visits under '
              'Upcoming EVV Appointments. EVV refers to electronic visit verification.'),
      HelpSteps(steps: [
        'Open Home and scroll to Upcoming EVV Appointments.',
        'Read the service, date, and time listed for each visit.',
        'Select the refresh icon in that section to reload the schedule.',
        'If the schedule needs to change, message your caregiver to confirm the details.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'An expected appointment is missing.',
            solution:
                'Check your connection and refresh the appointment section. If the visit is still missing, ask your caregiver to confirm it is scheduled.'),
      ]),
      HelpRelatedArticles(articleIds: [HelpArticleIds.messagingCaregiver]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.messagingCaregiver,
    categoryId: HelpCategoryIds.messaging,
    title: 'Messaging your caregiver',
    summary: 'Open a conversation, send a message, and retry a failed message.',
    roles: [HelpRole.patient],
    sections: [
      HelpSteps(steps: [
        'Select Messages in the Patient navigation.',
        'Open your caregiver conversation. To start a conversation, use Contacts and select your caregiver if they are listed.',
        'Type your message in the message field.',
        'Select the send icon and check the conversation for the message.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'My caregiver is not listed or messaging is unavailable.',
            solution:
                'Ask your caregiver to check the account link and messaging availability.'),
        const HelpTroubleshootingTip(
            problem: 'Message failed to send.',
            solution:
                'Check your connection, then select Retry beside the failed message.'),
      ]),
      HelpRelatedArticles(articleIds: [HelpArticleIds.gettingStarted]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.resettingPassword,
    categoryId: HelpCategoryIds.account,
    title: 'Resetting your password',
    summary: 'Request an email reset link when you cannot sign in.',
    roles: HelpRole.values,
    sections: [
      HelpSteps(steps: [
        'On the sign-in screen, select Forgot Password?.',
        'Enter the email address associated with your CareConnect account.',
        'Select Send Reset Link while connected to the internet.',
        'Open the reset email and follow its link to choose a new password.',
        'Return to sign in with your new password.',
      ]),
      HelpTroubleshooting(tips: [
        const HelpTroubleshootingTip(
            problem: 'I cannot find the reset email.',
            solution:
                'Check your spam or junk folder and confirm you entered your account email. If no email arrives, contact the team that manages your CareConnect account.'),
        const HelpTroubleshootingTip(
            problem: 'The reset link does not work.',
            solution:
                'Request a new link and use the most recent reset email.'),
      ]),
      HelpRelatedArticles(articleIds: [HelpArticleIds.gettingStarted]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.openingHelp,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Opening Help',
    summary: 'Find the Help Center from Settings.',
    roles: HelpRole.values,
    sections: [
      const HelpParagraph(
        text: 'The Help Center provides guides for using CareConnect.',
      ),
      HelpSteps(
        heading: 'Open Help',
        steps: [
          'Open Settings.',
          'Scroll down to General.',
          'Select Help, above Offline Persistence.',
        ],
      ),
      HelpTroubleshooting(
        tips: [
          const HelpTroubleshootingTip(
            problem: 'I cannot see the General section.',
            solution: 'Scroll down in Settings until you reach General.',
          ),
        ],
      ),
      HelpRelatedArticles(articleIds: [HelpArticleIds.readingHelp]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.readingHelp,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Reading Help articles',
    summary: 'Open a guide and follow links to other useful articles.',
    roles: HelpRole.values,
    sections: [
      const HelpParagraph(
        text: 'You can read Help articles without an internet connection. '
            'Some app features described in a guide may still require a connection.',
      ),
      HelpSteps(
        steps: [
          'Select an article on the Help Center home screen.',
          'Follow the numbered steps in the article.',
          'Select a related article to read another guide.',
          'Use the back button to return to the previous screen.',
        ],
      ),
      HelpTroubleshooting(
        tips: [
          const HelpTroubleshootingTip(
            problem: 'An article is unavailable.',
            solution:
                'Return to the Help Center and select an available article.',
          ),
        ],
      ),
      HelpRelatedArticles(articleIds: [HelpArticleIds.openingHelp]),
    ],
  ),
]);
