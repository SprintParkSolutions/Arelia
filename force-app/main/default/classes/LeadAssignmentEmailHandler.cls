/**
 * @name        LeadAssignmentEmailHandler
 * @description Sends an email to the assigned Supervisor (custom object) when a Lead is updated.
 * Uses a Lightning Email Template and merges Lead data.
 * Optimized to reduce cognitive complexity and comply with PMD best practices.
 * @version     1.0
 */
public without sharing class LeadAssignmentEmailHandler {

    /**
     * @description Main method to handle logic after Lead update.
     * Checks if a Supervisor_User__c was newly assigned, builds the email, and sends it.
     * @param newList List of updated Lead records.
     * @param oldMap  Map of old Lead records keyed by Id.
     * @pmd.reducesCognitiveComplexity True
     */
    public static void handleSupervisorAssignment(List<Lead> newList, Map<Id, Lead> oldMap) {
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        EmailTemplate template = getEmailTemplate();

        if (template == null) {
            return;
        }

        for (Lead newLead : newList) {
            Lead oldLead = oldMap.get(newLead.Id);

            if (isSupervisorNewlyAssigned(oldLead, newLead)) {
                Messaging.SingleEmailMessage email = buildEmail(template, newLead);
                if (email != null) {
                    emailsToSend.add(email);
                }
            }
        }

        sendEmails(emailsToSend);
    }

    /**
     * @description Fetches the Lightning Email Template used for notifying Supervisors.
     * @return EmailTemplate record or null if not found or exception occurs.
     * @pmd.comment Reduces inline query complexity from handleSupervisorAssignment
     */
    private static EmailTemplate getEmailTemplate() {
        try {
            // WITH SYSTEM_MODE ensures we ignore user permissions for this setup object, resolving CRUD violations
            EmailTemplate template = [
                SELECT Id FROM EmailTemplate
                WHERE DeveloperName =: Label.Arelia_Living_Supervisor_Email_Template
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return template;
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @description Checks if Supervisor_User__c was newly assigned to the Lead.
     * @param oldLead The old version of the Lead record.
     * @param newLead The updated version of the Lead record.
     * @return true if Supervisor_User__c changed from null to non-null, else false.
     * @pmd.comment Isolates logical condition for readability and testing
     */
    private static Boolean isSupervisorNewlyAssigned(Lead oldLead, Lead newLead) {
        return oldLead.Supervisor_User__c == null && newLead.Supervisor_User__c != null;
    }

    /**
     * @description Builds a Messaging.SingleEmailMessage using the template and supervisor's email.
     * Uses Lead as the targetObjectId for template merge field context.
     * @param template EmailTemplate to be used.
     * @param newLead Lead record for merge field context.
     * @return Messaging.SingleEmailMessage object or null if supervisor email is missing or an exception occurs.
     * @pmd.comment Reduces nested logic and separates query + mail logic
     */
    private static Messaging.SingleEmailMessage buildEmail(EmailTemplate template, Lead newLead) {
        Id supervisorId = newLead.Supervisor_User__c;
        try {
            if (String.isBlank(newLead.Supervisor_User_Email__c)) {
                return null;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(template.Id);
            mail.setTargetObjectId(newLead.Id); // merge fields context
            mail.setToAddresses(new List<String>{ newLead.Supervisor_User_Email__c });
            mail.setTreatTargetObjectAsRecipient(false);
            mail.setSaveAsActivity(false);
            mail.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
            return mail;

        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @description Sends a list of SingleEmailMessages.
     * Throws AuraHandledException if any email fails.
     * @param emailsToSend List of Messaging.SingleEmailMessage to send.
     * @pmd.comment Extracted to reduce complexity of send logic
     */
    private static void sendEmails(List<Messaging.SingleEmailMessage> emailsToSend) {
        if (emailsToSend.isEmpty()) {
            return;
        }

        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
            for (Messaging.SendEmailResult res : results) {
                if (!res.isSuccess()) {
                    throw new AuraHandledException('Email failed: ' + res.getErrors()[0].getMessage());
                }
            }
        } catch (Exception sendEx) {
            throw new AuraHandledException('Unexpected error sending email: ' + sendEx.getMessage());
        }
    }

    /**
     * @description Gets the Org-Wide Email Address Id for 'nareshp@sprintpark.com'.
     * @return The OrgWideEmailAddress Id if found; otherwise, null.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        // WITH SYSTEM_MODE ensures we ignore user permissions for this setup object, resolving CRUD violations
        List<OrgWideEmailAddress> oweaList = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE Address =: Label.Arelia_OWD AND IsAllowAllProfiles = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }
}