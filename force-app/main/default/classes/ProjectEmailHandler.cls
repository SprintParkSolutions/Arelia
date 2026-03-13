/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 12-11-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class ProjectEmailHandler {

    public static void sendEmailForProject(Project__c project) {
        if (project == null) {
            System.debug(LoggingLevel.WARN, '[ProjectEmailHandler] Project is null');
            return;
        }

        try {
            System.debug('[ProjectEmailHandler] Start email process for Project: ' + project.Id);

            // ✅ Re-query project to include Supervisor relationship fields
            project = [
                SELECT Id, Name, Start_Date__c, Client__c, Client_Email__c, Supervisor_User__c, Supervisor_Email_Text_c__c, Supervisor_Contact_Text_c__c
                FROM Project__c
                WHERE Id = :project.Id
                LIMIT 1
            ];

            List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

            // Load email template IDs
            Id clientTemplateId = getTemplateIdByDeveloperName('Project_To_Lead');
            Id mgmtTemplateId = getTemplateIdByDeveloperName('Project_To_IDC');

            System.debug('[ProjectEmailHandler] Client Template ID: ' + clientTemplateId);
            System.debug('[ProjectEmailHandler] Management Template ID: ' + mgmtTemplateId);

            // Prepare client email
            if (project.Client__c != null && project.Client_Email__c != null && clientTemplateId != null) {
                Messaging.SingleEmailMessage clientEmail = prepareClientEmail(project, clientTemplateId);
                System.debug('[ProjectEmailHandler] Prepared Client Email to: ' + project.Client_Email__c);
                emailMessages.add(clientEmail);
            } else {
                System.debug(LoggingLevel.WARN, '[ProjectEmailHandler] Missing Client__c, Client_Email__c or template');
            }

            // Prepare management email
            if (mgmtTemplateId != null) {
                List<Messaging.SingleEmailMessage> mgmtEmails = prepareManagementEmails(project, mgmtTemplateId);
                System.debug('[ProjectEmailHandler] Prepared ' + mgmtEmails.size() + ' Management Emails');
                emailMessages.addAll(mgmtEmails);
            }

            // Send Emails
            if (!emailMessages.isEmpty()) {
                System.debug('[ProjectEmailHandler] Sending ' + emailMessages.size() + ' emails...');
                sendEmails(emailMessages);
            } else {
                System.debug(LoggingLevel.WARN, '[ProjectEmailHandler] No emails prepared');
            }

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, '[ProjectEmailHandler] Failed: ' + ex.getMessage());
            throw new AuraHandledException('Project Email Error: ' + ex.getMessage());
        }
    }

    private static Id getTemplateIdByDeveloperName(String devName) {
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate 
            WHERE DeveloperName = :devName 
            LIMIT 1
        ];
        return (templates.isEmpty()) ? null : templates[0].Id;
    }

    private static Messaging.SingleEmailMessage prepareClientEmail(Project__c proj, Id templateId) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTemplateId(templateId);
        email.setTargetObjectId(proj.Client__c); // Contact
        email.setWhatId(proj.Id); // Project
        email.setToAddresses(new List<String>{ proj.Client_Email__c });
        email.setTreatTargetObjectAsRecipient(true);
        email.setSaveAsActivity(false);
        return email;
    }

    private static List<Messaging.SingleEmailMessage> prepareManagementEmails(Project__c proj, Id templateId) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // Use Custom Label or Metadata for management emails
        String mgmtEmails = Label.Management_Email_Addresses;

        if (String.isBlank(mgmtEmails)) {
            System.debug(LoggingLevel.WARN, '[ProjectEmailHandler] No management emails in custom label');
            return emails;
        }

        for (String emailAddr : mgmtEmails.split(',')) {
            if (String.isNotBlank(emailAddr)) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ emailAddr.trim() });
                email.setTemplateId(templateId);
                email.setTargetObjectId(proj.Client__c != null ? proj.Client__c : UserInfo.getUserId());
                email.setWhatId(proj.Id);
                email.setTreatTargetObjectAsRecipient(false);
                email.setSaveAsActivity(false);
                emails.add(email);
            }
        }

        return emails;
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> messages) {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);

        for (Integer i = 0; i < results.size(); i++) {
            Messaging.SendEmailResult result = results[i];
            if (result.isSuccess()) {
                System.debug('[ProjectEmailHandler] Email ' + i + ' sent successfully.');
            } else {
                for (Messaging.SendEmailError error : result.getErrors()) {
                    System.debug(LoggingLevel.ERROR, '[ProjectEmailHandler] Email ' + i + ' failed: ' + error.getMessage());
                }
            }
        }
    }
}