/**
 * @description Controller for Proforma Invoice Manager Approval (Public Site).
 * Refactored for PMD Compliance (Braces, Complexity) and specific Project Name logic.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ProformaManagerController {

    private class ManagerNotificationData {
        public Proforma_Invoice__c invoice;
        public String action;
        public String comments;
    }

    // --- 1. Fetch Invoice Details ---

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInvoiceById(String recordId) {
        try {
            Proforma_Invoice__c invoice = [
                SELECT Id, Status__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c, 
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c,
                       Project__r.Name, LastModifiedDate
                FROM Proforma_Invoice__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            // Logic: Project Name is Opportunity Name
            String parentName = (invoice.Opportunity__r != null) ? invoice.Opportunity__r.Name : 'Unknown Project';

            // Resolve Client Name
            String clientName = (invoice.Opportunity__r != null && invoice.Opportunity__r.Lead_Name__c != null) 
                                ? invoice.Opportunity__r.Lead_Name__c : 'The Client';

            Map<String, Object> result = new Map<String, Object>();
            result.put('id', invoice.Id);
            result.put('projectName', parentName);
            result.put('clientStatus', invoice.Status__c);
            result.put('managerStatus', invoice.Manager_Approval__c ? 'Approved' : 'Pending');
            result.put('comments', invoice.Manager_Comments__c);
            
            // UI Data
            result.put('clientName', clientName);
            result.put('clientApprovedDate', invoice.LastModifiedDate.format('MMM dd, yyyy'));
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid ID or Record Not Found');
        }
    }

    // --- 2. Submit Manager Decision ---

    @AuraEnabled
    public static void submitManagerDecision(String recordId, String action, String comments) {
        try {
            Proforma_Invoice__c invoice = [
                SELECT Id, Opportunity__c, 
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c,
                       Opportunity__r.Supervisor_User_Email__c,
                       Opportunity__r.Primary_Contact__r.Email, 
                       Opportunity__r.Supervisor_User__r.FirstName, 
                       Opportunity__r.Supervisor_User__r.LastName,  
                       Project__r.Name, Manager_Comments__c, Related_File_Id__c
                FROM Proforma_Invoice__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            if (action == 'Approve') {
                invoice.Manager_Approval__c = true;
                invoice.Manager_Comments__c = String.isNotBlank(comments) ? comments : 'Approved by manager';
            } else if (action == 'Reject') {
                invoice.Manager_Approval__c = false; 
                invoice.Manager_Comments__c = comments;
            }
            update invoice;

            sendManagerResponseNotification(invoice, action, invoice.Manager_Comments__c);

        } catch (Exception e) { 
            throw new AuraHandledException('Error submitting decision: ' + e.getMessage()); 
        }
    }

    // --- 3. Notification Logic ---

    private static void sendManagerResponseNotification(Proforma_Invoice__c invoice, String action, String comments) {
        sendInternalNotification(invoice, action, comments);
        if (action == 'Approve') {
            sendClientNotification(invoice);
        }
    }

    private static void sendInternalNotification(Proforma_Invoice__c invoice, String action, String comments) {
        try {
            if (invoice.Opportunity__r == null || String.isBlank(invoice.Opportunity__r.Supervisor_User_Email__c)) {
                return;
            }

            List<String> toAddresses = new List<String>{ invoice.Opportunity__r.Supervisor_User_Email__c };
            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Proforma_Manager_Response_Template LIMIT 1];
            
            ManagerNotificationData data = new ManagerNotificationData();
            data.invoice = invoice;
            data.action = action;
            data.comments = comments;

            Messaging.SingleEmailMessage mail = buildInternalEmail(et, toAddresses, data);
            
            Set<Id> docIds = fetchLinkedFileIds(invoice.Id);
            if (!docIds.isEmpty()) {
                attachAllFilesToEmail(mail, docIds);
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) { 
            System.debug('Internal Email Failed: ' + e.getMessage()); 
        }
    }

    private static void sendClientNotification(Proforma_Invoice__c invoice) {
        try {
            String clientEmail = (invoice.Opportunity__r != null && invoice.Opportunity__r.Primary_Contact__r != null) ? invoice.Opportunity__r.Primary_Contact__r.Email : null;
            if (String.isBlank(clientEmail)) {
                return;
            }

            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Proforma_Client_Final_Approval_Template LIMIT 1];

            // Ensure Project Name is Opportunity Name
            String oppName = (invoice.Opportunity__r != null) ? invoice.Opportunity__r.Name : 'Project';
            String clientName = (invoice.Opportunity__r != null && invoice.Opportunity__r.Lead_Name__c != null) ? invoice.Opportunity__r.Lead_Name__c : 'Valued Client';

            String htmlBody = et.HtmlValue.replace('[OPPORTUNITY_NAME]', oppName)
                                          .replace('[PROJECT_NAME]', oppName)
                                          .replace('[CLIENT_NAME]', clientName);
            
            String subject = et.Subject.replace('[OPPORTUNITY_NAME]', oppName)
                                       .replace('[PROJECT_NAME]', oppName);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            setOrgWideAddress(mail);
            mail.setToAddresses(new String[] { clientEmail });
            mail.setSubject(subject);
            mail.setHtmlBody(htmlBody);

            Set<Id> docIds = fetchLinkedFileIds(invoice.Id);
            if (!docIds.isEmpty()) {
                attachAllFilesToEmail(mail, docIds);
            }
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        } catch (Exception e) { 
            System.debug('Client Email Failed: ' + e.getMessage()); 
        }
    }

    // --- Helpers ---

    private static Set<Id> fetchLinkedFileIds(Id invoiceId) {
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :invoiceId]) {
            docIds.add(link.ContentDocumentId);
        }
        return docIds;
    }

    private static Messaging.SingleEmailMessage buildInternalEmail(EmailTemplate et, List<String> toAddresses, ManagerNotificationData data) {
        String projectName = (data.invoice.Opportunity__r != null) ? data.invoice.Opportunity__r.Name : 'Project';
        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        String decisionLabel = (data.action == 'Approve') ? 'Approved' : 'Rejected / Changes Requested';
        
        // --- UPDATED: Supervisor Name Logic (First Name + Last Name) ---
        String supervisorName = 'Team';
        if (data.invoice.Opportunity__r != null && data.invoice.Opportunity__r.Supervisor_User__r != null) {
            String firstName = data.invoice.Opportunity__r.Supervisor_User__r.FirstName;
            String lastName = data.invoice.Opportunity__r.Supervisor_User__r.LastName;
            
            // Handle cases where First Name might be null
            supervisorName = (String.isNotBlank(firstName) ? firstName + ' ' : '') + 
                             (String.isNotBlank(lastName) ? lastName : '');
            
            if (String.isBlank(supervisorName)) { supervisorName = 'Team'; }
        }
        // -------------------------------------------------------------

        String clientName = (data.invoice.Opportunity__r != null) ? data.invoice.Opportunity__r.Lead_Name__c : 'Client';

        String htmlBody = et.HtmlValue.replace('[PROJECT_NAME]', projectName)
                                      .replace('[OPPORTUNITY_NAME]', projectName)
                                      .replace('[DECISION]', decisionLabel)
                                      .replace('[COMMENTS]', safeComments)
                                      .replace('[SUPERVISOR_NAME]', supervisorName) // Uses the new full name
                                      .replace('[CLIENT_NAME]', clientName);
                                      
        String subject = et.Subject.replace('[OPPORTUNITY_NAME]', projectName);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        setOrgWideAddress(mail);
        mail.setToAddresses(toAddresses);
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        return mail;
    }
    private static void attachAllFilesToEmail(Messaging.SingleEmailMessage mail, Set<Id> fileIds) {
        List<ContentVersion> files = [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true];
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        for (ContentVersion file : files) {
            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            attach.setFileName(file.Title + '.' + file.FileExtension);
            attach.setBody(file.VersionData);
            attachments.add(attach);
        }
        mail.setFileAttachments(attachments);
    }

    private static void setOrgWideAddress(Messaging.SingleEmailMessage mail) {
        try {
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :System.Label.Arelia_OWD LIMIT 1];
            if (!owd.isEmpty()) {
                mail.setOrgWideEmailAddressId(owd[0].Id);
            }
        } catch (Exception ex) { 
            System.debug('OWD Error'); 
        }
    }
}