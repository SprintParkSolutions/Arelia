/**
 * @name        LeadAssignmentEmailHandler
 * @description Sends notification emails to the assigned Supervisor and
 *              Client when a Supervisor is newly assigned to a Lead.
 * @version     1.1
 */
public without sharing class LeadAssignmentEmailHandler {

    private static final String CLIENT_TEMPLATE_DEVELOPER_NAME =
        Label.Arelia_Client_Supervisor_Assigned_Email;

    /**
     * @description Holds the templates and Org-Wide Email Address used while
     *              preparing assignment notification emails.
     */
    private class NotificationContext {

        private EmailTemplate supervisorTemplate;
        private EmailTemplate clientTemplate;
        private Id orgWideEmailAddressId;

        /**
         * @description Creates the notification context.
         * @param supervisorEmailTemplate Supervisor email template.
         * @param clientEmailTemplate Client email template.
         * @param senderAddressId Org-Wide Email Address Id.
         */
        private NotificationContext(
            EmailTemplate supervisorEmailTemplate,
            EmailTemplate clientEmailTemplate,
            Id senderAddressId
        ) {
            supervisorTemplate = supervisorEmailTemplate;
            clientTemplate = clientEmailTemplate;
            orgWideEmailAddressId = senderAddressId;
        }
    }

    /**
     * @description Handles Supervisor assignment notification emails.
     * @param newList List of updated Lead records.
     * @param oldMap Map of previous Lead records keyed by Id.
     */
    public static void handleSupervisorAssignment(
        List<Lead> newList,
        Map<Id, Lead> oldMap
    ) {
        if (isInvalidInput(newList, oldMap)) {
            return;
        }

        EmailTemplate supervisorTemplate = getEmailTemplate();

        if (supervisorTemplate == null) {
            return;
        }

        NotificationContext notificationContext =
            new NotificationContext(
                supervisorTemplate,
                getClientEmailTemplate(),
                getDefaultOrgWideEmailAddressId()
            );

        List<Messaging.SingleEmailMessage> emailsToSend =
            buildAssignmentEmails(
                newList,
                oldMap,
                notificationContext
            );

        sendEmails(emailsToSend);
    }

    /**
     * @description Determines whether the supplied handler inputs are invalid.
     * @param newList Updated Lead records.
     * @param oldMap Previous Lead records.
     * @return True when processing should stop.
     */
    private static Boolean isInvalidInput(
        List<Lead> newList,
        Map<Id, Lead> oldMap
    ) {
        return newList == null ||
            newList.isEmpty() ||
            oldMap == null;
    }

    /**
     * @description Builds notification emails for all eligible Leads.
     * @param newList Updated Lead records.
     * @param oldMap Previous Lead records.
     * @param notificationContext Notification templates and sender address.
     * @return Prepared Supervisor and Client email messages.
     */
    private static List<Messaging.SingleEmailMessage>
        buildAssignmentEmails(
            List<Lead> newList,
            Map<Id, Lead> oldMap,
            NotificationContext notificationContext
        ) {
        List<Messaging.SingleEmailMessage> emailsToSend =
            new List<Messaging.SingleEmailMessage>();

        for (Lead newLead : newList) {
            emailsToSend.addAll(
                buildEmailsForLead(
                    newLead,
                    oldMap.get(newLead.Id),
                    notificationContext
                )
            );
        }

        return emailsToSend;
    }

    /**
     * @description Builds Supervisor and Client emails for one eligible Lead.
     * @param newLead Updated Lead.
     * @param oldLead Previous Lead.
     * @param notificationContext Notification templates and sender address.
     * @return Prepared emails for the Lead.
     */
    private static List<Messaging.SingleEmailMessage>
        buildEmailsForLead(
            Lead newLead,
            Lead oldLead,
            NotificationContext notificationContext
        ) {
        List<Messaging.SingleEmailMessage> leadEmails =
            new List<Messaging.SingleEmailMessage>();

        if (!LeadEmailHandler.isAreliaLead(newLead)) {
            return leadEmails;
        }

        if (!isSupervisorNewlyAssigned(oldLead, newLead)) {
            System.debug(
                LoggingLevel.DEBUG,
                'No supervisor assignment change for Lead: ' +
                newLead.Id
            );

            return leadEmails;
        }

        addEmailIfPresent(
            leadEmails,
            buildEmail(
                notificationContext.supervisorTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );

        addEmailIfPresent(
            leadEmails,
            buildClientEmail(
                notificationContext.clientTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );

        return leadEmails;
    }

    /**
     * @description Adds a prepared email to the collection when it is present.
     * @param emailMessages Email collection.
     * @param emailMessage Prepared email message.
     */
    private static void addEmailIfPresent(
        List<Messaging.SingleEmailMessage> emailMessages,
        Messaging.SingleEmailMessage emailMessage
    ) {
        if (emailMessage != null) {
            emailMessages.add(emailMessage);
        }
    }

    /**
     * @description Fetches the Lightning Email Template used for notifying
     *              Supervisors.
     * @return Supervisor EmailTemplate or null.
     */
    private static EmailTemplate getEmailTemplate() {
        return getEmailTemplateByDeveloperName(
            Label.Arelia_Living_Supervisor_Email_Template,
            'Supervisor'
        );
    }

    /**
     * @description Fetches the Lightning Email Template used for notifying
     *              the Client.
     * @return Client EmailTemplate or null.
     */
    private static EmailTemplate getClientEmailTemplate() {
        return getEmailTemplateByDeveloperName(
            CLIENT_TEMPLATE_DEVELOPER_NAME,
            'Client'
        );
    }

    /**
     * @description Fetches an email template using its developer name.
     * @param developerName Email Template developer name.
     * @param templateDescription Description used in logs.
     * @return Matching EmailTemplate or null.
     */
    private static EmailTemplate getEmailTemplateByDeveloperName(
        String developerName,
        String templateDescription
    ) {
        if (!Schema.sObjectType.EmailTemplate.isAccessible()) {
            System.debug(
                LoggingLevel.ERROR,
                'Current user does not have read access to EmailTemplate.'
            );

            return null;
        }

        try {
            List<EmailTemplate> templates = [
                SELECT Id
                FROM EmailTemplate
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    templateDescription +
                    ' Email Template was not found: ' +
                    developerName
                );

                return null;
            }

            System.debug(
                LoggingLevel.DEBUG,
                'Fetched ' +
                templateDescription +
                ' Email Template: ' +
                templates[0].Id
            );

            return templates[0];

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error fetching ' +
                templateDescription +
                ' Email Template: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }

    /**
     * @description Checks whether Supervisor_User__c was newly assigned.
     * @param oldLead Previous Lead.
     * @param newLead Updated Lead.
     * @return True when the Supervisor changed from null to populated.
     */
    private static Boolean isSupervisorNewlyAssigned(
        Lead oldLead,
        Lead newLead
    ) {
        return (
            oldLead == null ||
            oldLead.Supervisor_User__c == null
        ) &&
        newLead != null &&
        newLead.Supervisor_User__c != null;
    }

    /**
     * @description Builds the email sent to the assigned Supervisor.
     * @param template Supervisor email template.
     * @param newLead Lead used as merge-field context.
     * @param orgWideEmailAddressId Sender Org-Wide Email Address Id.
     * @return Prepared Supervisor email or null.
     */
    private static Messaging.SingleEmailMessage buildEmail(
        EmailTemplate template,
        Lead newLead,
        Id orgWideEmailAddressId
    ) {
        Id supervisorId = newLead.Supervisor_User__c;

        System.debug(
            LoggingLevel.DEBUG,
            'Lead ID: ' +
            newLead.Id +
            ' to Supervisor User Id: ' +
            supervisorId +
            ' Supervisor Email: ' +
            newLead.Supervisor_User_Email__c
        );

        try {
            if (String.isBlank(newLead.Supervisor_User_Email__c)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Supervisor has no email for Lead: ' +
                    newLead.Id
                );

                return null;
            }

            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();

            mail.setTemplateId(template.Id);
            mail.setTargetObjectId(newLead.Id);
            mail.setToAddresses(
                new List<String>{
                    newLead.Supervisor_User_Email__c
                }
            );
            mail.setTreatTargetObjectAsRecipient(false);
            mail.setSaveAsActivity(false);
            mail.setOrgWideEmailAddressId(
                orgWideEmailAddressId
            );

            return mail;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error preparing Supervisor email: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }

    /**
     * @description Builds the email sent to the Client when a Supervisor
     *              is assigned.
     * @param clientTemplate Client notification email template.
     * @param newLead Lead receiving the notification.
     * @param orgWideEmailAddressId Sender Org-Wide Email Address Id.
     * @return Prepared Client email or null.
     */
    private static Messaging.SingleEmailMessage buildClientEmail(
        EmailTemplate clientTemplate,
        Lead newLead,
        Id orgWideEmailAddressId
    ) {
        if (clientTemplate == null || newLead == null) {
            return null;
        }

        try {
            if (String.isBlank(newLead.Email)) {
                System.debug(
                    LoggingLevel.WARN,
                    'Client email is missing for Lead: ' +
                    newLead.Id
                );

                return null;
            }

            Messaging.SingleEmailMessage clientMail =
                new Messaging.SingleEmailMessage();

            clientMail.setTemplateId(clientTemplate.Id);
            clientMail.setTargetObjectId(newLead.Id);
            clientMail.setTreatTargetObjectAsRecipient(true);
            clientMail.setSaveAsActivity(false);
            clientMail.setOrgWideEmailAddressId(
                orgWideEmailAddressId
            );

            System.debug(
                LoggingLevel.DEBUG,
                'Client notification email prepared for Lead: ' +
                newLead.Id +
                ', Client Email: ' +
                newLead.Email
            );

            return clientMail;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error preparing Client email: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }

    /**
     * @description Sends all prepared email messages.
     * @param emailsToSend Emails to send.
     */
    private static void sendEmails(
        List<Messaging.SingleEmailMessage> emailsToSend
    ) {
        if (emailsToSend.isEmpty()) {
            System.debug(
                LoggingLevel.DEBUG,
                'No emails to send.'
            );

            return;
        }

        try {
            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(
                    emailsToSend,
                    false
                );

            validateEmailResults(results);

        } catch (Exception sendException) {
            System.debug(
                LoggingLevel.ERROR,
                'Unexpected error sending email: ' +
                sendException.getMessage()
            );

            throw new AuraHandledException(
                'Unexpected error sending email: ' +
                sendException.getMessage()
            );
        }
    }

    /**
     * @description Validates the results returned by Messaging.sendEmail.
     * @param results Email sending results.
     */
    private static void validateEmailResults(
        Messaging.SendEmailResult[] results
    ) {
        for (Messaging.SendEmailResult result : results) {
            validateEmailResult(result);
        }
    }

    /**
     * @description Validates one email sending result.
     * @param result Email sending result.
     */
    private static void validateEmailResult(
        Messaging.SendEmailResult result
    ) {
        if (result.isSuccess()) {
            System.debug(
                LoggingLevel.DEBUG,
                'Email sent successfully.'
            );

            return;
        }

        logEmailErrors(result.getErrors());

        throw new AuraHandledException(
            'Email failed: ' +
            result.getErrors()[0].getMessage()
        );
    }

    /**
     * @description Logs email sending errors.
     * @param emailErrors Email errors returned by Salesforce.
     */
    private static void logEmailErrors(
        Messaging.SendEmailError[] emailErrors
    ) {
        for (Messaging.SendEmailError emailError : emailErrors) {
            System.debug(
                LoggingLevel.ERROR,
                'EMAIL ERROR: ' +
                emailError.getMessage()
            );
        }
    }

    /**
     * @description Gets the configured Org-Wide Email Address Id.
     * @return OrgWideEmailAddress Id or null.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        if (!Schema.sObjectType.OrgWideEmailAddress.isAccessible()) {
            System.debug(
                LoggingLevel.ERROR,
                'Current user does not have read access to ' +
                'OrgWideEmailAddress.'
            );

            return null;
        }

        try {
            List<OrgWideEmailAddress> orgWideAddresses = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :Label.Arelia_OWD
                LIMIT 1
            ];

            return orgWideAddresses.isEmpty()
                ? null
                : orgWideAddresses[0].Id;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error fetching Org-Wide Email Address: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }
}