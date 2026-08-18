/**
 * @name        LeadAssignmentEmailHandler
 * @description Sends Supervisor and Client notification emails when a
 *              Supervisor is first assigned or changed on an Arelia Lead.
 *
 *              First assignment:
 *              - Existing Supervisor assignment email
 *              - Existing Client assignment email
 *
 *              Supervisor change:
 *              - Client Supervisor-changed email
 *              - Newly appointed Supervisor email
 *
 * @version     2.1
 */
public without sharing class LeadAssignmentEmailHandler {

    private static final String INITIAL_SUPERVISOR_TEMPLATE =
        Label.Arelia_Living_Supervisor_Email_Template;

    private static final String INITIAL_CLIENT_TEMPLATE =
        Label.Arelia_Client_Supervisor_Assigned_Email;

    private static final String CLIENT_SUPERVISOR_CHANGED_TEMPLATE =
        Label.Arelia_Client_Supervisor_Changed;

    private static final String NEW_SUPERVISOR_EXISTING_LEAD_TEMPLATE =
        Label.Arelia_New_Supervisor_Assigned_Existing_Lead;

    /**
     * @description Stores templates and sender information used while
     *              preparing Supervisor assignment notifications.
     */
    private class NotificationContext {
        private EmailTemplate initialSupervisorTemplate;
        private EmailTemplate initialClientTemplate;
        private EmailTemplate changedClientTemplate;
        private EmailTemplate changedSupervisorTemplate;
        private Id orgWideEmailAddressId;
    }

    /**
     * @description Handles first Supervisor assignment and Supervisor
     *              replacement notification emails.
     * @param newList Updated Lead records.
     * @param oldMap Previous Lead records keyed by Lead Id.
     */
    public static void handleSupervisorAssignment(
        List<Lead> newList,
        Map<Id, Lead> oldMap
    ) {
        if (isInvalidInput(newList, oldMap)) {
            return;
        }

        NotificationContext notificationContext =
            buildNotificationContext();

        List<Messaging.SingleEmailMessage> emailsToSend =
            buildAssignmentEmails(
                newList,
                oldMap,
                notificationContext
            );

        sendEmails(emailsToSend);
    }

    /**
     * @description Determines whether the handler input is invalid.
     * @param newList Updated Lead records.
     * @param oldMap Previous Lead records keyed by Lead Id.
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
     * @description Loads all required templates and the Org-Wide Email
     *              Address.
     * @return Shared notification context.
     */
    private static NotificationContext buildNotificationContext() {
        NotificationContext notificationContext =
            new NotificationContext();

        notificationContext.initialSupervisorTemplate =
            getEmailTemplateByDeveloperName(
                INITIAL_SUPERVISOR_TEMPLATE,
                'Initial Supervisor assignment'
            );

        notificationContext.initialClientTemplate =
            getEmailTemplateByDeveloperName(
                INITIAL_CLIENT_TEMPLATE,
                'Initial Client assignment'
            );

        notificationContext.changedClientTemplate =
            getEmailTemplateByDeveloperName(
                CLIENT_SUPERVISOR_CHANGED_TEMPLATE,
                'Client Supervisor changed'
            );

        notificationContext.changedSupervisorTemplate =
            getEmailTemplateByDeveloperName(
                NEW_SUPERVISOR_EXISTING_LEAD_TEMPLATE,
                'New Supervisor assigned to existing Lead'
            );

        notificationContext.orgWideEmailAddressId =
            getDefaultOrgWideEmailAddressId();

        return notificationContext;
    }

    /**
     * @description Builds notification messages for all eligible Leads.
     * @param newList Updated Lead records.
     * @param oldMap Previous Lead records keyed by Lead Id.
     * @param notificationContext Templates and sender information.
     * @return Prepared email messages.
     */
    private static List<Messaging.SingleEmailMessage>
        buildAssignmentEmails(
            List<Lead> newList,
            Map<Id, Lead> oldMap,
            NotificationContext notificationContext
        )
    {
        List<Messaging.SingleEmailMessage> emailsToSend =
            new List<Messaging.SingleEmailMessage>();

        for (Lead newLead : newList) {
            Lead oldLead = oldMap.get(newLead.Id);

            emailsToSend.addAll(
                buildEmailsForLead(
                    newLead,
                    oldLead,
                    notificationContext
                )
            );
        }

        return emailsToSend;
    }

    /**
     * @description Builds first-assignment or replacement emails for one
     *              eligible Lead.
     * @param newLead Updated Lead.
     * @param oldLead Previous Lead.
     * @param notificationContext Templates and sender information.
     * @return Prepared emails for the Lead.
     */
    private static List<Messaging.SingleEmailMessage>
        buildEmailsForLead(
            Lead newLead,
            Lead oldLead,
            NotificationContext notificationContext
        )
    {
        List<Messaging.SingleEmailMessage> leadEmails =
            new List<Messaging.SingleEmailMessage>();

        if (!isEligibleAreliaLead(newLead)) {
            return leadEmails;
        }

        if (isSupervisorNewlyAssigned(oldLead, newLead)) {
            addInitialAssignmentEmails(
                leadEmails,
                newLead,
                notificationContext
            );

            return leadEmails;
        }

        if (isSupervisorChanged(oldLead, newLead)) {
            addSupervisorChangedEmails(
                leadEmails,
                newLead,
                notificationContext
            );

            return leadEmails;
        }

        System.debug(
            LoggingLevel.DEBUG,
            'No Supervisor notification required for Lead: ' +
            newLead.Id
        );

        return leadEmails;
    }

    /**
     * @description Determines whether the updated Lead can be processed.
     * @param newLead Updated Lead.
     * @return True when the Lead exists and is an Arelia Lead.
     */
    private static Boolean isEligibleAreliaLead(Lead newLead) {
        return newLead != null &&
            LeadEmailHandler.isAreliaLead(newLead);
    }

    /**
     * @description Adds the original two emails for first Supervisor
     *              assignment.
     * @param leadEmails Email collection for the current Lead.
     * @param newLead Updated Lead.
     * @param notificationContext Templates and sender information.
     */
    private static void addInitialAssignmentEmails(
        List<Messaging.SingleEmailMessage> leadEmails,
        Lead newLead,
        NotificationContext notificationContext
    ) {
        addEmailIfPresent(
            leadEmails,
            buildSupervisorEmail(
                notificationContext.initialSupervisorTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );

        addEmailIfPresent(
            leadEmails,
            buildClientEmail(
                notificationContext.initialClientTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );
    }

    /**
     * @description Adds two notification emails when an existing Supervisor
     *              is replaced:
     *              1. Client Supervisor-changed email.
     *              2. Newly appointed Supervisor email.
     * @param leadEmails Email collection for the current Lead.
     * @param newLead Updated Lead containing the new Supervisor.
     * @param notificationContext Templates and sender information.
     */
    private static void addSupervisorChangedEmails(
        List<Messaging.SingleEmailMessage> leadEmails,
        Lead newLead,
        NotificationContext notificationContext
    ) {
        addEmailIfPresent(
            leadEmails,
            buildClientEmail(
                notificationContext.changedClientTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );

        addEmailIfPresent(
            leadEmails,
            buildSupervisorEmail(
                notificationContext.changedSupervisorTemplate,
                newLead,
                notificationContext.orgWideEmailAddressId
            )
        );
    }

    /**
     * @description Adds a prepared email when it is not null.
     * @param emailMessages Email collection.
     * @param emailMessage Prepared email.
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
     * @description Fetches an email template using its DeveloperName.
     * @param developerName Email Template DeveloperName.
     * @param templateDescription Description used in logs.
     * @return Matching EmailTemplate or null.
     */
    private static EmailTemplate getEmailTemplateByDeveloperName(
        String developerName,
        String templateDescription
    ) {
        if (String.isBlank(developerName)) {
            System.debug(
                LoggingLevel.ERROR,
                templateDescription +
                ' template DeveloperName is blank.'
            );

            return null;
        }

        if (!Schema.sObjectType.EmailTemplate.isAccessible()) {
            System.debug(
                LoggingLevel.ERROR,
                'Current user does not have read access to EmailTemplate.'
            );

            return null;
        }

        try {
            List<EmailTemplate> emailTemplates = [
                SELECT Id, DeveloperName
                FROM EmailTemplate
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];

            if (emailTemplates.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    templateDescription +
                    ' Email Template was not found. DeveloperName: ' +
                    developerName
                );

                return null;
            }

            System.debug(
                LoggingLevel.DEBUG,
                'Fetched ' +
                templateDescription +
                ' Email Template: ' +
                emailTemplates[0].Id
            );

            return emailTemplates[0];

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
     * @description Determines whether a Supervisor was assigned for the first
     *              time.
     * @param oldLead Previous Lead.
     * @param newLead Updated Lead.
     * @return True for null-to-populated Supervisor assignment.
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
     * @description Determines whether an existing Supervisor was replaced
     *              with a different populated Supervisor.
     * @param oldLead Previous Lead.
     * @param newLead Updated Lead.
     * @return True for Supervisor A to Supervisor B.
     */
    private static Boolean isSupervisorChanged(
        Lead oldLead,
        Lead newLead
    ) {
        return oldLead != null &&
            oldLead.Supervisor_User__c != null &&
            newLead != null &&
            newLead.Supervisor_User__c != null &&
            oldLead.Supervisor_User__c !=
                newLead.Supervisor_User__c;
    }

    /**
     * @description Builds an email for the currently assigned Supervisor.
     *              The Lead is used as the template merge context, while
     *              Supervisor_User_Email__c is the actual recipient.
     * @param emailTemplate Supervisor email template.
     * @param newLead Lead used as merge-field context.
     * @param orgWideEmailAddressId Sender Org-Wide Email Address Id.
     * @return Prepared Supervisor email or null.
     */
    private static Messaging.SingleEmailMessage buildSupervisorEmail(
        EmailTemplate emailTemplate,
        Lead newLead,
        Id orgWideEmailAddressId
    ) {
        if (emailTemplate == null || newLead == null) {
            System.debug(
                LoggingLevel.WARN,
                'Supervisor email was not prepared because the ' +
                'template or Lead is unavailable.'
            );

            return null;
        }

        if (String.isBlank(newLead.Supervisor_User_Email__c)) {
            System.debug(
                LoggingLevel.WARN,
                'Supervisor email was not prepared because the newly ' +
                'assigned Supervisor email is blank. Lead: ' +
                newLead.Id
            );

            return null;
        }

        try {
            Messaging.SingleEmailMessage supervisorMail =
                new Messaging.SingleEmailMessage();

            supervisorMail.setTemplateId(emailTemplate.Id);

            /*
             * The Lead provides the merge-field context.
             * The Lead is not an actual recipient of this message.
             */
            supervisorMail.setTargetObjectId(newLead.Id);

            supervisorMail.setTreatTargetObjectAsRecipient(false);

            /*
             * The currently populated Supervisor email belongs to the
             * newly appointed Supervisor after a Supervisor change.
             */
            supervisorMail.setToAddresses(
                new List<String>{
                    newLead.Supervisor_User_Email__c
                }
            );

            supervisorMail.setSaveAsActivity(false);

            setOrgWideEmailAddress(
                supervisorMail,
                orgWideEmailAddressId
            );

            System.debug(
                LoggingLevel.DEBUG,
                'Supervisor email prepared using template: ' +
                emailTemplate.DeveloperName +
                '. Lead: ' +
                newLead.Id +
                ', Supervisor: ' +
                newLead.Supervisor_User__c +
                ', Supervisor Email: ' +
                newLead.Supervisor_User_Email__c
            );

            return supervisorMail;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error preparing Supervisor email. Lead: ' +
                newLead.Id +
                '. Template: ' +
                emailTemplate.DeveloperName +
                '. Error: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }

    /**
     * @description Builds a template email sent directly to the Client Lead.
     * @param emailTemplate Client email template.
     * @param newLead Client Lead receiving the email.
     * @param orgWideEmailAddressId Sender Org-Wide Email Address Id.
     * @return Prepared Client email or null.
     */
    private static Messaging.SingleEmailMessage buildClientEmail(
        EmailTemplate emailTemplate,
        Lead newLead,
        Id orgWideEmailAddressId
    ) {
        if (emailTemplate == null || newLead == null) {
            System.debug(
                LoggingLevel.WARN,
                'Client email was not prepared because the template ' +
                'or Lead is unavailable.'
            );

            return null;
        }

        if (String.isBlank(newLead.Email)) {
            System.debug(
                LoggingLevel.WARN,
                'Client email was not prepared because the Client email ' +
                'is blank. Lead: ' +
                newLead.Id
            );

            return null;
        }

        try {
            Messaging.SingleEmailMessage clientMail =
                new Messaging.SingleEmailMessage();

            clientMail.setTemplateId(emailTemplate.Id);

            /*
             * The Lead provides the merge-field context and is also the
             * actual recipient of the Client notification.
             */
            clientMail.setTargetObjectId(newLead.Id);

            clientMail.setTreatTargetObjectAsRecipient(true);

            clientMail.setSaveAsActivity(false);

            setOrgWideEmailAddress(
                clientMail,
                orgWideEmailAddressId
            );

            System.debug(
                LoggingLevel.DEBUG,
                'Client email prepared using template: ' +
                emailTemplate.DeveloperName +
                '. Lead: ' +
                newLead.Id +
                ', Client Email: ' +
                newLead.Email
            );

            return clientMail;

        } catch (Exception exceptionRecord) {
            System.debug(
                LoggingLevel.ERROR,
                'Error preparing Client email. Lead: ' +
                newLead.Id +
                '. Template: ' +
                emailTemplate.DeveloperName +
                '. Error: ' +
                exceptionRecord.getMessage()
            );

            return null;
        }
    }

    /**
     * @description Sets the Org-Wide Email Address when one is available.
     * @param emailMessage Email being prepared.
     * @param orgWideEmailAddressId Org-Wide Email Address Id.
     */
    private static void setOrgWideEmailAddress(
        Messaging.SingleEmailMessage emailMessage,
        Id orgWideEmailAddressId
    ) {
        if (
            emailMessage != null &&
            orgWideEmailAddressId != null
        ) {
            emailMessage.setOrgWideEmailAddressId(
                orgWideEmailAddressId
            );
        }
    }

    /**
     * @description Sends all prepared email messages and validates each result.
     * @param emailsToSend Emails to send.
     */
    private static void sendEmails(
        List<Messaging.SingleEmailMessage> emailsToSend
    ) {
        if (emailsToSend == null || emailsToSend.isEmpty()) {
            System.debug(
                LoggingLevel.DEBUG,
                'No Supervisor assignment emails to send.'
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
                'Unexpected error sending Supervisor assignment emails: ' +
                sendException.getMessage()
            );

            throw new AuraHandledException(
                'Unexpected error sending email: ' +
                sendException.getMessage()
            );
        }
    }

    /**
     * @description Validates all results returned by Messaging.sendEmail.
     * @param results Email sending results.
     */
    private static void validateEmailResults(
        Messaging.SendEmailResult[] results
    ) {
        if (results == null) {
            return;
        }

        for (Messaging.SendEmailResult emailResult : results) {
            validateEmailResult(emailResult);
        }
    }

    /**
     * @description Validates one email sending result.
     * @param emailResult Email sending result.
     */
    private static void validateEmailResult(
        Messaging.SendEmailResult emailResult
    ) {
        if (
            emailResult != null &&
            emailResult.isSuccess()
        ) {
            System.debug(
                LoggingLevel.DEBUG,
                'Supervisor assignment email sent successfully.'
            );

            return;
        }

        if (emailResult == null) {
            throw new AuraHandledException(
                'Salesforce returned an empty email result.'
            );
        }

        Messaging.SendEmailError[] emailErrors =
            emailResult.getErrors();

        logEmailErrors(emailErrors);

        throw new AuraHandledException(
            'Email failed: ' +
            getFirstEmailErrorMessage(emailErrors)
        );
    }

    /**
     * @description Logs Salesforce email sending errors.
     * @param emailErrors Email errors returned by Salesforce.
     */
    private static void logEmailErrors(
        Messaging.SendEmailError[] emailErrors
    ) {
        if (emailErrors == null) {
            return;
        }

        for (Messaging.SendEmailError emailError : emailErrors) {
            System.debug(
                LoggingLevel.ERROR,
                'EMAIL ERROR: ' +
                emailError.getMessage()
            );
        }
    }

    /**
     * @description Returns the first email error message.
     * @param emailErrors Email errors returned by Salesforce.
     * @return First error message or a default message.
     */
    private static String getFirstEmailErrorMessage(
        Messaging.SendEmailError[] emailErrors
    ) {
        if (
            emailErrors == null ||
            emailErrors.isEmpty()
        ) {
            return 'Unknown Salesforce email error.';
        }

        return emailErrors[0].getMessage();
    }

    /**
     * @description Gets the configured Org-Wide Email Address.
     * @return Org-Wide Email Address Id or null.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        if (String.isBlank(Label.Arelia_OWD)) {
            System.debug(
                LoggingLevel.WARN,
                'Arelia_OWD custom label is blank.'
            );

            return null;
        }

        /*
         * Required by PMD ApexCRUDViolation:
         * Validate read access before performing the SOQL query.
         */
        if (
            !Schema.sObjectType.OrgWideEmailAddress
                .isAccessible()
        ) {
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

            if (orgWideAddresses.isEmpty()) {
                System.debug(
                    LoggingLevel.WARN,
                    'Org-Wide Email Address was not found: ' +
                    Label.Arelia_OWD
                );

                return null;
            }

            return orgWideAddresses[0].Id;

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