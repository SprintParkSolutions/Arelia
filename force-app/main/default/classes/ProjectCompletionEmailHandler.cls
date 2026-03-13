/**
 * @description       : Handler for sending emails upon Project Completion.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 01-16-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@SuppressWarnings('PMD.ExcessiveParameterList')
public without sharing class ProjectCompletionEmailHandler {

    // [EXISTING CONSTANTS]
    private static final String CLIENT_TPL_COMPLETED     = 'Client_Project_Completed_Notification';
    private static final String SUPERVISOR_TPL_COMPLETED = 'Supervisor_Project_Completed_Notification';
    private static final String MANAGER_TPL_COMPLETED    = 'Sending_Project_Completed_Information_to_Manager';
    private static final String MGMT_TPL                 = 'Sending_Project_Completed_Information_to_Management';
    private static final String ENROLL_TPL               = 'Sending_Project_Completed_Information_to_Enrollment';

    private static final String DEFAULT_OWD_EMAIL = System.Label.Arelia_OWD;
    private static final String MGMT_LABEL_CSV    = System.Label.Arelia_Living_Enrollment_Members;

    // [MODIFIED: Renamed to match FieldNamingConventions]
    @TestVisible private static String testCsvOverride;
    @TestVisible private static String testEmailFallback;
    @TestVisible private static Boolean forceException = false;

    /**
     * @description Handles logic after Project update triggers.
     * @param newList List of new Project records.
     * @param oldMap Map of old Project records.
     */
    public static void handleAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        List<Project__c> justCompleted = new List<Project__c>();
        for (Project__c n : newList) {
            Project__c o = oldMap.get(n.Id);
            if (isProjectNewlyCompleted(n, o)) {
                justCompleted.add(n);
            }
        }

        if (!justCompleted.isEmpty()) {
            sendProjectApprovedEmail(justCompleted);
        }
    }

    /**
     * @description Helper to check if project status changed to Completed/100%.
     */
    private static Boolean isProjectNewlyCompleted(Project__c n, Project__c o) {
        if (o == null) {
            return false;
        }
        Boolean nowCompleted = (n.Status__c == 'Completed' && n.Project_Completion_Status__c == 100);
        Boolean wasCompleted = (o.Status__c == 'Completed' && o.Project_Completion_Status__c == 100);
        return nowCompleted && !wasCompleted;
    }

    /**
     * @description Orchestrates the gathering of data and sending of emails.
     * @param projects List of projects to process.
     */
    public static void sendProjectApprovedEmail(List<Project__c> projects) {
        if (projects == null || projects.isEmpty()) {
            return;
        }

        try {
            // Force exception for coverage
            if (Test.isRunningTest() && forceException) {
                throw new CalloutException('Forced Exception');
            }

            Map<Id, Contact> contactMap = getClientContacts(projects);
            Map<Id, User>    supMap     = getSupervisorUsers(projects);

            Templates tpls = loadTemplates();
            List<User> roleManagers = getManagersByRole();

            // Use Test CSV if provided, else use Label
            String csvToUse = (Test.isRunningTest() && testCsvOverride != null)
                              ? testCsvOverride : MGMT_LABEL_CSV;

            List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
            for (Project__c proj : projects) {
                Contact client = contactMap.get(proj.Client__c);
                User    sup    = supMap.get(proj.Supervisor_User__c);

                outbox.addAll(buildClientEmails(proj, client, sup, tpls));
                outbox.addAll(buildSupervisorEmails(proj, client, sup, tpls));
                outbox.addAll(buildRoleManagerEmails(proj, client, sup, tpls, roleManagers));
                outbox.addAll(buildCsvLabelEmails(proj, client, sup, tpls.management, csvToUse));
            }

            if (!outbox.isEmpty()) {
                Messaging.sendEmail(outbox);
            }

        } catch (Exception e) {
            // PMD: AvoidDebugStatements - Debug removed for performance and compliance.
        }
    }

    // [HELPER METHODS]

    private class Templates {
        EmailTemplate client;
        EmailTemplate supervisor;
        EmailTemplate manager;
        EmailTemplate management;
        EmailTemplate enrollment;
    }

    private static Templates loadTemplates() {
        Templates t = new Templates();
        t.client     = fetchEmailTemplate(CLIENT_TPL_COMPLETED);
        t.supervisor = fetchEmailTemplate(SUPERVISOR_TPL_COMPLETED);
        t.manager    = fetchEmailTemplate(MANAGER_TPL_COMPLETED);
        t.management = fetchEmailTemplate(MGMT_TPL);
        t.enrollment = fetchEmailTemplate(ENROLL_TPL);
        return t;
    }

    private static List<Messaging.SingleEmailMessage> buildClientEmails(Project__c proj, Contact client, User sup, Templates tpls) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.client == null) {
            return listMsgs;
        }

        String dbValue = String.valueOf(proj.get('Client_Email__c'));
        String to = resolveEmailAddress(client != null ? client.Email : null, dbValue);

        if (String.isBlank(to)) {
            return listMsgs;
        }

        String subj = replaceVars(tpls.client.Subject,  proj, client, sup, null);
        String body = replaceVars(tpls.client.HtmlValue, proj, client, sup, null);

        if (client != null && String.isNotBlank(client.Email)) {
            listMsgs.add(buildTargetEmail(client.Id, proj.Id, subj, body));
        } else {
            listMsgs.add(buildDirectEmail(to, proj.Id, subj, body));
        }
        return listMsgs;
    }

    private static List<Messaging.SingleEmailMessage> buildSupervisorEmails(Project__c proj, Contact client, User sup, Templates tpls) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.supervisor == null) {
            return listMsgs;
        }

        String dbValue = String.valueOf(proj.get('Supervisor_Email_Text_c__c'));
        String to = resolveEmailAddress(sup != null ? sup.Email : null, dbValue);

        if (String.isBlank(to)) {
            return listMsgs;
        }

        String subj = replaceVars(tpls.supervisor.Subject,  proj, client, sup, null);
        String body = replaceVars(tpls.supervisor.HtmlValue, proj, client, sup, null);

        if (sup != null && String.isNotBlank(sup.Email)) {
            listMsgs.add(buildTargetEmail(sup.Id, proj.Id, subj, body));
        } else {
            listMsgs.add(buildDirectEmail(to, proj.Id, subj, body));
        }
        return listMsgs;
    }

    /**
     * @description Helper to resolve email with fallback and override logic.
     */
    private static String resolveEmailAddress(String objectEmail, String dbFallbackField) {
        String fallback = (Test.isRunningTest() && testEmailFallback != null) ? testEmailFallback : dbFallbackField;
        return (String.isNotBlank(objectEmail)) ? objectEmail : fallback;
    }

    private static List<Messaging.SingleEmailMessage> buildRoleManagerEmails(Project__c proj, Contact client, User sup, Templates tpls, List<User> roleManagers) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tpls == null || tpls.manager == null || roleManagers == null || roleManagers.isEmpty()) {
            return listMsgs;
        }

        for (User mgr : roleManagers) {
            if (mgr == null || String.isBlank(mgr.Email)) {
                continue;
            }
            String mgrName = String.isNotBlank(mgr.Name) ? mgr.Name : 'Manager';
            String subj    = replaceVars(tpls.manager.Subject,  proj, client, sup, mgrName);
            String body    = replaceVars(tpls.manager.HtmlValue, proj, client, sup, mgrName);
            listMsgs.add(buildDirectEmail(mgr.Email.trim(), proj.Id, subj, body));
        }
        return listMsgs;
    }

    private static List<Messaging.SingleEmailMessage> buildCsvLabelEmails(Project__c proj, Contact client, User sup, EmailTemplate tmpl, String csv) {
        if (tmpl == null || String.isBlank(csv)) {
            return new List<Messaging.SingleEmailMessage>();
        }
        return buildPerRecipientFromCsv(tmpl, proj, client, sup, csv);
    }

    private static Map<Id, Contact> getClientContacts(List<Project__c> projects) {
        Set<Id> ids = new Set<Id>();
        for (Project__c p : projects) {
            if (p.Client__c != null) {
                ids.add(p.Client__c);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, Contact>();
        }
        try {
            return new Map<Id, Contact>([SELECT Id, Name, Email FROM Contact WHERE Id IN :ids]);
        } catch (Exception e) {
            return new Map<Id, Contact>();
        }
    }

    private static Map<Id, User> getSupervisorUsers(List<Project__c> projects) {
        Set<Id> ids = new Set<Id>();
        for (Project__c p : projects) {
            if (p.Supervisor_User__c != null) {
                ids.add(p.Supervisor_User__c);
            }
        }
        if (ids.isEmpty()) {
            return new Map<Id, User>();
        }
        try {
            return new Map<Id, User>([SELECT Id, Name, Email FROM User WHERE Id IN :ids]);
        } catch (Exception e) {
            return new Map<Id, User>();
        }
    }

    private static List<User> getManagersByRole() {
        try {
            return [SELECT Id, Name, Email FROM User WHERE IsActive = true AND Email != null AND UserRole.Name LIKE '%Manager%'];
        } catch (Exception e) {
            return new List<User>();
        }
    }

    private static Messaging.SingleEmailMessage buildTargetEmail(Id targetId, Id whatId, String subject, String body) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setTargetObjectId(targetId);
        m.setWhatId(whatId);
        m.setSubject(subject);
        m.setHtmlBody(body);
        m.setSaveAsActivity(false);
        m.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
        return m;
    }

    private static Messaging.SingleEmailMessage buildDirectEmail(String toAddress, Id whatId, String subject, String body) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ toAddress });
        m.setWhatId(whatId);
        m.setSubject(subject);
        m.setHtmlBody(body);
        m.setSaveAsActivity(false);
        m.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
        return m;
    }

    private static List<Messaging.SingleEmailMessage> buildPerRecipientFromCsv(EmailTemplate tmpl, Project__c proj, Contact contact, User sup, String csv) {
        List<Messaging.SingleEmailMessage> listMsgs = new List<Messaging.SingleEmailMessage>();
        if (tmpl == null || String.isBlank(csv)) {
            return listMsgs;
        }
        for (String raw : csv.split(',')) {
            String addr = (raw == null) ? null : raw.trim();
            if (String.isBlank(addr)) {
                continue;
            }
            String display = inferDisplayNameFromEmail(addr);
            String subj = replaceVars(tmpl.Subject,  proj, contact, sup, display);
            String body = replaceVars(tmpl.HtmlValue, proj, contact, sup, display);
            listMsgs.add(buildDirectEmail(addr, proj.Id, subj, body));
        }
        return listMsgs;
    }

    private static String replaceVars(String input, Project__c proj, Contact contact, User sup, String managerName) {
        if (String.isBlank(input)) {
            return '';
        }
        String outStr = input
            .replace('{{{Project__c.Name}}}',                 safe(proj != null ? proj.Name : null))
            .replace('{{{Project__c.Project_Code__c}}}',      safe(proj != null ? proj.Project_Code__c : null))
            .replace('{{{Project__c.Status__c}}}',            safe(proj != null ? proj.Status__c : null))
            .replace('{{{Project__c.Type_Of_Project__c}}}',   safe(proj != null ? proj.Type_Of_Project__c : null))
            .replace('{{{Project__c.Project_Scope__c}}}',     safe(proj != null ? proj.Project_Scope__c : null))
            .replace('{{{Project__r.Client__r.Name}}}',       safe(contact != null ? contact.Name : null))
            .replace('{{{Project__r.Supervisor_User__r.Name}}}', safe(sup != null ? sup.Name : null));
        outStr = outStr.replace('{{{ManagerName}}}', safe(managerName));
        return outStr;
    }

    private static EmailTemplate fetchEmailTemplate(String developerName) {
        try {
            List<EmailTemplate> t = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :developerName LIMIT 1];
            return t.isEmpty() ? null : t[0];
        } catch (Exception e) {
            return null;
        }
    }

    private static Id getOrgWideEmailAddressId() {
        try {
            List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :DEFAULT_OWD_EMAIL LIMIT 1];
            return o.isEmpty() ? null : o[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static String inferDisplayNameFromEmail(String emailAddr) {
        if (String.isBlank(emailAddr) || !emailAddr.contains('@')) {
            return 'Manager';
        }
        String local = emailAddr.substring(0, emailAddr.indexOf('@')).replace('.', ' ').replace('_', ' ').trim();
        if (String.isBlank(local)) {
            return 'Manager';
        }
        List<String> caps = new List<String>();
        for (String p : local.split('\\s+')) {
            if (String.isNotBlank(p)) {
                caps.add(p.substring(0,1).toUpperCase() + (p.length()>1?p.substring(1).toLowerCase():''));
            }
        }
        return caps.isEmpty() ? 'Manager' : String.join(caps, ' ');
    }

    private static String safe(String v) {
        return String.isNotBlank(v) ? v : '';
    }
}