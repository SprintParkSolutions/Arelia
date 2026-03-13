/**
 * Class: ProjectUpdateHandler
 * Responsibility:
 *  - On Project__c AFTER UPDATE, detect records whose Project_Completion_Status__c changed
 *    and send status update emails (client + supervisor) using Lightning Email Templates.
 *
 * PMD / Style:
 *  - Tiny trigger; all logic here.
 *  - Guard clauses minimize nesting.
 *  - OneDeclarationPerLine everywhere.
 *  - Curly braces on all if/for blocks.
 *  - Small helpers to keep Cognitive Complexity / NCSS low.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation')
public without sharing class ProjectUpdateHandler {

    // ----------------------------------------------------------------------
    // Configuration constants (no labels as requested)
    // ----------------------------------------------------------------------
    private static final String CLIENT_TPL_DEVNAME = Label.Arelia_Living_Project_Status_Update_Lead_Template;
    private static final String SUPERVISOR_TPL_DEVNAME = Label.Arelia_Living_Project_Status_Update_Supervisor_Template;

    /**
     * Entry point from the trigger (AFTER UPDATE).
     */
    public static void afterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        if (newList == null) { return; }
        if (newList.isEmpty()) { return; }
        if (oldMap == null) { return; }
        if (oldMap.isEmpty()) { return; }

        List<Project__c> changed = pickWithStatusChange(newList, oldMap);
        if (changed.isEmpty()) { return; }

        sendProjectStatusUpdateEmails(changed);
    }

    /**
     * Filters only the projects whose Project_Completion_Status__c changed.
     */
    private static List<Project__c> pickWithStatusChange(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        List<Project__c> result = new List<Project__c>();

        for (Project__c pNew : newList) {
            Project__c pOld = oldMap.get(pNew.Id);
            if (pOld == null) { continue; }
            Boolean statusChanged = pNew.Project_Completion_Status__c != pOld.Project_Completion_Status__c;
            if (statusChanged) { result.add(pNew); }
        }
        return result;
    }

    /**
     * Orchestrates email sending to client and supervisor using Lightning Email Templates.
     */
    public static void sendProjectStatusUpdateEmails(List<Project__c> updatedProjects) {
        if (updatedProjects == null) { return; }
        if (updatedProjects.isEmpty()) { return; }

        Id clientTemplateId = getTemplateIdByDeveloperName(CLIENT_TPL_DEVNAME);
        Id supervisorTemplateId = getTemplateIdByDeveloperName(SUPERVISOR_TPL_DEVNAME);

        if (clientTemplateId == null) {
            System.debug(LoggingLevel.ERROR, 'ProjectUpdateHandler: Client template not found: ' + CLIENT_TPL_DEVNAME);
            return;
        }
        if (supervisorTemplateId == null) {
            System.debug(LoggingLevel.ERROR, 'ProjectUpdateHandler: Supervisor template not found: ' + SUPERVISOR_TPL_DEVNAME);
            return;
        }

        Contact dummyContact = getSharedDummyContact();
        if (dummyContact == null) {
            System.debug(LoggingLevel.ERROR, 'ProjectUpdateHandler: Dummy Contact not found.');
            return;
        }

        Id oweaId = getDefaultOrgWideEmailAddressId(); // may be null
        List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();

        for (Project__c proj : updatedProjects) {
            if (proj == null) { continue; }

            if (String.isNotBlank(proj.Client_Email__c)) {
                List<String> clientTos = cleanedEmails(new List<String>{ proj.Client_Email__c });
                if (!clientTos.isEmpty()) {
                    Messaging.SingleEmailMessage toClient = buildTemplatedEmail(
                        dummyContact.Id,clientTos,clientTemplateId,proj.Id,oweaId);
                    batch.add(toClient);
                }
            }

            if (String.isNotBlank(proj.Supervisor_Email_Text_c__c)) {
                List<String> supTos = cleanedEmails(new List<String>{ proj.Supervisor_Email_Text_c__c });
                if (!supTos.isEmpty()) {
                    Messaging.SingleEmailMessage toSupervisor = buildTemplatedEmail(
                        dummyContact.Id, supTos, supervisorTemplateId, proj.Id, oweaId);
                    batch.add(toSupervisor);
                }
            }
        }
        sendEmails(batch);
    }

    /**
     * Deduplicates and trims emails; drops blanks.
     */
    private static List<String> cleanedEmails(List<String> raw) {
        Set<String> uniq = new Set<String>();
        if (raw != null) {
            for (String s : raw) {
                if (String.isBlank(s)) { continue; }
                uniq.add(s.trim());
            }
        }
        List<String> out = new List<String>();
        out.addAll(uniq);
        return out;
    }

    /**
     * Builds a SingleEmailMessage for a Lightning Email Template.
     */
    private static Messaging.SingleEmailMessage buildTemplatedEmail(
        Id targetContactId, List<String> toAddresses, Id templateId, Id whatId, Id oweaId)
    {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setTargetObjectId(targetContactId);
        msg.setToAddresses(toAddresses);
        msg.setTemplateId(templateId);
        msg.setWhatId(whatId);
        msg.setTreatTargetObjectAsRecipient(false);
        msg.setSaveAsActivity(true);
        if (oweaId != null) {
            msg.setOrgWideEmailAddressId(oweaId);
        }
        return msg;
    }

    /**
     * Sends a prepared batch of emails with logging.
     * Enforces OneDeclarationPerLine in the loop.
     */
    private static void sendEmails(List<Messaging.SingleEmailMessage> emailsToSend) {
        if (emailsToSend == null) {
            System.debug(LoggingLevel.WARN, 'ProjectUpdateHandler: emailsToSend is null.');
            return;
        }
        if (emailsToSend.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'ProjectUpdateHandler: No emails prepared to send.');
            return;
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);

        Integer total = results.size();
        for (Integer i = 0; i < total; i++) {
            Messaging.SendEmailResult result = results[i];
            List<String> toAddresses = emailsToSend[i].getToAddresses();

            if (result != null && result.isSuccess()) {
                System.debug(LoggingLevel.INFO,
                    'ProjectUpdateHandler: Email sent. ProjectWhatId=' + String.valueOf(emailsToSend[i].getWhatId()) +
                    ', To=' + String.valueOf(toAddresses)
                );
            } else if (result != null) {
                System.debug(LoggingLevel.ERROR,
                    'ProjectUpdateHandler: Email failed. ProjectWhatId=' + String.valueOf(emailsToSend[i].getWhatId()) +
                    ', To=' + String.valueOf(toAddresses)
                );
                Messaging.SendEmailError[] errors = result.getErrors();
                Integer errCount = errors == null ? 0 : errors.size();
                for (Integer eIdx = 0; eIdx < errCount; eIdx++) {
                    Messaging.SendEmailError err = errors[eIdx];
                    System.debug(LoggingLevel.ERROR, '  Error: ' + err.getMessage());
                }
            } else {
                System.debug(LoggingLevel.ERROR,
                    'ProjectUpdateHandler: Null SendEmailResult. ProjectWhatId=' + String.valueOf(emailsToSend[i].getWhatId()) +
                    ', To=' + String.valueOf(toAddresses)
                );
            }
        }
    }

    /**
     * Finds the shared dummy Contact by DUMMY_CONTACT_EMAIL.
     */
    private static Contact getSharedDummyContact() {
        List<Contact> contacts = [SELECT Id FROM Contact LIMIT 1];
        if (!contacts.isEmpty()) { return contacts[0]; }
        return null;
    }

    /**
     * Resolve Email Template Id by DeveloperName.
     */
    private static Id getTemplateIdByDeveloperName(String devName) {
        if (String.isBlank(devName)) { return null;}
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
        if (!templates.isEmpty()) {
            return templates[0].Id;
        }
        return null;
    }

    /**
     * Resolve a default Org-Wide Email Address:
     *  - picks any OWEA that is allowed for all profiles (common "default"),
     *  - returns null if none found (safe to skip OWEA).
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE IsAllowAllProfiles = true ORDER BY CreatedDate ASC LIMIT 1];
        if (!oweaList.isEmpty()) {
            return oweaList[0].Id;
        }
        return null;
    }
}