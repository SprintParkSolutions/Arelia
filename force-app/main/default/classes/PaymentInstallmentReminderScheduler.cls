global with sharing class PaymentInstallmentReminderScheduler
    implements Schedulable {

    global void execute(SchedulableContext sc) {
        sendPaymentReminders();
    }

    public static void sendPaymentReminders() {

        Date todayDate = Date.today();

        // =====================================================
        // 1. EXISTING REMINDER INTERVALS
        // =====================================================

        Set<Date> reminderDates = new Set<Date>{
            todayDate.addDays(20),
            todayDate.addDays(10),
            todayDate.addDays(7)
        };

        // =====================================================
        // 2. GET ALL UNPAID PROJECT PAYMENT TERMS
        // =====================================================

        List<Payment_Term__c> dueTerms = [
            SELECT
                Id,
                Name,
                Term_Label__c,
                Due_Date__c,
                Percentage__c,
                Payment_Received__c,
                Payment_Status__c,
                Reminder_20_Days_Sent__c,
                Reminder_10_Days_Sent__c,
                Reminder_7_Days_Sent__c,
                Project__c,
                Project__r.Name,
                Project__r.Client__c,
                Project__r.Project_Name__c
            FROM Payment_Term__c
            WHERE Due_Date__c IN :reminderDates
              AND Payment_Received__c = false
              AND Project__c != null
            ORDER BY Due_Date__c ASC, Id ASC
        ];

        if (dueTerms.isEmpty()) {
            System.debug(
                LoggingLevel.INFO,
                'PAYMENT REMINDER: No eligible unpaid installments.'
            );
            return;
        }

        // =====================================================
        // 3. PREPARE REMINDER TRACKING
        // =====================================================

        List<Payment_Term__c> termsToUpdate =
            new List<Payment_Term__c>();

        Integer queuedCount = 0;
        Integer skippedCount = 0;
        Integer failedCount = 0;

        // =====================================================
        // 4. PROCESS EACH PROJECT'S PAYMENT TERM
        // =====================================================

        for (Payment_Term__c termRec : dueTerms) {

            Integer daysRemaining =
                todayDate.daysBetween(
                    termRec.Due_Date__c
                );

            Boolean shouldSend = false;

            if (
                daysRemaining == 20 &&
                termRec.Reminder_20_Days_Sent__c != true
            ) {
                shouldSend = true;

            } else if (
                daysRemaining == 10 &&
                termRec.Reminder_10_Days_Sent__c != true
            ) {
                shouldSend = true;

            } else if (
                daysRemaining == 7 &&
                termRec.Reminder_7_Days_Sent__c != true
            ) {
                shouldSend = true;
            }

            if (!shouldSend) {
                continue;
            }

            // =================================================
            // 5. GET CUSTOMER CONTACT FOR ACTUAL PROJECT
            // =================================================

            Id projectId = termRec.Project__c;

            Id contactId =
                termRec.Project__r.Client__c;

            // The existing push service validates that
            // Project__c.Client__c matches this Contact.
            // Never send using an unrelated Contact ID.

            if (contactId == null) {

                skippedCount++;

                System.debug(
                    LoggingLevel.WARN,
                    'PAYMENT REMINDER SKIPPED: ' +
                    'Project does not have Client__c. ' +
                    'PaymentTerm=' + termRec.Id +
                    ', Project=' + projectId
                );

                continue;
            }

            // =================================================
            // 6. RESPECT SALESFORCE QUEUEABLE LIMITS
            // =================================================

            if (
                Limits.getQueueableJobs() >=
                Limits.getLimitQueueableJobs()
            ) {

                System.debug(
                    LoggingLevel.WARN,
                    'PAYMENT REMINDER: Queueable job limit reached. ' +
                    'Remaining reminders were not marked as sent.'
                );

                break;
            }

            // =================================================
            // 7. BUILD PAYMENT REMINDER MESSAGE
            // =================================================

            String projectName =
                termRec.Project__r.Name;

            if (String.isBlank(projectName)) {
                projectName = 'Your Project';
            }

            String paymentName =
                String.isBlank(termRec.Term_Label__c)
                    ? termRec.Name
                    : termRec.Term_Label__c;

            if (String.isBlank(paymentName)) {
                paymentName = 'Payment installment';
            }

            String percentageText = '';

            if (termRec.Percentage__c != null) {

                percentageText =
                    ' Payment percentage: ' +
                    String.valueOf(termRec.Percentage__c) +
                    '%.';
            }

            String messageBody =
                '"' + paymentName +
                '" for project "' +
                projectName +
                '" is due in ' +
                String.valueOf(daysRemaining) +
                ' days, on ' +
                String.valueOf(termRec.Due_Date__c) +
                '.' +
                percentageText;

            // =================================================
            // 8. SEND MULTI-PROJECT PUSH NOTIFICATION
            // =================================================

            try {

                // This is the existing six-parameter
                // method in AreliaPushNotificationService.
                //
                // Contact ID = current project's client.
                // Record ID = actual Payment Term ID.
                // Project ID = actual Project__c ID.

                AreliaPushNotificationService.sendToContactAsync(
                    contactId,
                    'Payment Reminder',
                    messageBody,
                    'payment_reminder',
                    String.valueOf(termRec.Id),
                    projectId
                );

                // =================================================
                // 9. MARK ONLY THE QUEUED REMINDER FLAG
                // =================================================

                Payment_Term__c updateRec =
                    new Payment_Term__c(
                        Id = termRec.Id
                    );

                if (daysRemaining == 20) {

                    updateRec.Reminder_20_Days_Sent__c =
                        true;

                } else if (daysRemaining == 10) {

                    updateRec.Reminder_10_Days_Sent__c =
                        true;

                } else if (daysRemaining == 7) {

                    updateRec.Reminder_7_Days_Sent__c =
                        true;
                }

                termsToUpdate.add(updateRec);

                queuedCount++;

                System.debug(
                    LoggingLevel.INFO,
                    'PAYMENT REMINDER QUEUED: ' +
                    'PaymentTerm=' + termRec.Id +
                    ', Project=' + projectId +
                    ', Contact=' + contactId +
                    ', DaysRemaining=' + daysRemaining
                );

            } catch (Exception ex) {

                failedCount++;

                System.debug(
                    LoggingLevel.ERROR,
                    'PAYMENT REMINDER FAILED: ' +
                    'PaymentTerm=' + termRec.Id +
                    ', Project=' + projectId +
                    ', Error=' + ex.getMessage()
                );
            }
        }

        // =====================================================
        // 10. UPDATE REMINDER FLAGS
        // =====================================================

        if (!termsToUpdate.isEmpty()) {

            update termsToUpdate;
        }

        // =====================================================
        // 11. EXECUTION SUMMARY
        // =====================================================

        System.debug(
            LoggingLevel.INFO,
            '=== PAYMENT REMINDER SUMMARY === ' +
            'Eligible=' + dueTerms.size() +
            ', Queued=' + queuedCount +
            ', Skipped=' + skippedCount +
            ', Failed=' + failedCount
        );
    }
}