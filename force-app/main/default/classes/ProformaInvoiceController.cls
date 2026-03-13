/**
 * @description Controller for Proforma Invoice Client Approval & Upload.
 * Refactored to reduce Cognitive Complexity and fix PMD violations (Braces, Complexity).
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ProformaInvoiceController {

    // --- Inner Classes ---
    private class NotificationData {
        public Proforma_Invoice__c invoice;
        public String status;
        public String comments;
        public List<ContentVersion> fileAttachments; 
    }

    private class EmailConfig {
        public String templateName;
        public List<String> toAddresses;
        public NotificationData data;
        public Boolean isManagerRequest;
        public String customSubject;
    }

    public class InvoiceHistoryWrapper {
        @AuraEnabled public String id; 
        @AuraEnabled public String fileName;
        @AuraEnabled public String clientStatus;
        @AuraEnabled public String clientComments;
        @AuraEnabled public Boolean managerApproved; 
        @AuraEnabled public String managerComments;
    }

    // --- 1. INTERNAL: Send Email & Create Invoice Record ---

    @AuraEnabled
    public static void sendInvoiceForApproval(Id recordId, List<String> fileIds) {
        try {
            if (fileIds == null || fileIds.isEmpty()) {
                throw new AuraHandledException('Error: No files selected.');
            }

            // 1. Create Transaction
            Proforma_Invoice__c invoiceRec = createInvoiceTransaction(recordId, fileIds);
            
            // 2. Send Email
            List<ContentVersion> cvList = getLatestContentVersions(fileIds);
            sendClientRequestEmail(invoiceRec.Id, cvList);
            
            updateOpportunityStatus(recordId);

        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    private static Proforma_Invoice__c createInvoiceTransaction(Id recordId, List<String> fileIds) {
        Proforma_Invoice__c invoiceRec = new Proforma_Invoice__c();
        invoiceRec.Related_File_Id__c = fileIds[0];
        
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            invoiceRec.Opportunity__c = recordId;
        } else if (sObjName == 'Project__c') {
            invoiceRec.Project__c = recordId;
        }
        
        invoiceRec.Secure_Token__c = UUID.randomUUID().toString();
        invoiceRec.Status__c = 'Sent';
        upsert invoiceRec;

        linkFilesToInvoice(invoiceRec.Id, fileIds, recordId);
        return invoiceRec;
    }

    private static void sendClientRequestEmail(Id invoiceId, List<ContentVersion> files) {
        NotificationData data = new NotificationData();
        data.invoice = queryInvoiceForEmail(invoiceId);
        data.fileAttachments = files;
        data.status = 'Sent'; 

        String clientEmail = getClientEmail(data.invoice);
        if (String.isBlank(clientEmail)) {
            return;
        }

        EmailConfig config = new EmailConfig();
        config.templateName = Label.Proforma_Client_Approval_Template; 
        config.toAddresses = new List<String>{ clientEmail };
        config.data = data;
        config.isManagerRequest = false;
        
        String fileTitles = getFileTitlesCommaSeparated(data.fileAttachments);
        String subjectBase = 'Approval Request: ' + (data.fileAttachments.size() > 1 ? 'Multiple Files' : fileTitles);
        
        if (data.invoice.Opportunity__r != null) {
            config.customSubject = subjectBase + ' for ' + data.invoice.Opportunity__r.Name;
        } else {
            config.customSubject = subjectBase;
        }

        sendTemplatedEmail(config);
    }

    // --- 2. EXTERNAL: Submit Client Decision ---

    @AuraEnabled
    public static void submitClientDecision(String recordId, String status, String comments) {
        try {
            Proforma_Invoice__c invoice = queryInvoiceForEmail(recordId);
            invoice.Status__c = status;
            invoice.Client_Comments__c = String.isNotBlank(comments) ? comments : 'Approved by Client';
            
            update invoice;

            handleNotifications(invoice, status, comments);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static void handleNotifications(Proforma_Invoice__c invoice, String status, String comments) {
        NotificationData data = new NotificationData();
        data.invoice = invoice;
        data.status = status;
        data.comments = comments;
        data.fileAttachments = fetchAllLinkedFiles(invoice.Id);

        notifySupervisor(invoice, data);

        if (status == 'Approved') {
            notifyManager(data);
        }
    }

    private static void notifySupervisor(Proforma_Invoice__c invoice, NotificationData data) {
        if (invoice.Opportunity__r != null && String.isNotBlank(invoice.Opportunity__r.Supervisor_User_Email__c)) {
            EmailConfig config = new EmailConfig();
            config.templateName = Label.Proforma_Client_Response_Template;
            config.toAddresses = new List<String>{ invoice.Opportunity__r.Supervisor_User_Email__c };
            config.data = data;
            config.isManagerRequest = false;
            sendTemplatedEmail(config);
        }
    }

    private static void notifyManager(NotificationData data) {
        List<String> managerEmails = getManagerAddresses();
        if (!managerEmails.isEmpty()) {
            EmailConfig config = new EmailConfig();
            config.templateName = Label.Proforma_Manager_Approval_Request_Template;
            config.toAddresses = managerEmails;
            config.data = data;
            config.isManagerRequest = true;
            sendTemplatedEmail(config);
        }
    }

    // --- 4. Shared Email Engine ---

    private static void sendTemplatedEmail(EmailConfig config) {
        List<EmailTemplate> etList = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :config.templateName LIMIT 1];
        if (etList.isEmpty()) {
            return;
        } 
        EmailTemplate et = etList[0];

        try {
            Map<String, String> mergeFields = getMergeFields(config);
            String htmlBody = applyMergeFields(et.HtmlValue, mergeFields);
            String subject = (String.isNotBlank(config.customSubject)) ? config.customSubject : applyMergeFields(et.Subject, mergeFields);

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            setOrgWideAddress(mail);
            mail.setToAddresses(config.toAddresses);
            mail.setSubject(subject);
            mail.setHtmlBody(htmlBody);

            if (config.data.fileAttachments != null && !config.data.fileAttachments.isEmpty()) {
                attachFiles(mail, config.data.fileAttachments);
            }
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) { 
            System.debug('Email Send Failed: ' + e.getMessage()); 
        }
    }

    private static void attachFiles(Messaging.SingleEmailMessage mail, List<ContentVersion> files) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        for (ContentVersion cv : files) {
            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            attach.setFileName(cv.Title + '.' + cv.FileExtension);
            if (cv.VersionData != null) {
                attach.setBody(cv.VersionData);
                attachments.add(attach);
            }
        }
        mail.setFileAttachments(attachments);
    }

    // --- 5. Data Helpers (Refactored for Complexity) ---

    private static Map<String, String> getMergeFields(EmailConfig config) {
        Map<String, String> fields = new Map<String, String>();
        Proforma_Invoice__c inv = config.data.invoice;
        
        // Split logic into smaller chunks
        populateProjectDetails(fields, inv);
        populateDecisionDetails(fields, config);
        populatePeopleDetails(fields, inv);
        
        resolveLinks(fields, config, inv.Id);
        
        String titles = (config.data.fileAttachments != null) ? getFileTitlesCommaSeparated(config.data.fileAttachments) : '';
        fields.put('FILE_TITLE', titles);

        return fields;
    }

    private static void populateProjectDetails(Map<String, String> fields, Proforma_Invoice__c inv) {
        String oppName = (inv.Opportunity__r != null) ? inv.Opportunity__r.Name : 'Project';
        fields.put('PROJECT_NAME', oppName);
        fields.put('OPPORTUNITY_NAME', oppName);
    }

    private static void populateDecisionDetails(Map<String, String> fields, EmailConfig config) {
        String decisionStatus = String.isNotBlank(config.data.status) ? config.data.status : 'Pending';
        
        // Maps to [CLIENT_ACTION] or [DECISION]
        fields.put('CLIENT_ACTION', decisionStatus); 
        fields.put('DECISION', decisionStatus);
        
        String commentText = String.isNotBlank(config.data.comments) ? config.data.comments : 'No comments.';
        fields.put('COMMENTS', commentText);
        fields.put('CLIENT_COMMENTS', commentText); 
    }

    private static void populatePeopleDetails(Map<String, String> fields, Proforma_Invoice__c inv) {
        String clientName = 'Valued Client';
        if (inv.Opportunity__r != null && inv.Opportunity__r.Lead_Name__c != null) {
            clientName = inv.Opportunity__r.Lead_Name__c;
        }
        fields.put('CLIENT_NAME', clientName);
        fields.put('CLIENT_EMAIL', getClientEmail(inv));
        fields.put('SUPERVISOR_NAME', getSupervisorName(inv));
    }

    private static void resolveLinks(Map<String, String> fields, EmailConfig config, String invoiceId) {
        String siteUrl = System.Label.Arelia_Site_Label.removeEnd('/');
        
        String managerPage = System.Label.Proforma_Manager_Site_Page;
        if (!managerPage.startsWith('/')) {
            managerPage = '/' + managerPage;
        }
        
        String clientPage = System.Label.Proforma_Invoice_Site_Page;
        if (!clientPage.startsWith('/')) {
            clientPage = '/' + clientPage;
        }

        fields.put('MANAGER_LINK_URL', config.isManagerRequest ? (siteUrl + managerPage + '?id=' + invoiceId) : '');
        fields.put('MANAGER_LINK', ''); 
        fields.put('APPROVAL_LINK', siteUrl + clientPage + '?id=' + invoiceId);
    }

    private static String applyMergeFields(String text, Map<String, String> fields) {
        if (text == null) {
            return '';
        }
        String result = text;
        for (String key : fields.keySet()) {
            String value = fields.get(key);
            if (value == null) {
                value = '';
            }
            result = result.replace('[' + key + ']', value);
        }
        return result;
    }

    // --- 6. Database Queries & Utils ---

    private static Proforma_Invoice__c queryInvoiceForEmail(Id recordId) {
        return [
            SELECT Id, Related_File_Id__c, Status__c, Client_Comments__c, 
                   Opportunity__r.Name, Opportunity__r.Lead_Name__c, 
                   Opportunity__r.Primary_Contact__r.Email, 
                   Opportunity__r.Supervisor_User_Email__c, 
                   Opportunity__r.Supervisor_User__r.FirstName, 
                   Opportunity__r.Supervisor_User__r.LastName, 
                   Project__r.Name 
            FROM Proforma_Invoice__c 
            WHERE Id = :recordId 
            LIMIT 1
        ];
    }

    private static List<ContentVersion> getLatestContentVersions(List<String> fileIds) {
        return [
            SELECT Id, Title, FileExtension, ContentDocumentId, VersionData 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :fileIds AND IsLatest = true
        ];
    }

    private static void linkFilesToInvoice(Id invoiceId, List<String> fileIds, Id parentRecordId) {
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (String fId : fileIds) {
            links.add(new ContentDocumentLink(LinkedEntityId = invoiceId, ContentDocumentId = fId, ShareType = 'V', Visibility = 'AllUsers'));
        }
        if (!links.isEmpty()) {
            insert links;
        }
        
        List<ContentDocumentLink> oldLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :parentRecordId AND ContentDocumentId IN :fileIds];
        if (!oldLinks.isEmpty()) {
            delete oldLinks;
        }
    }

    private static List<ContentVersion> fetchAllLinkedFiles(Id invoiceId) {
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :invoiceId]) {
            docIds.add(link.ContentDocumentId);
        }
        if (docIds.isEmpty()) {
            return new List<ContentVersion>();
        }
        return [SELECT VersionData, Title, FileExtension FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true];
    }

    private static String getClientEmail(Proforma_Invoice__c inv) {
        return (inv.Opportunity__r != null && inv.Opportunity__r.Primary_Contact__r != null) ? inv.Opportunity__r.Primary_Contact__r.Email : '';
    }

    private static String getSupervisorName(Proforma_Invoice__c inv) {
        if (inv.Opportunity__r != null && inv.Opportunity__r.Supervisor_User__r != null) {
            String f = inv.Opportunity__r.Supervisor_User__r.FirstName;
            String l = inv.Opportunity__r.Supervisor_User__r.LastName;
            return ((f != null ? f : '') + ' ' + (l != null ? l : '')).trim();
        }
        return 'Team';
    }

    private static List<String> getManagerAddresses() {
        String label = Label.Arelia_Living_Enrollment_Members;
        if (String.isBlank(label)) {
            return new List<String>();
        }
        List<String> addrs = new List<String>();
        for (String s : label.split('[,;]')) {
            if (String.isNotBlank(s)) {
                addrs.add(s.trim());
            }
        }
        return addrs;
    }

    private static String getFileTitlesCommaSeparated(List<ContentVersion> cvList) {
        List<String> t = new List<String>();
        for (ContentVersion c : cvList) {
            t.add(c.Title);
        }
        return String.join(t, ', ');
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

    private static void updateOpportunityStatus(Id recordId) { 
        System.debug('Status update placeholder for: ' + recordId);
    }

    // --- 7. EXTERNAL: Get Details (Project Name = Opportunity Name) ---

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getInvoiceById(String recordId) {
        try {
            Proforma_Invoice__c invoice = [
                SELECT Id, Status__c, Client_Comments__c, Related_File_Id__c,
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c
                FROM Proforma_Invoice__c 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            ContentDocument doc = [SELECT Title FROM ContentDocument WHERE Id = :invoice.Related_File_Id__c LIMIT 1];
            
            Map<String, String> result = new Map<String, String>();
            result.put('title', doc.Title);
            result.put('status', invoice.Status__c);
            result.put('comments', invoice.Client_Comments__c);

            // Logic: Force Project Name to be Opportunity Name
            String projectName = 'Proforma Invoice';
            if (invoice.Opportunity__r != null) {
                projectName = invoice.Opportunity__r.Name;
            }
            result.put('projectName', projectName);

            String clientName = 'Valued Client';
            if (invoice.Opportunity__r != null && invoice.Opportunity__r.Lead_Name__c != null) {
                clientName = invoice.Opportunity__r.Lead_Name__c;
            }
            result.put('clientName', clientName);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid Link or Record Not Found');
        }
    }

    // --- 8. HISTORY TABLE DATA ---

    @AuraEnabled(cacheable=true)
    public static List<InvoiceHistoryWrapper> getRelatedInvoices(Id recordId) {
        List<Proforma_Invoice__c> listInv = fetchInvoices(recordId);
        if (listInv.isEmpty()) {
            return new List<InvoiceHistoryWrapper>();
        }

        Map<Id, String> fNames = getFileMap(listInv);
        return createWrappers(listInv, fNames);
    }

    private static List<Proforma_Invoice__c> fetchInvoices(Id recordId) {
        String sObj = recordId.getSObjectType().getDescribe().getName();
        if (sObj == 'Opportunity') {
            return [SELECT Id, Status__c, Client_Comments__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c FROM Proforma_Invoice__c WHERE Opportunity__c = :recordId ORDER BY CreatedDate DESC];
        } 
        if (sObj == 'Project__c') {
            return [SELECT Id, Status__c, Client_Comments__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c FROM Proforma_Invoice__c WHERE Project__c = :recordId ORDER BY CreatedDate DESC];
        }
        return new List<Proforma_Invoice__c>();
    }

    private static Map<Id, String> getFileMap(List<Proforma_Invoice__c> listInv) {
        Set<Id> fIds = new Set<Id>();
        for (Proforma_Invoice__c i : listInv) {
            if (String.isNotBlank(i.Related_File_Id__c)) {
                fIds.add(i.Related_File_Id__c);
            }
        }
        
        Map<Id, String> fNames = new Map<Id, String>();
        if (!fIds.isEmpty()) {
            for (ContentDocument d : [SELECT Id, Title FROM ContentDocument WHERE Id IN :fIds]) {
                fNames.put(d.Id, d.Title);
            }
        }
        return fNames;
    }

    private static List<InvoiceHistoryWrapper> createWrappers(List<Proforma_Invoice__c> listInv, Map<Id, String> fNames) {
        List<InvoiceHistoryWrapper> results = new List<InvoiceHistoryWrapper>();
        for (Proforma_Invoice__c i : listInv) {
            InvoiceHistoryWrapper w = new InvoiceHistoryWrapper();
            w.id = i.Id;
            w.fileName = fNames.containsKey(i.Related_File_Id__c) ? fNames.get(i.Related_File_Id__c) : 'File Not Found';
            w.clientStatus = i.Status__c;
            w.clientComments = i.Client_Comments__c;
            w.managerApproved = i.Manager_Approval__c;
            w.managerComments = i.Manager_Comments__c;
            results.add(w);
        }   
        return results;
    }
}