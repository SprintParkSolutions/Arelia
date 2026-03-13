/**
 * @description
 * Handler class for operations related to Project__c object,
 * including assigning project codes and sending email notifications
 * to clients, supervisors, and internal teams (management/enrollment).
 *
 * @author
 * Arelia team
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class ProjectTriggerHandler {

    // Template and sender configuration
    private static final String CLIENT_TEMPLATE = Label.Arelia_Living_Client_Project_Notification;
    private static final String SUPERVISOR_TEMPLATE = Label.Arelia_Living_Supervisor_Project_Notification;
    private static final String MANAGER_TEMPLATE = Label.Arelia_Living_Sending_Project_Create_Information_to_Manager;
    private static final String MGMT_TEMPLATE = Label.Arelia_Living_Sending_Project_Create_Information_to_Management;
    private static final String ENROLLMENT_TEMPLATE = Label.Arelia_Living_Sending_Project_Create_Information_to_Enrollment;
    private static final String DEFAULT_OWD_EMAIL = Label.Arelia_OWD;

    /**
     * @description
     * Assigns a unique code to Project__c records that do not already have one.
     *
     * @param projects List of Project__c records to update with generated codes.
     */
    public static void assignProjectCodes(List<Project__c> projects) {
        if (projects == null) {
            return;
        }
        for (Project__c proj : projects) {
            if (proj == null) {
                continue;
            }
            if (String.isBlank(proj.Project_Code__c)) {
                String prefix = 'AL-';
                String timePart = String.valueOf(Datetime.now().getTime()).right(6);
                String randomPart = String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 4);
                proj.Project_Code__c = prefix + timePart + '-' + randomPart;
            }
        }
    }

    /**
     * @description
     * Sends email notifications to:
     * - The assigned Supervisor
     * - The Client (Contact)
     * - Management team (via custom label)
     * - Enrollment team (via custom label)
     *
     * @param projects List of Project__c records to process for email.
     */
    public static void sendProjectApprovedEmail(List<Project__c> projects) {
        if (projects == null || projects.isEmpty()) {
            return;
        }

        try {
            Map<Id, Contact> contactMap = getClientContacts(projects);
            Map<Id, User> userMap = getSupervisorUsers(projects);

            EmailTemplate clientTmpl = fetchEmailTemplate(CLIENT_TEMPLATE);
            EmailTemplate supTmpl = fetchEmailTemplate(SUPERVISOR_TEMPLATE);
            EmailTemplate managerTmpl = fetchEmailTemplate(MANAGER_TEMPLATE);
            EmailTemplate mgmtTmpl = fetchEmailTemplate(MGMT_TEMPLATE);
            EmailTemplate enrollmentTmpl = fetchEmailTemplate(ENROLLMENT_TEMPLATE);

            List<Messaging.SingleEmailMessage> allEmails = new List<Messaging.SingleEmailMessage>();

            for (Project__c proj : projects) {
                if (proj == null) {
                    continue;
                }
                Contact client = contactMap.get(proj.Client__c);
                User sup = userMap.get(proj.Supervisor_User__c);

                // Supervisor
                if (sup != null && String.isNotBlank(sup.Email) && supTmpl != null) {
                    allEmails.add(
                        buildEmailMessage(
                            sup.Id,
                            proj.Id,
                            replaceTemplateVars(supTmpl.Subject,   proj, client, sup),
                            replaceTemplateVars(supTmpl.HtmlValue, proj, client, sup)
                        )
                    );
                }

                // Client
                if (client != null && String.isNotBlank(client.Email) && clientTmpl != null) {
                    allEmails.add(
                        buildEmailMessage(
                            client.Id,
                            proj.Id,
                            replaceTemplateVars(clientTmpl.Subject,   proj, client, sup),
                            replaceTemplateVars(clientTmpl.HtmlValue, proj, client, sup)
                        )
                    );
                }

                // Management (label list; unchanged)
                allEmails.addAll(buildGroupEmails(mgmtTmpl, proj, client, sup, Label.Arelia_Living_Enrollment_Members));

                // Manager (role-based list -> string join; call unchanged)
                allEmails.addAll(buildGroupEmails(managerTmpl, proj, client, sup, String.join(getManagerEmailsByRole(), ',')));

                // Enrollment (role-based list -> string join; call unchanged)
                allEmails.addAll(buildGroupEmails(enrollmentTmpl, proj, client, sup, String.join(getEnrollmentEmailsByRole(), ',')));
            }

            if (!allEmails.isEmpty()) {
                Messaging.sendEmail(allEmails);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error sending emails for Projects: ' + e.getMessage());
        }
    }

    /**
     * @description
     * Retrieves the Contact records (clients) associated with the given Project records.
     */
    private static Map<Id, Contact> getClientContacts(List<Project__c> projects) {
        Set<Id> contactIds = new Set<Id>();
        for (Project__c proj : projects) {
            if (proj != null && proj.Client__c != null) {
                contactIds.add(proj.Client__c);
            }
        }
        if (contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        try {
            return new Map<Id, Contact>([SELECT Id, Name, Email, Password__c FROM Contact WHERE Id IN :contactIds]);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching Contacts: ' + e.getMessage());
            return new Map<Id, Contact>();
        }
    }

    /**
     * @description
     * Retrieves the Supervisor Users assigned to the given Project records.
     */
    private static Map<Id, User> getSupervisorUsers(List<Project__c> projects) {
        Set<Id> userIds = new Set<Id>();
        for (Project__c proj : projects) {
            if (proj != null && proj.Supervisor_User__c != null) {
                userIds.add(proj.Supervisor_User__c);
            }
        }
        if (userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        try {
            return new Map<Id, User>([SELECT Id, Name, Email FROM User WHERE Id IN :userIds]);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching Users: ' + e.getMessage());
            return new Map<Id, User>();
        }
    }

    /**
     * @description
     * Builds emails for a list of recipients (comma-separated).
     * If the template includes {{{ManagerName}}}, we personalize one email per recipient
     * using the matching User.Name (fallback: local-part of email).
     * Otherwise, we preserve original behavior: one email with all ToAddresses.
     */
    private static List<Messaging.SingleEmailMessage> buildGroupEmails(EmailTemplate tmpl, Project__c proj,
                                                        Contact contact, User sup, String labelEmails) 
    {
        List<Messaging.SingleEmailMessage> result = new List<Messaging.SingleEmailMessage>();
        if (tmpl == null || String.isBlank(labelEmails)) {
            return result;
        }

        try {
            List<String> emailList = new List<String>();
            for (String raw : labelEmails.split(',')) {
                if (String.isNotBlank(raw)) {
                    emailList.add(raw.trim());
                }
            }
            if (emailList.isEmpty()) {
                return result;
            }

            Boolean needsManagerName =
                (tmpl.Subject != null && tmpl.Subject.contains('{{{ManagerName}}}')) ||
                (tmpl.HtmlValue != null && tmpl.HtmlValue.contains('{{{ManagerName}}}'));

            if (needsManagerName) {
                // Personalize per recipient
                Map<String, String> emailToName = resolveUserNamesByEmail(emailList);

                for (String addr : emailList) {
                    if (String.isBlank(addr)) {
                        continue;
                    }
                    String mgrName = emailToName.containsKey(addr) ? emailToName.get(addr) : nameFromEmail(addr);

                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(new List<String>{ addr });
                    email.setSubject(replaceTemplateVars(tmpl.Subject,   proj, contact, sup, mgrName));
                    email.setHtmlBody(replaceTemplateVars(tmpl.HtmlValue, proj, contact, sup, mgrName));
                    email.setSaveAsActivity(false);
                    email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
                    result.add(email);
                }
            } else {
                // Original behavior: one email with all recipients
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(emailList);
                email.setSubject(replaceTemplateVars(tmpl.Subject,   proj, contact, sup));
                email.setHtmlBody(replaceTemplateVars(tmpl.HtmlValue, proj, contact, sup));
                email.setSaveAsActivity(false);
                email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
                result.add(email);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error building group email: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description
     * Builds a single-target email message for the Supervisor or Client.
     */
    private static Messaging.SingleEmailMessage buildEmailMessage(Id targetId, Id whatId, String subject,String body) 
    {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(targetId);
        email.setWhatId(whatId);
        email.setSubject(subject);
        email.setHtmlBody(body);
        email.setSaveAsActivity(false);
        email.setOrgWideEmailAddressId(getOrgWideEmailAddressId());
        return email;
    }

    // ---------------- Merge helpers ----------------

    // Existing replacement (kept)
    private static String replaceTemplateVars(String input, Project__c proj, Contact contact, User sup) {
        return replaceTemplateVars(input, proj, contact, sup, null);
    }

    // Manager-aware overload (adds {{{ManagerName}}})
    private static String replaceTemplateVars(String input,Project__c proj,Contact contact,User sup,String managerName) 
    {
        String base = (input == null) ? '' : input;
        base = base
            .replace('{{{Project__c.Name}}}', safe(proj != null ? proj.Name : ''))
            .replace('{{{Project__c.Project_Code__c}}}', safe(proj != null ? proj.Project_Code__c : ''))
            .replace('{{{Project__c.Status__c}}}', safe(proj != null ? proj.Status__c : ''))
            .replace('{{{Project__c.Project_Request_Quotation_Type__c}}}',safe(proj != null ? getPicklistLabel(Project__c.Project_Request_Quotation_Type__c, proj.Project_Request_Quotation_Type__c): ''))
            .replace('{{{Project__r.Client__r.Name}}}', safe(contact != null ? contact.Name : ''))
            .replace('{{{Project__r.Client__r.Password__c}}}', safe(contact != null ? contact.Password__c : ''))
            .replace('{{{Project__r.Client__r.Email}}}', safe(contact != null ? contact.Email : ''))           
            .replace('{{{Project__r.Supervisor_User__r.Name}}}', safe(sup != null ? sup.Name : ''));
        if (base.contains('{{{ManagerName}}}')) {
            base = base.replace('{{{ManagerName}}}', safe(managerName));
        }
        return base;
    }

    /**
     * @description
     * Returns the picklist label for a stored API value.
     * If no matching label is found, returns the original value.
     *
     * @param fieldRef Picklist field reference.
     * @param apiValue Stored API value from record.
     * @return Picklist label or original value.
     */
    private static String getPicklistLabel(Schema.SObjectField fieldRef, String apiValue) {
        if (fieldRef == null || String.isBlank(apiValue)) {
            return '';
        }

        try {
            for (Schema.PicklistEntry entry : fieldRef.getDescribe().getPicklistValues()) {
                if (entry.getValue() == apiValue) {
                    return entry.getLabel();
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting picklist label: ' + e.getMessage());
        }

        return apiValue;
    }

    /**
     * @description
     * Retrieves the EmailTemplate by developer name.
     */
    private static EmailTemplate fetchEmailTemplate(String name) {
        try {
            List<EmailTemplate> templates = [SELECT Id, Subject, HtmlValue FROM EmailTemplate
                WHERE DeveloperName = :name LIMIT 1];
            return templates.isEmpty() ? null : templates[0];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching EmailTemplate: ' + name + ' | ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description
     * Retrieves the Org-Wide Email Address Id for use in email sending.
     */
    private static Id getOrgWideEmailAddressId() {
        try {
            List<OrgWideEmailAddress> addresses = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :DEFAULT_OWD_EMAIL LIMIT 1];
            return addresses.isEmpty() ? null : addresses[0].Id;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching OrgWideEmailAddress: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Safe string (never null).
     */
    private static String safe(String value) {
        return String.isNotBlank(value) ? value : '';
    }

    /**
     * @description Resolve User.Name by email for personalization.
     */
    private static Map<String, String> resolveUserNamesByEmail(List<String> emails) {
        Map<String, String> m = new Map<String, String>();
        if (emails == null || emails.isEmpty()) {
            return m;
        }
        List<User> users = [SELECT Name, Email FROM User WHERE IsActive = true AND Email IN :emails];
        for (User u : users) {
            if (u != null && String.isNotBlank(u.Email)) {
                m.put(u.Email.trim(), u.Name);
            }
        }
        return m;
    }

    /**
     * @description Fallback: derive a readable name from an email address.
     * e.g., "priya.sharma@x.com" -> "Priya Sharma"
     */
    private static String nameFromEmail(String email) {
        if (String.isBlank(email)) {
            return '';
        }
        String local = email.split('@')[0];
        local = local.replace('.', ' ').replace('_', ' ').replace('-', ' ');
        List<String> parts = local.split(' ');
        List<String> pretty = new List<String>();
        for (String p : parts) {
            if (String.isBlank(p)) {
                continue;
            }
            pretty.add(p.substring(0, 1).toUpperCase() + (p.length() > 1 ? p.substring(1).toLowerCase() : ''));
        }
        return String.join(pretty, ' ');
    }

    // ---------------- Existing role-based helpers (unchanged) ----------------

    /**
     * @description Fetches manager user emails based on role name.
     */
    private static List<String> getManagerEmailsByRole() {
        List<String> managerEmails = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Manager%'
              AND IsActive = true AND Email != null]) 
        {
            managerEmails.add(u.Email.trim());
        }
        return managerEmails;
    }

    /**
     * @description Fetches Enrollment user emails based on role name.
     */
    private static List<String> getEnrollmentEmailsByRole() {
        List<String> enrollmentEmails = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Enrollment%'
              AND IsActive = true AND Email != null]) 
        {
            enrollmentEmails.add(u.Email.trim());
        }
        return enrollmentEmails;
    }
}