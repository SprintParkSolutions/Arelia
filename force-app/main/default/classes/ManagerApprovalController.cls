/**
 * @description Controller for the Manager Approval Portal (LWC) for architecture deisgn .
 * Refactored to reduce Cognitive Complexity and fix PMD violations.
 * Updated to include Manager-specific context (Budget, Client Info).
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ManagerApprovalController {

    // --- Inner Classes ---

    private class ManagerNotificationData {
        public Architecture_Design__c design;
        public String action;
        public String comments;
    }

    private class EmailContext {
        public EmailTemplate template;
        public List<String> toAddresses;
        public ManagerNotificationData data;
        public List<ContentVersion> files;
    }

    // --- 1. Fetch Design Details ---

   @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDesignById(String recordId) {
        try {
            // Fetch Design + Parent Project/Opportunity Details
            // REMOVED: Name (title) and Architecture_Budget__c
            Architecture_Design__c design = [
                SELECT Id, Status__c, Manager_Approval__c, Manager_Comments__c, Related_File_Id__c,
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c,
                       Project__r.Name, LastModifiedDate
                FROM Architecture_Design__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            // Resolve Parent Name
            String parentName = (design.Opportunity__r != null) ? design.Opportunity__r.Name :
                                (design.Project__r != null) ? design.Project__r.Name : 'Unknown Project';

            // Resolve Client Name
            String clientName = (design.Opportunity__r != null && design.Opportunity__r.Lead_Name__c != null)
                                ? design.Opportunity__r.Lead_Name__c : 'The Client';

            // Build Result Map
            Map<String, Object> result = new Map<String, Object>();
            result.put('id', design.Id);
            // result.put('title', design.Name); // REMOVED
            result.put('projectName', parentName);
            result.put('status', design.Manager_Approval__c ? 'Approved' : 'Pending');
            result.put('comments', design.Manager_Comments__c);

            // Manager Specific Context
            // result.put('budget', design.Architecture_Budget__c); // REMOVED
            result.put('clientName', clientName);
            result.put('clientApprovedDate', design.LastModifiedDate.format('MMM dd, yyyy'));

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error loading design record: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void submitManagerDecision(String recordId, String action, String comments) {
        try {
            // 1. Fetch the design (We need Opportunity__c field for the update logic)
            Architecture_Design__c design = fetchDesignForDecision(recordId);

            if (action == 'Approve') {
                design.Manager_Approval__c = true;
                design.Manager_Comments__c = String.isNotBlank(comments) ? comments : 'Approved By Manager';
                
                // 2. THIS WAS MISSING - Call the method to update Opportunity
                handleOpportunityUpdate(design); 
                
            } else if (action == 'Reject') {
                design.Manager_Approval__c = false;
                design.Manager_Comments__c = comments;
            }

            update design;

            // 3. Send Notifications
            ManagerNotificationData notificationData = new ManagerNotificationData();
            notificationData.design = design;
            notificationData.action = action;
            notificationData.comments = design.Manager_Comments__c;

            sendManagerResponseNotification(notificationData);

        } catch (Exception e) {
            throw new AuraHandledException('Error submitting decision: ' + e.getMessage());
        }
    }


    // Helper to reduce complexity in submitManagerDecision
    private static Architecture_Design__c fetchDesignForDecision(String recordId) {
        return [
            SELECT Id, Opportunity__c, Related_File_Id__c,
                   Opportunity__r.Name,
                   Opportunity__r.Project_Description__c,
                   Opportunity__r.Lead_Name__c, 
                   Opportunity__r.Supervisor_User_Email__c,
                   Opportunity__r.Primary_Contact__r.Email, 
                   Opportunity__r.Supervisor_User__r.FirstName, 
                   Opportunity__r.Supervisor_User__r.LastName,
                   Opportunity__r.Supervisor_User__r.Phone,
                   Project__r.Name,
                   Manager_Comments__c 
            FROM Architecture_Design__c 
            WHERE Id = :recordId 
            LIMIT 1
        ];
    }

    // Helper to separate Opportunity update logic
    private static void handleOpportunityUpdate(Architecture_Design__c design) {
        if (design.Opportunity__c != null) {
            Opportunity oppToUpdate = new Opportunity(
                Id = design.Opportunity__c, 
                Architecture_Manager_Approval__c = true
            );
            update oppToUpdate;
        }
    }

    // --- 3. Notification Logic ---

    private static void sendManagerResponseNotification(ManagerNotificationData data) {
        List<ContentVersion> cvList = fetchAttachments(data.design.Id);

        // 1. Send SUPERVISOR Email
        if (data.design.Opportunity__r != null && String.isNotBlank(data.design.Opportunity__r.Supervisor_User_Email__c)) {
            sendEmail(
                new List<String>{ data.design.Opportunity__r.Supervisor_User_Email__c }, 
                Label.Manager_Response_Notification_Template, 
                data, 
                cvList
            );
        }

        // 2. Send CLIENT Email (Only on Approve)
        if (data.action == 'Approve' && 
            data.design.Opportunity__r != null && 
            data.design.Opportunity__r.Primary_Contact__r != null && 
            String.isNotBlank(data.design.Opportunity__r.Primary_Contact__r.Email)) {
            
            sendEmail(
                new List<String>{ data.design.Opportunity__r.Primary_Contact__r.Email }, 
                Label.Client_Final_Response_Template, 
                data, 
                cvList
            );
        }
    }

    // Fixed ExcessiveParameterList
    private static void sendEmail(List<String> recipients, String templateDevName, ManagerNotificationData data, List<ContentVersion> files) {
        try {
            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateDevName LIMIT 1];
            
            EmailContext ctx = new EmailContext();
            ctx.template = et;
            ctx.toAddresses = recipients;
            ctx.data = data;
            ctx.files = files;

            Messaging.SingleEmailMessage mail = buildEmailMessage(ctx);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug('Email Send Failed (' + templateDevName + '): ' + e.getMessage());
        }
    }

    // --- Helpers ---

    private static List<ContentVersion> fetchAttachments(Id designId) {
        Set<Id> docIds = new Set<Id>();
        for(ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :designId]) {
            docIds.add(link.ContentDocumentId);
        }
        if (docIds.isEmpty()) { return new List<ContentVersion>(); }
        
        return [SELECT Id, Title, FileExtension, VersionData FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true];
    }

    // Refactored to reduce Cognitive Complexity
    private static Messaging.SingleEmailMessage buildEmailMessage(EmailContext ctx) {
        // 1. Generate substitution map
        Map<String, String> mergeFields = generateMergeMap(ctx.data);

        // 2. Apply substitutions
        String subject = applyMergeFields(ctx.template.Subject, mergeFields);
        String htmlBody = applyMergeFields(ctx.template.HtmlValue, mergeFields);

        // 3. Construct Email
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(ctx.toAddresses);
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);

        // 4. Set OWD
        setOrgWideAddress(mail);

        // 5. Attach Files
        if (ctx.files != null && !ctx.files.isEmpty()) {
            List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
            for(ContentVersion cv : ctx.files) {
                Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
                attach.setFileName(cv.Title + '.' + cv.FileExtension);
                attach.setBody(cv.VersionData);
                attachments.add(attach);
            }
            mail.setFileAttachments(attachments);
        }

        return mail;
    }

    private static Map<String, String> generateMergeMap(ManagerNotificationData data) {
        Architecture_Design__c des = data.design;
        Map<String, String> m = new Map<String, String>();

        String projectName = (des.Opportunity__r != null) ? des.Opportunity__r.Name : 
                             (des.Project__r != null) ? des.Project__r.Name : 'Unknown Project';
        
        String projectDesc = (des.Opportunity__r != null && des.Opportunity__r.Project_Description__c != null) 
                             ? des.Opportunity__r.Project_Description__c : '';
        
        String supervisorPhone = (des.Opportunity__r != null && des.Opportunity__r.Supervisor_User__r != null && des.Opportunity__r.Supervisor_User__r.Phone != null) 
                                 ? des.Opportunity__r.Supervisor_User__r.Phone : '';
        
        String supervisorEmail = (des.Opportunity__r != null && des.Opportunity__r.Supervisor_User_Email__c != null) 
                                 ? des.Opportunity__r.Supervisor_User_Email__c : '';

        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        String decisionLabel = (data.action == 'Approve') ? 'Approved' : 'Changes Requested';

        m.put('[PROJECT_NAME]', projectName);
        m.put('[PROJECT_DESCRIPTION]', projectDesc);
        m.put('[DECISION]', decisionLabel);
        m.put('[COMMENTS]', safeComments);
        m.put('[SUPERVISOR_NAME]', resolveSupervisorName(des));
        m.put('[SUPERVISOR_EMAIL]', supervisorEmail);
        m.put('[SUPERVISOR_PHONE]', supervisorPhone);
        m.put('[CLIENT_NAME]', resolveClientName(des));

        return m;
    }

    private static String applyMergeFields(String content, Map<String, String> mergeFields) {
        if (String.isBlank(content)) return '';
        String result = content;
        for (String key : mergeFields.keySet()) {
            result = result.replace(key, mergeFields.get(key));
        }
        return result;
    }

    private static void setOrgWideAddress(Messaging.SingleEmailMessage mail) {
        try {
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :System.Label.Arelia_OWD LIMIT 1];
            if (!owd.isEmpty()) { mail.setOrgWideEmailAddressId(owd[0].Id); }
        } catch (Exception ex) { System.debug('OWD Error'); }
    }

    private static String resolveSupervisorName(Architecture_Design__c design) {
        if (design.Opportunity__r != null && design.Opportunity__r.Supervisor_User__r != null) {
            String f = design.Opportunity__r.Supervisor_User__r.FirstName;
            String l = design.Opportunity__r.Supervisor_User__r.LastName;
            return ((f != null ? f : '') + ' ' + (l != null ? l : '')).trim();
        }
        return 'Enrollment Team';
    }

    private static String resolveClientName(Architecture_Design__c design) {
        if (design.Opportunity__r != null && design.Opportunity__r.Lead_Name__c != null) {
            return design.Opportunity__r.Lead_Name__c;
        }
        return 'Valued Client';
    }
}