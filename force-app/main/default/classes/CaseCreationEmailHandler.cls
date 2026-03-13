/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-24-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public without sharing class CaseCreationEmailHandler {

    // =========================================================================
    // METHOD 1: Update Supervisor User (Runs Synchronously)
    // =========================================================================
    public static void linkSupervisorUser(List<Case> newCases) {
        try {
            Set<Id> projectIds = new Set<Id>();
            for (Case c : newCases) {
                if (c.Project__c != null) {
                    projectIds.add(c.Project__c);
                }
            }

            if (projectIds.isEmpty()) return;

            Map<Id, Project__c> projectMap = new Map<Id, Project__c>(
                [SELECT Id, Supervisor_Email_Text_c__c FROM Project__c WHERE Id IN :projectIds]
            );

            Set<String> supervisorEmails = new Set<String>();
            for (Project__c p : projectMap.values()) {
                if (String.isNotBlank(p.Supervisor_Email_Text_c__c)) {
                    supervisorEmails.add(p.Supervisor_Email_Text_c__c);
                }
            }

            Map<String, Id> emailToUserIdMap = new Map<String, Id>();
            if (!supervisorEmails.isEmpty()) {
                for (User u : [SELECT Id, Email FROM User WHERE Email IN :supervisorEmails AND IsActive = true]) {
                    emailToUserIdMap.put(u.Email, u.Id);
                }
            }

            for (Case c : newCases) {
                if (c.Project__c != null && projectMap.containsKey(c.Project__c)) {
                    String supEmail = projectMap.get(c.Project__c).Supervisor_Email_Text_c__c;
                    if (supEmail != null && emailToUserIdMap.containsKey(supEmail)) {
                        c.Supervisor_User__c = emailToUserIdMap.get(supEmail);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('⚠️ Error linking Supervisor User: ' + e.getMessage());
        }
    }

    // =========================================================================
    // METHOD 2: Send Creation Emails (Runs Asynchronously / @future)
    // =========================================================================
    @future(callout=true)
    public static void sendProjectEmails(Set<Id> caseIds) {
        try {
            List<Case> caseList = [
                SELECT Id, Project__c, Project_Client_Email__c, Supervisor_Email__c 
                FROM Case 
                WHERE Id IN :caseIds
            ];

            String clientTemplateName = 'Client_Case_Template';
            String supervisorTemplateName = 'Supervisor_Case_Template';
            
            Map<String, Id> templateMap = new Map<String, Id>();
            for (EmailTemplate et : [SELECT Id, DeveloperName FROM EmailTemplate 
                                     WHERE DeveloperName IN (:clientTemplateName, :supervisorTemplateName)]) {
                templateMap.put(et.DeveloperName, et.Id);
            }

            if (templateMap.isEmpty()) return;

            List<String> managerEmails = new List<String>();
            if (String.isNotBlank(System.Label.Arelia_Living_Enrollment_Members)) {
                managerEmails = System.Label.Arelia_Living_Enrollment_Members.split(',');
            }

            Contact dummyContact;
            try {
                dummyContact = [SELECT Id, Email FROM Contact LIMIT 1];
            } catch (Exception e) {
                System.debug('❌ No Contact found in Org.');
                return; 
            }

            Id orgWideEmailId = null;
            try {
                OrgWideEmailAddress owea = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
                orgWideEmailId = owea.Id;
            } catch (Exception e) { }

            List<Messaging.SingleEmailMessage> mailsToSend = new List<Messaging.SingleEmailMessage>();

            for (Case c : caseList) {
                if (String.isNotBlank(c.Project_Client_Email__c) && templateMap.containsKey(clientTemplateName)) {
                    Messaging.SingleEmailMessage clientMail = new Messaging.SingleEmailMessage();
                    clientMail.setTemplateId(templateMap.get(clientTemplateName));
                    clientMail.setWhatId(c.Id); 
                    clientMail.setTargetObjectId(dummyContact.Id); 
                    clientMail.setTreatTargetObjectAsRecipient(false); 
                    clientMail.setToAddresses(new List<String>{c.Project_Client_Email__c});
                    if (orgWideEmailId != null) clientMail.setOrgWideEmailAddressId(orgWideEmailId);
                    clientMail.setSaveAsActivity(false);
                    mailsToSend.add(clientMail);
                }

                if (String.isNotBlank(c.Supervisor_Email__c) && templateMap.containsKey(supervisorTemplateName)) {
                    Messaging.SingleEmailMessage supervisorMail = new Messaging.SingleEmailMessage();
                    supervisorMail.setTemplateId(templateMap.get(supervisorTemplateName));
                    supervisorMail.setWhatId(c.Id);
                    supervisorMail.setTargetObjectId(dummyContact.Id);
                    supervisorMail.setTreatTargetObjectAsRecipient(false);
                    supervisorMail.setToAddresses(new List<String>{c.Supervisor_Email__c});
                    if (!managerEmails.isEmpty()) {
                        supervisorMail.setCcAddresses(managerEmails);
                    }
                    if (orgWideEmailId != null) supervisorMail.setOrgWideEmailAddressId(orgWideEmailId);
                    supervisorMail.setSaveAsActivity(false);
                    mailsToSend.add(supervisorMail);
                }
            }

            if (!mailsToSend.isEmpty()) {
                Messaging.sendEmail(mailsToSend, false);
            }

        } catch (Exception ex) {
            System.debug('❌ Email Handler Error: ' + ex.getMessage());
        }
    }

    // =========================================================================
    // METHOD 3: Send Closure Emails (Runs Asynchronously / @future)
    // NEW ADDITION: Uses exactly the same logic, but with the Closure templates.
    // =========================================================================
    @future(callout=true)
    public static void sendClosureEmails(Set<Id> caseIds) {
        try {
            // 1. Re-query Cases 
            List<Case> caseList = [
                SELECT Id, Project__c, Project_Client_Email__c, Supervisor_Email__c 
                FROM Case 
                WHERE Id IN :caseIds
            ];

            // 2. Get NEW Templates
            String clientTemplateName = 'Case_Closure_Client_Template';
            String supervisorTemplateName = 'Case_Closure_Supervisor_Template';
            
            Map<String, Id> templateMap = new Map<String, Id>();
            for (EmailTemplate et : [SELECT Id, DeveloperName FROM EmailTemplate 
                                     WHERE DeveloperName IN (:clientTemplateName, :supervisorTemplateName)]) {
                templateMap.put(et.DeveloperName, et.Id);
            }

            if (templateMap.isEmpty()) return;

            // 3. Get Manager Emails
            List<String> managerEmails = new List<String>();
            if (String.isNotBlank(System.Label.Arelia_Living_Enrollment_Members)) {
                managerEmails = System.Label.Arelia_Living_Enrollment_Members.split(',');
            }

            // 4. Get Dummy Contact 
            Contact dummyContact;
            try {
                dummyContact = [SELECT Id, Email FROM Contact LIMIT 1];
            } catch (Exception e) {
                System.debug('❌ No Contact found in Org.');
                return; 
            }

            // 5. Get Org-Wide Email Address 
            Id orgWideEmailId = null;
            try {
                OrgWideEmailAddress owea = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
                orgWideEmailId = owea.Id;
            } catch (Exception e) { }

            List<Messaging.SingleEmailMessage> mailsToSend = new List<Messaging.SingleEmailMessage>();

            // 6. Build Emails
            for (Case c : caseList) {
                
                // --- A. Closure Client Email ---
                if (String.isNotBlank(c.Project_Client_Email__c) && templateMap.containsKey(clientTemplateName)) {
                    Messaging.SingleEmailMessage clientMail = new Messaging.SingleEmailMessage();
                    clientMail.setTemplateId(templateMap.get(clientTemplateName));
                    clientMail.setWhatId(c.Id); 
                    clientMail.setTargetObjectId(dummyContact.Id); 
                    clientMail.setTreatTargetObjectAsRecipient(false); 
                    clientMail.setToAddresses(new List<String>{c.Project_Client_Email__c});
                    if (orgWideEmailId != null) clientMail.setOrgWideEmailAddressId(orgWideEmailId);
                    clientMail.setSaveAsActivity(false);
                    mailsToSend.add(clientMail);
                }

                // --- B. Closure Supervisor Email (+ Manager CC) ---
                if (String.isNotBlank(c.Supervisor_Email__c) && templateMap.containsKey(supervisorTemplateName)) {
                    Messaging.SingleEmailMessage supervisorMail = new Messaging.SingleEmailMessage();
                    supervisorMail.setTemplateId(templateMap.get(supervisorTemplateName));
                    supervisorMail.setWhatId(c.Id);
                    supervisorMail.setTargetObjectId(dummyContact.Id);
                    supervisorMail.setTreatTargetObjectAsRecipient(false);
                    supervisorMail.setToAddresses(new List<String>{c.Supervisor_Email__c});
                    
                    if (!managerEmails.isEmpty()) {
                        supervisorMail.setCcAddresses(managerEmails);
                    }
                    
                    if (orgWideEmailId != null) supervisorMail.setOrgWideEmailAddressId(orgWideEmailId);
                    supervisorMail.setSaveAsActivity(false);
                    mailsToSend.add(supervisorMail);
                }
            }

            // 7. Send All Emails
            if (!mailsToSend.isEmpty()) {
                Messaging.sendEmail(mailsToSend, false);
            }

        } catch (Exception ex) {
            System.debug('❌ Closure Email Handler Error: ' + ex.getMessage());
        }
    }
}