/**
 * @description Controller for Proforma Invoice Client Approval & Upload.
 * Refactored to reduce Cognitive Complexity and fix PMD violations (Braces, Complexity).
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ProformaInvoiceController {
    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Proforma invoice approval is supported only for Arelia opportunities.';

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
    /**
    * Sends Proforma Invoice approval push notification
    * asynchronously to the related Prospect mobile device.
    */
    
    // =========================================================
    // LWC - SEND PROFORMA INVOICE FOR CLIENT APPROVAL
    // =========================================================
    @AuraEnabled
    public static void sendInvoiceForApproval(Id recordId,List<String> fileIds )
    {
        try {

            // 1. VALIDATE FILES
            if (fileIds == null || fileIds.isEmpty()) {
                throw new AuraHandledException('Error: No files selected.');
            }

            // 2. VALIDATE OPPORTUNITY
            validateAreliaOpportunity(recordId);

            // 3. CREATE PROFORMA INVOICE
            // Client approval request email is sent by
            // ProformaInvoiceTriggerHandler once Status__c
            // transitions to 'Sent' below, so it fires the
            // same way for any source that submits an invoice.
            Proforma_Invoice__c invoiceRec = createInvoiceTransaction(recordId,fileIds);

            // 4. MOBILE PUSH NOTIFICATION
            sendProformaNotificationAsync(String.valueOf(invoiceRec.Id));

            // 5. EXISTING OPPORTUNITY LOGIC

            updateOpportunityStatus(recordId);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
 
    @future(callout=true)
    public static void sendProformaNotificationAsync(String invoiceIdValue) {

        // ==========================================
        // 1. VALIDATE INVOICE ID
        // ==========================================
        if (String.isBlank(invoiceIdValue)) {
            System.debug(LoggingLevel.WARN,'PROFORMA PUSH: Invoice Id is blank.');
            return;
        }
        Id invoiceId;

        try {
            invoiceId = (Id) invoiceIdValue.trim();
            if (invoiceId.getSObjectType() != Proforma_Invoice__c.SObjectType) {
                System.debug(LoggingLevel.WARN,'PROFORMA PUSH: Invalid Invoice Id type.');
                return;
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'PROFORMA PUSH: Invalid Invoice Id. ' +e.getMessage());
            return;
        }

        // ==========================================
        // 2. GET PROFORMA INVOICE
        // ==========================================
        List<Proforma_Invoice__c> invoiceRecords = [SELECT Id, Name,Opportunity__c, Related_File_Id__c, Status__c
            FROM Proforma_Invoice__c WHERE Id = :invoiceId LIMIT 1 ];

        if (invoiceRecords.isEmpty()) {
            System.debug( LoggingLevel.WARN, 'PROFORMA PUSH: Invoice not found.' );
            return;
        }

        Proforma_Invoice__c invoiceRecord = invoiceRecords[0];
        
        System.debug(LoggingLevel.INFO,'PROFORMA PUSH: Invoice = ' + invoiceRecord.Id);
        System.debug(LoggingLevel.INFO,'PROFORMA PUSH: Opportunity = ' + invoiceRecord.Opportunity__c);
        System.debug(LoggingLevel.INFO,'PROFORMA PUSH: File = ' + invoiceRecord.Related_File_Id__c);

        // ==========================================
        // 3. VALIDATE OPPORTUNITY + FILE
        // ==========================================
        if (invoiceRecord.Opportunity__c == null || String.isBlank(invoiceRecord.Related_File_Id__c))
        {
            System.debug(LoggingLevel.WARN,'PROFORMA PUSH: Opportunity or file is missing.');
            return;
        }

        // ==========================================
        // 4. OPPORTUNITY -> CONVERTED LEAD
        // ==========================================
        List<Lead> convertedLeads = [SELECT Id, ConvertedOpportunityId, ConvertedDate FROM Lead
                WHERE IsConverted = true AND ConvertedOpportunityId =:invoiceRecord.Opportunity__c
                ORDER BY ConvertedDate DESC LIMIT 1 ];

        if (convertedLeads.isEmpty()) {
            System.debug( LoggingLevel.WARN, 'PROFORMA PUSH: No converted Lead found ' + 'for Opportunity: ' + invoiceRecord.Opportunity__c );
            return;
        }

        Id leadId = convertedLeads[0].Id;

        System.debug(LoggingLevel.INFO,'PROFORMA PUSH: Related Lead = ' +leadId);


        // ==========================================
        // 5. GET CLIENT DEVICE TOKENS
        // ==========================================
        List<Prospect_Device_Token__c> tokenRecords = [SELECT Id,Prospect_Lead__c,FCM_Token__c,Active__c,Last_Seen__c
                FROM Prospect_Device_Token__c WHERE Prospect_Lead__c = :leadId AND Active__c = true 
                ORDER BY Last_Seen__c DESC NULLS LAST LIMIT 90 ];
        
        System.debug(LoggingLevel.INFO,'PROFORMA PUSH: Token Count = ' + tokenRecords.size());
        
        if (tokenRecords.isEmpty()) {
            System.debug(LoggingLevel.WARN,'PROFORMA PUSH: No active device token '+ 'found for Lead: '+ leadId);
            return;
        }


        // ==========================================
        // 6. FIREBASE DATA PAYLOAD
        // ==========================================
        Map<String, String> dataPayload = new Map<String, String>
                    { 'recipientType' => 'prospect', 'leadId' => String.valueOf(leadId),
                        'opportunityId' => String.valueOf( invoiceRecord.Opportunity__c ),
                        'invoiceId' => String.valueOf( invoiceRecord.Id ),'notificationType' => 'PROFORMA_INVOICE_UPLOADED',
                        'actionType' => 'OPEN_PROFORMA_INVOICE', 'route' => 'prospect_proforma_invoice'
                    };

        // Avoid duplicate notifications
        Set<String> processedTokens = new Set<String>();
        
        // ==========================================
        // 7. SEND FIREBASE NOTIFICATION
        // ==========================================
        for ( Prospect_Device_Token__c tokenRecord : tokenRecords ) 
        {
            String fcmToken = tokenRecord.FCM_Token__c;
            if (String.isBlank(fcmToken)) {
                continue;
            }
            if (processedTokens.contains(fcmToken))
            {
                continue;
            }
            processedTokens.add(fcmToken);
        
            try {

                System.debug(LoggingLevel.INFO,'PROFORMA PUSH: Sending notification '+ 'for Lead = '
                    + leadId+ ', Invoice = '+ invoiceRecord.Id);

                FirebasePushService.sendPushToToken(fcmToken, 'Proforma Invoice Approval Required', 'Your Proforma Invoice has been '
                    + 'submitted for your approval. ' + 'Tap to review the document ' + 'and respond.', dataPayload );

                System.debug( LoggingLevel.INFO, 'PROFORMA PUSH: Firebase call completed.' );

            } catch (Exception e) {
                System.debug( LoggingLevel.ERROR, 'PROFORMA PUSH FAILED: ' + e.getMessage() );
            }
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
        upsert invoiceRec;

        linkFilesToInvoice(invoiceRec.Id, fileIds, recordId);

        // Status flips to 'Sent' only after files are linked, so the
        // ProformaInvoiceTriggerHandler (which reacts to this update)
        // can find the linked files when it sends the approval email.
        invoiceRec.Status__c = 'Sent';
        update invoiceRec;

        return invoiceRec;
    }

    /**
     * @description Sends the client approval request email for an invoice whose Status__c
     * just transitioned to 'Sent'. Called from ProformaInvoiceTriggerHandler so it fires
     * for any source that saves a Proforma_Invoice__c into that state, not just this class.
     */
    public static void sendClientApprovalRequestEmail(Id invoiceId) {
        sendClientRequestEmail(invoiceId, fetchAllLinkedFiles(invoiceId));
    }

    /**
     * @description Sends the post-decision notifications (supervisor, and manager when approved)
     * for an invoice whose Status__c just changed away from 'Sent'. Called from
     * ProformaInvoiceTriggerHandler so it fires regardless of what updated the record.
     */
    public static void sendClientDecisionNotifications(Id invoiceId, String status, String comments) {
        handleNotifications(queryInvoiceForEmail(invoiceId), status, comments);
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
    public static void submitClientDecision(String token, String status, String comments) {
        try {
            Proforma_Invoice__c invoice = queryInvoiceByToken(token);
            invoice.Status__c = status;
            invoice.Client_Comments__c = String.isNotBlank(comments) ? comments : 'Approved by Client';

            update invoice;
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
        String supervisorEmail = getSupervisorEmail(invoice);
        if (String.isNotBlank(supervisorEmail)) {
            EmailConfig config = new EmailConfig();
            config.templateName = Label.Proforma_Client_Response_Template;
            config.toAddresses = new List<String>{ supervisorEmail };
            config.data = data;
            config.isManagerRequest = false;
            sendTemplatedEmail(config);
        }
    }

    private static String getSupervisorEmail(Proforma_Invoice__c inv) {
        if (inv.Opportunity__r != null && String.isNotBlank(inv.Opportunity__r.Supervisor_User_Email__c)) {
            return inv.Opportunity__r.Supervisor_User_Email__c;
        }
        return '';
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
        
        resolveLinks(fields, config, inv.Secure_Token__c);
        
        String titles = (config.data.fileAttachments != null) ? getFileTitlesCommaSeparated(config.data.fileAttachments) : '';
        fields.put('FILE_TITLE', titles);

        return fields;
    }

    private static void populateProjectDetails(Map<String, String> fields, Proforma_Invoice__c inv) {
        String projectLabel = 'Project';
        if (inv.Opportunity__r != null) {
            projectLabel = inv.Opportunity__r.Name;
        } else if (inv.Project__r != null) {
            projectLabel = inv.Project__r.Name;
        }
        fields.put('PROJECT_NAME', projectLabel);
        fields.put('OPPORTUNITY_NAME', projectLabel);
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

    private static void resolveLinks(Map<String, String> fields, EmailConfig config, String secureToken) {
        String siteUrl = System.Label.Arelia_Site_Label.removeEnd('/');

        String managerPage = System.Label.Proforma_Manager_Site_Page;
        if (!managerPage.startsWith('/')) {
            managerPage = '/' + managerPage;
        }

        String clientPage = System.Label.Proforma_Invoice_Site_Page;
        if (!clientPage.startsWith('/')) {
            clientPage = '/' + clientPage;
        }

        // Links carry the invoice's Secure_Token__c (not its record Id) so the public site
        // can resolve/authorize the record without exposing a guessable Salesforce Id.
        fields.put('MANAGER_LINK_URL', config.isManagerRequest ? (siteUrl + managerPage + '?id=' + secureToken) : '');
        fields.put('MANAGER_LINK', '');
        fields.put('APPROVAL_LINK', siteUrl + clientPage + '?id=' + secureToken);
    }

    @TestVisible
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
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        List<Proforma_Invoice__c> invoices = [SELECT Id, Related_File_Id__c, Status__c, Client_Comments__c, Secure_Token__c, Opportunity__r.Name, Opportunity__r.Lead_Name__c, Opportunity__r.Primary_Contact__r.Email, Opportunity__r.Supervisor_User_Email__c,
                   Opportunity__r.Supervisor_User__r.FirstName, Opportunity__r.Supervisor_User__r.LastName, Project__r.Name FROM Proforma_Invoice__c WHERE Id = :recordId AND (Opportunity__c = null OR Opportunity__r.RecordTypeId = :areliaOpportunityRecordTypeId) LIMIT 1];

        if (invoices.isEmpty()) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }

        return invoices[0];
    }

    /**
     * @description Resolves a Proforma_Invoice__c by its Secure_Token__c for public site access,
     * instead of by record Id, so the public approval link doesn't expose a guessable Salesforce Id.
     */
    private static Proforma_Invoice__c queryInvoiceByToken(String token) {
        if (String.isBlank(token)) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }

        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        List<Proforma_Invoice__c> invoices = [SELECT Id, Related_File_Id__c, Status__c, Client_Comments__c, Secure_Token__c, Opportunity__r.Name, Opportunity__r.Lead_Name__c, Opportunity__r.Primary_Contact__r.Email, Opportunity__r.Supervisor_User_Email__c,
                   Opportunity__r.Supervisor_User__r.FirstName, Opportunity__r.Supervisor_User__r.LastName, Project__r.Name FROM Proforma_Invoice__c WHERE Secure_Token__c = :token AND (Opportunity__c = null OR Opportunity__r.RecordTypeId = :areliaOpportunityRecordTypeId) LIMIT 1];

        if (invoices.isEmpty()) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }

        return invoices[0];
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
        if (inv.Opportunity__r != null && inv.Opportunity__r.Primary_Contact__r != null && String.isNotBlank(inv.Opportunity__r.Primary_Contact__r.Email)) {
            return inv.Opportunity__r.Primary_Contact__r.Email;
        }
        return '';
    }

    private static String getSupervisorName(Proforma_Invoice__c inv) {
        if (inv.Opportunity__r != null && inv.Opportunity__r.Supervisor_User__r != null) {
            String f = inv.Opportunity__r.Supervisor_User__r.FirstName;
            String l = inv.Opportunity__r.Supervisor_User__r.LastName;
            return ((f != null ? f : '') + ' ' + (l != null ? l : '')).trim();
        }
        return 'Team';
    }

    @TestVisible
    private static String getSupervisorNameForTest(Proforma_Invoice__c invoiceRecord) {
        return getSupervisorName(invoiceRecord);
    }

    private static List<String> getManagerAddresses() {
        String label = Label.Arelia_Living_Management_Members;
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

    private static void validateAreliaOpportunity(Id recordId) {
        if (recordId == null) {
            return;
        }

        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName != 'Opportunity') {
            return;
        }

        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();

        // Filter by RecordTypeId in SOQL so only supported Opportunity records continue.
        if (
            areliaOpportunityRecordTypeId == null ||
            [SELECT Id FROM Opportunity WHERE Id = :recordId
                AND RecordTypeId = :areliaOpportunityRecordTypeId LIMIT 1]
                .isEmpty()
        ) {
            throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }
    }

    // --- 7. EXTERNAL: Get Details (Project Name = Opportunity Name) ---

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getInvoiceById(String token) {
        try {
            Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
            List<Proforma_Invoice__c> invoices = [SELECT Id, Status__c, Client_Comments__c, Related_File_Id__c, Opportunity__r.Name, Opportunity__r.Lead_Name__c, Project__r.Name FROM Proforma_Invoice__c WHERE Secure_Token__c = :token
                AND (Opportunity__c = null OR Opportunity__r.RecordTypeId = :areliaOpportunityRecordTypeId) LIMIT 1];
            if (invoices.isEmpty()) {
                throw new AuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
            }
            Proforma_Invoice__c invoice = invoices[0];

            Map<String, String> result = new Map<String, String>();
            result.put('title', getPrimaryFileTitle(invoice));
            result.put('status', invoice.Status__c);
            result.put('comments', invoice.Client_Comments__c);

            // Logic: Force Project Name to be Opportunity Name (or the Project's own Name for Project-linked invoices)
            String projectName = 'Proforma Invoice';
            if (invoice.Opportunity__r != null) {
                projectName = invoice.Opportunity__r.Name;
            } else if (invoice.Project__r != null) {
                projectName = invoice.Project__r.Name;
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

    /**
     * @description Resolves a display title for the invoice's primary file. Falls back to any
     * file linked via ContentDocumentLink when Related_File_Id__c is blank - which happens for
     * invoices created by clients (e.g. the mobile app) that insert Proforma_Invoice__c directly
     * via the REST API instead of going through createInvoiceTransaction.
     */
    private static String getPrimaryFileTitle(Proforma_Invoice__c invoice) {
        if (String.isNotBlank(invoice.Related_File_Id__c)) {
            List<ContentDocument> docs = [SELECT Title FROM ContentDocument WHERE Id = :invoice.Related_File_Id__c LIMIT 1];
            if (!docs.isEmpty()) {
                return docs[0].Title;
            }
        }

        Set<Id> linkedDocIds = new Set<Id>();
        for (ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :invoice.Id LIMIT 1]) {
            linkedDocIds.add(link.ContentDocumentId);
        }
        if (linkedDocIds.isEmpty()) {
            return 'Proforma Invoice';
        }

        List<ContentDocument> linkedDocs = [SELECT Title FROM ContentDocument WHERE Id IN :linkedDocIds LIMIT 1];
        return linkedDocs.isEmpty() ? 'Proforma Invoice' : linkedDocs[0].Title;
    }

    // --- 8. HISTORY TABLE DATA ---

    @AuraEnabled(cacheable=true)
    public static List<InvoiceHistoryWrapper> getRelatedInvoices(Id recordId) {
        List<Proforma_Invoice__c> listInv = fetchInvoices(recordId);
        if (listInv.isEmpty()) {
            return new List<InvoiceHistoryWrapper>();
        }

        Map<Id, String> fileNamesByInvoiceId = resolveFileNames(listInv);
        return createWrappers(listInv, fileNamesByInvoiceId);
    }

    private static List<Proforma_Invoice__c> fetchInvoices(Id recordId) {
        String sObj = recordId.getSObjectType().getDescribe().getName();
        if (sObj == 'Opportunity') {
            Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
            return [SELECT Id, Status__c, Client_Comments__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c FROM Proforma_Invoice__c WHERE Opportunity__c = :recordId AND Opportunity__r.RecordTypeId = :areliaOpportunityRecordTypeId ORDER BY CreatedDate DESC];
        } 
        if (sObj == 'Project__c') {
            return [SELECT Id, Status__c, Client_Comments__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c FROM Proforma_Invoice__c WHERE Project__c = :recordId ORDER BY CreatedDate DESC];
        }
        return new List<Proforma_Invoice__c>();
    }

    /**
     * @description Resolves a display file name per invoice. Prefers the ContentDocument
     * pointed to by Related_File_Id__c; falls back to whatever file is linked via
     * ContentDocumentLink when that's blank or stale - which happens for invoices inserted
     * directly via REST by external clients (e.g. the mobile app) that never populate
     * Related_File_Id__c, mirroring the fallback in getPrimaryFileTitle.
     */
    private static Map<Id, String> resolveFileNames(List<Proforma_Invoice__c> listInv) {
        Set<Id> directFileIds = new Set<Id>();
        for (Proforma_Invoice__c i : listInv) {
            if (String.isNotBlank(i.Related_File_Id__c)) {
                directFileIds.add(i.Related_File_Id__c);
            }
        }

        Map<Id, String> directTitles = new Map<Id, String>();
        if (!directFileIds.isEmpty()) {
            for (ContentDocument d : [SELECT Id, Title FROM ContentDocument WHERE Id IN :directFileIds]) {
                directTitles.put(d.Id, d.Title);
            }
        }

        Set<Id> invoiceIdsNeedingFallback = new Set<Id>();
        for (Proforma_Invoice__c i : listInv) {
            if (!directTitles.containsKey(i.Related_File_Id__c)) {
                invoiceIdsNeedingFallback.add(i.Id);
            }
        }

        Map<Id, Id> invoiceToFirstDoc = new Map<Id, Id>();
        if (!invoiceIdsNeedingFallback.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :invoiceIdsNeedingFallback
                ORDER BY ContentDocumentId
            ]) {
                if (!invoiceToFirstDoc.containsKey(link.LinkedEntityId)) {
                    invoiceToFirstDoc.put(link.LinkedEntityId, link.ContentDocumentId);
                }
            }
        }

        Map<Id, String> fallbackTitles = new Map<Id, String>();
        if (!invoiceToFirstDoc.isEmpty()) {
            for (ContentDocument d : [SELECT Id, Title FROM ContentDocument WHERE Id IN :invoiceToFirstDoc.values()]) {
                fallbackTitles.put(d.Id, d.Title);
            }
        }

        Map<Id, String> fileNamesByInvoiceId = new Map<Id, String>();
        for (Proforma_Invoice__c i : listInv) {
            String title = directTitles.get(i.Related_File_Id__c);
            if (title == null) {
                Id fallbackDocId = invoiceToFirstDoc.get(i.Id);
                title = fallbackDocId != null ? fallbackTitles.get(fallbackDocId) : null;
            }
            fileNamesByInvoiceId.put(i.Id, String.isNotBlank(title) ? title : 'File Not Found');
        }
        return fileNamesByInvoiceId;
    }

    private static List<InvoiceHistoryWrapper> createWrappers(List<Proforma_Invoice__c> listInv, Map<Id, String> fileNamesByInvoiceId) {
        List<InvoiceHistoryWrapper> results = new List<InvoiceHistoryWrapper>();
        for (Proforma_Invoice__c i : listInv) {
            InvoiceHistoryWrapper w = new InvoiceHistoryWrapper();
            w.id = i.Id;
            w.fileName = fileNamesByInvoiceId.get(i.Id);
            w.clientStatus = i.Status__c;
            w.clientComments = i.Client_Comments__c;
            w.managerApproved = i.Manager_Approval__c;
            w.managerComments = i.Manager_Comments__c;
            results.add(w);
        }
        return results;
    }
}