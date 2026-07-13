package com.careconnect.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class ReminderDispatcher {

    private final SesService sesService;
    private final SnsService snsService;
    private final Logger log = LoggerFactory.getLogger(ReminderDispatcher.class);

    @Value("${notifications.demo.toEmail:}")
    private String demoEmail;

    @Value("${notifications.demo.toPhone:}")
    private String demoPhone;

    @Value("${notifications.reminder.enabled:true}")
    private boolean remindersEnabled;

    public ReminderDispatcher(SesService sesService, SnsService snsService) {
        this.sesService = sesService;
        this.snsService = snsService;
    }

    @Scheduled(cron = "${notifications.reminder.cron:0 0 7 * * *}") // Default 7 AM daily // Default 10 minutes
    public void sendDemoReminder() {
        if (!remindersEnabled) {
            log.debug("Automated reminders are disabled");
            return;
        }

        if ((demoEmail == null || demoEmail.isEmpty()) && (demoPhone == null || demoPhone.isEmpty())) {
            log.debug("No demo addresses configured for ReminderDispatcher");
            return;
        }

        String subject = "Reminder: Upcoming Appointment";
        String html = "<h1>Appointment Reminder</h1><p>This is a demo reminder for your upcoming appointment.</p>";
        String text = "This is a demo reminder for your upcoming appointment.";

        try {
            if (demoEmail != null && !demoEmail.isEmpty()) {
                String id = sesService.sendEmail(demoEmail, subject, html, text);
                log.info("Demo reminder email queued messageId={}", id);
            }
        } catch (Exception e) {
            log.warn("Failed to send demo reminder email: {}", e.getMessage());
        }

        try {
            if (demoPhone != null && !demoPhone.isEmpty()) {
                String id = snsService.publishSms(demoPhone, text);
                log.info("Demo reminder SMS queued messageId={}", id);
            }
        } catch (Exception e) {
            log.warn("Failed to send demo reminder SMS: {}", e.getMessage());
        }
    }

    // Future enhancement: Scheduled medication reminders
    // @Scheduled(fixedRateString = "${notifications.medication.checkRate:300000}") // Every 5 minutes
    public void checkAndSendMedicationReminders() {
        // TODO: Implement logic to check for upcoming medication times
        // This would query the database for medications due soon and send reminders
        // based on patient preferences and notification settings
        log.debug("Medication reminder check not yet implemented");
    }

    // Future enhancement: Scheduled appointment reminders
    // @Scheduled(fixedRateString = "${notifications.appointment.checkRate:900000}") // Every 15 minutes
    public void checkAndSendAppointmentReminders() {
        // TODO: Implement logic to check for upcoming appointments
        // This would query the database for appointments in the next 24 hours
        // and send reminders based on patient preferences
        log.debug("Appointment reminder check not yet implemented");
    }

    // Future enhancement: Vital signs monitoring alerts
    // @Scheduled(fixedRateString = "${notifications.vitals.checkRate:180000}") // Every 3 minutes
    public void checkAndSendVitalAlerts() {
        // TODO: Implement logic to monitor vital signs and send alerts
        // when values are outside normal ranges based on patient thresholds
        log.debug("Vital signs alert check not yet implemented");
    }
}
