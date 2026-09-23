public without sharing class AreliaPaymentNotificationHandler {

    private static final String NOTIFICATION_TYPE = 'PAYMENT_UPDATE';

    /**
     * Handles Payment_Term__c updates and sends notifications
     * to the client related to the payment term's project.
     */
    public static void handleAfterUpdate(
        List<Payment_Term__c> newPaymentTerms,
        Map<Id, Payment_Term__c> oldPaymentTermMap
    ) {
        if (
            newPaymentTerms == null ||
            newPaymentTerms.isEmpty() ||
            oldPaymentTermMap == null ||
            oldPaymentTermMap.isEmpty()
        ) {
            return;
        }

        List<Payment_Term__c> changedPaymentTerms =
            getChangedPaymentTerms(
                newPaymentTerms,
                oldPaymentTermMap
            );

        if (changedPaymentTerms.isEmpty()) {
            return;
        }

        Set<Id> projectIds = collectProjectIds(changedPaymentTerms);

        if (projectIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'Payment notification skipped: no related Project found.'
            );
            return;
        }

        Map<Id, Project__c> projectMap =
            getAreliaProjects(projectIds);

        sendNotifications(
            changedPaymentTerms,
            oldPaymentTermMap,
            projectMap
        );
    }

    /**
     * Returns payment terms where a monitored field changed.
     */
    private static List<Payment_Term__c> getChangedPaymentTerms(
        List<Payment_Term__c> newPaymentTerms,
        Map<Id, Payment_Term__c> oldPaymentTermMap
    ) {
        List<Payment_Term__c> changedPaymentTerms =
            new List<Payment_Term__c>();

        for (Payment_Term__c newTerm : newPaymentTerms) {
            Payment_Term__c oldTerm =
                oldPaymentTermMap.get(newTerm.Id);

            if (oldTerm == null) {
                continue;
            }

            if (hasRelevantChange(newTerm, oldTerm)) {
                changedPaymentTerms.add(newTerm);
            }
        }

        return changedPaymentTerms;
    }

    /**
     * Checks fields exposed through PaymentTermRestService.
     */
    private static Boolean hasRelevantChange(
        Payment_Term__c newTerm,
        Payment_Term__c oldTerm
    ) {
        return newTerm.Percentage__c != oldTerm.Percentage__c ||
            newTerm.Due_Date__c != oldTerm.Due_Date__c ||
            newTerm.Payment_Received__c != oldTerm.Payment_Received__c ||
            newTerm.Term_Label__c != oldTerm.Term_Label__c ||
            newTerm.Project__c != oldTerm.Project__c;
    }

    /**
     * Collects related Project IDs.
     */
    private static Set<Id> collectProjectIds(
        List<Payment_Term__c> paymentTerms
    ) {
        Set<Id> projectIds = new Set<Id>();

        for (Payment_Term__c paymentTerm : paymentTerms) {
            if (paymentTerm.Project__c != null) {
                projectIds.add(paymentTerm.Project__c);
            }
        }

        return projectIds;
    }

    /**
     * Retrieves Arelia projects and their client contacts.
     */
    private static Map<Id, Project__c> getAreliaProjects(
        Set<Id> projectIds
    ) {
        return new Map<Id, Project__c>([
            SELECT
                Id,
                Name,
                Client__c,
                RecordType.Name
            FROM Project__c
            WHERE Id IN :projectIds
            AND RecordType.Name = 'Arelia'
        ]);
    }

    /**
     * Sends mobile push notifications.
     */
    private static void sendNotifications(
        List<Payment_Term__c> changedPaymentTerms,
        Map<Id, Payment_Term__c> oldPaymentTermMap,
        Map<Id, Project__c> projectMap
    ) {
        for (Payment_Term__c newTerm : changedPaymentTerms) {
            Project__c relatedProject =
                projectMap.get(newTerm.Project__c);

            if (relatedProject == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'Payment notification skipped for Payment Term ' +
                    newTerm.Id +
                    ': related Arelia Project was not found.'
                );
                continue;
            }

            if (relatedProject.Client__c == null) {
                System.debug(
                    LoggingLevel.WARN,
                    'Payment notification skipped for Payment Term ' +
                    newTerm.Id +
                    ': Client__c is empty on the related Project.'
                );
                continue;
            }

            Payment_Term__c oldTerm =
                oldPaymentTermMap.get(newTerm.Id);

            NotificationContent content =
                buildNotificationContent(
                    newTerm,
                    oldTerm,
                    relatedProject.Name
                );

            AreliaPushNotificationService.sendToContactAsync(
                relatedProject.Client__c,
                content.title,
                content.messageBody,
                NOTIFICATION_TYPE,
                String.valueOf(newTerm.Id)
            );
        }
    }

    /**
     * Creates the notification title and message.
     */
    private static NotificationContent buildNotificationContent(
        Payment_Term__c newTerm,
        Payment_Term__c oldTerm,
        String projectName
    ) {
        List<String> changes = new List<String>();

        /*
         * When Payment_Received__c changes to true, no additional
         * "marked as received" message is added.
         *
         * When it changes back to false, the pending message is added.
         */
        if (
            newTerm.Payment_Received__c !=
            oldTerm.Payment_Received__c &&
            newTerm.Payment_Received__c != true
        ) {
            changes.add(
                'The payment has been marked as pending.'
            );
        }

        if (newTerm.Percentage__c != oldTerm.Percentage__c) {
            changes.add(
                buildPercentageMessage(newTerm.Percentage__c)
            );
        }

        if (newTerm.Due_Date__c != oldTerm.Due_Date__c) {
            changes.add(
                buildDueDateMessage(newTerm.Due_Date__c)
            );
        }

        if (newTerm.Term_Label__c != oldTerm.Term_Label__c) {
            changes.add(
                buildTermLabelMessage(newTerm.Term_Label__c)
            );
        }

        if (
            newTerm.Project__c != oldTerm.Project__c &&
            changes.isEmpty()
        ) {
            changes.add(
                'The related project for this payment term was updated.'
            );
        }

        String title = determineNotificationTitle(
            newTerm,
            oldTerm
        );

        String termName = getTermDisplayName(newTerm);

        String messageBody =
            termName +
            ' for project ' +
            projectName +
            ' was updated.';

        if (!changes.isEmpty()) {
            messageBody += ' ' + String.join(changes, ' ');
        }

        return new NotificationContent(
            title,
            messageBody
        );
    }

    /**
     * Determines the notification title.
     */
    private static String determineNotificationTitle(
        Payment_Term__c newTerm,
        Payment_Term__c oldTerm
    ) {
        if (
            newTerm.Payment_Received__c !=
            oldTerm.Payment_Received__c
        ) {
            if (newTerm.Payment_Received__c == true) {
                return 'Payment Received';
            }

            return 'Payment Status Updated';
        }

        if (newTerm.Due_Date__c != oldTerm.Due_Date__c) {
            return 'Payment Due Date Updated';
        }

        return 'Payment Term Updated';
    }

    /**
     * Creates the percentage update message.
     */
    private static String buildPercentageMessage(
        Decimal percentage
    ) {
        if (percentage == null) {
            return 'The payment percentage was removed.';
        }

        return 'The payment percentage is now ' +
            String.valueOf(percentage) +
            '%.';
    }

    /**
     * Creates the due-date update message.
     */
    private static String buildDueDateMessage(
        Date dueDate
    ) {
        if (dueDate == null) {
            return 'The payment due date was removed.';
        }

        return 'The payment due date is now ' +
            formatDate(dueDate) +
            '.';
    }

    /**
     * Creates the payment-term label update message.
     */
    private static String buildTermLabelMessage(
        String termLabel
    ) {
        if (String.isBlank(termLabel)) {
            return 'The payment-term label was removed.';
        }

        return 'The payment-term label is now ' +
            termLabel +
            '.';
    }

    /**
     * Returns the payment-term label or name.
     */
    private static String getTermDisplayName(
        Payment_Term__c paymentTerm
    ) {
        if (!String.isBlank(paymentTerm.Term_Label__c)) {
            return paymentTerm.Term_Label__c;
        }

        if (!String.isBlank(paymentTerm.Name)) {
            return paymentTerm.Name;
        }

        return 'Payment term';
    }

    /**
     * Formats a Date as DD-MM-YYYY.
     */
    private static String formatDate(Date value) {
        String dayValue = String.valueOf(value.day());

        if (value.day() < 10) {
            dayValue = '0' + dayValue;
        }

        String monthValue = String.valueOf(value.month());

        if (value.month() < 10) {
            monthValue = '0' + monthValue;
        }

        return dayValue +
            '-' +
            monthValue +
            '-' +
            String.valueOf(value.year());
    }

    /**
     * Stores the notification title and message.
     */
    private class NotificationContent {
        private String title;
        private String messageBody;

        private NotificationContent(
            String notificationTitle,
            String notificationMessage
        ) {
            title = notificationTitle;
            messageBody = notificationMessage;
        }
    }
}