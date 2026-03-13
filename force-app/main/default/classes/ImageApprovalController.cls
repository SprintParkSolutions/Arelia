/**
 * @description Controller for Client Image Approval LWC and Public Site.
 * Handles uploading design bundles, sending emails, and processing client decisions.
 * FIX: Replaced VersionData queries with setEntityAttachments to allow Guest Users to send multiple files.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ImageApprovalController {

    // ============================================================================
    // INNER CLASSES & WRAPPERS
    // ============================================================================

    public class DesignWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;       
        @AuraEnabled public String status;      
        @AuraEnabled public String statusClass;
        @AuraEnabled public String clientComments;
        @AuraEnabled public Date createdDate;
        @AuraEnabled public Boolean managerApproved;
        @AuraEnabled public String managerComments;
    }

    private class RecipientInfo {
        public String email;
        public String name;
    }

    private class NotificationData {
        public Architecture_Design__c design;
        public String status;
        public String comments;
    }

    private class ResolvedNames {
        public String supervisorName;
        public String clientName;
    }

    // ============================================================================
    // 1. INTERNAL: UPLOAD & SEND BUNDLE
    // ============================================================================

    @AuraEnabled
    public static void sendDesignBundle(Id recordId, List<String> fileIds, Decimal budget) {
        if (fileIds.isEmpty()) {
            return;
        }

        try {
            // 1. Create Record with Budget
            Architecture_Design__c designRec = createDesignRecord(recordId, fileIds[0], budget);
            
            // 2. Link Files to new Record
            linkFilesToDesign(designRec.Id, fileIds);

            // 3. Cleanup (Remove from Opportunity so they don't clutter the parent)
            cleanupOpportunityFiles(recordId, fileIds);

            // 4. Send Email
            sendEmailToClient(recordId, fileIds, designRec.Secure_Token__c);
            
            // 5. Update Opportunity Status
            updateOpportunityStatus(recordId);

        } catch (Exception e) {
            throw new AuraHandledException('Error sending bundle: ' + e.getMessage());
        }
    }

    private static Architecture_Design__c createDesignRecord(Id recordId, String mainFileId, Decimal budget) {
        Architecture_Design__c designRec = new Architecture_Design__c();
        linkDesignToParent(designRec, recordId);
        designRec.Secure_Token__c = UUID.randomUUID().toString();
        designRec.Status__c = 'Sent';
        designRec.Related_File_Id__c = mainFileId;
        designRec.Architecture_Budget__c = budget; 
        insert designRec;
        return designRec;
    }

    private static void linkFilesToDesign(Id designId, List<String> fileIds) {
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (String fileId : fileIds) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.LinkedEntityId = designId;
            cdl.ContentDocumentId = fileId;
            cdl.ShareType = 'V'; 
            cdl.Visibility = 'AllUsers'; 
            linksToInsert.add(cdl);
        }
        insert linksToInsert;
    }

    private static void cleanupOpportunityFiles(Id recordId, List<String> fileIds) {
        List<ContentDocumentLink> linksToDelete = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :recordId 
            AND ContentDocumentId IN :fileIds
        ];
        if (!linksToDelete.isEmpty()) {
            delete linksToDelete;
        }
    }

    private static void sendEmailToClient(Id recordId, List<String> fileIds, String token) {
        RecipientInfo recipient = fetchRecipientDetails(recordId);
        String fullLink = System.Label.Arelia_Site_Label + System.Label.Image_Approval + '?token=' + token;
        
        EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Client_Image_Approval_Template LIMIT 1];
        
        String htmlBody = et.HtmlValue;
        htmlBody = htmlBody.replace('[APPROVAL_LINK]', fullLink)
                           .replace('[CLIENT_NAME]', recipient.name);
        
        String subject = 'New Design Submission';
        if (et.Subject != null) {
            subject = et.Subject.replace('[FILE_TITLE]', 'New Design Submission');
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        setOrgWideAddress(mail);
        mail.setToAddresses(new String[] { recipient.email });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        
        // FIX: Use setEntityAttachments to securely attach ALL files
        List<Id> cvIds = getVersionIds(fileIds);
        if (!cvIds.isEmpty()) {
            mail.setEntityAttachments(cvIds);
        }
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    /**
     * @description FIX: Retrieves ContentVersion Ids directly. 
     * Bypasses Guest User 'VersionData' restrictions and heap limits.
     */
    private static List<Id> getVersionIds(List<String> fileIds) {
        List<Id> cvIds = new List<Id>();
        if (fileIds == null || fileIds.isEmpty()) {
            return cvIds;
        }

        for (ContentVersion cv : [SELECT Id FROM ContentVersion WHERE ContentDocumentId IN :fileIds AND IsLatest = true]) {
            cvIds.add(cv.Id);
        }
        return cvIds;
    }

    // ============================================================================
    // 2. INTERNAL: GET HISTORY
    // ============================================================================

    @AuraEnabled(cacheable=true)
    public static List<DesignWrapper> getRelatedImages(Id recordId) {
        List<DesignWrapper> designList = new List<DesignWrapper>();
        
        List<Architecture_Design__c> designs = [
            SELECT Id, Name, Status__c, Comments__c, CreatedDate, 
                   Manager_Approval__c, Manager_Comments__c
            FROM Architecture_Design__c 
            WHERE Opportunity__c = :recordId OR Project__c = :recordId 
            ORDER BY CreatedDate DESC
        ];
        
        for (Architecture_Design__c ad : designs) {
            DesignWrapper wrapper = new DesignWrapper();
            wrapper.id = ad.Id; 
            wrapper.title = ad.Name; 
            wrapper.createdDate = ad.CreatedDate.date();
            wrapper.status = ad.Status__c;
            wrapper.clientComments = ad.Comments__c;
            wrapper.managerApproved = ad.Manager_Approval__c;
            wrapper.managerComments = ad.Manager_Comments__c;

            wrapper.statusClass = getBadgeClass(ad.Status__c);
            designList.add(wrapper);
        }
        return designList;
    }

    private static String getBadgeClass(String status) {
        if (status == 'Approved') {
            return 'slds-badge slds-theme_success';
        }
        if (status == 'Changes Requested') {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge slds-theme_warning';
    }

    // ============================================================================
    // 3. EXTERNAL SITE METHODS
    // ============================================================================

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFileByToken(String token) {
        try {
            Architecture_Design__c design = [
                SELECT Id, Status__c, Comments__c, 
                       Project__r.Name, 
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c 
                FROM Architecture_Design__c 
                WHERE Secure_Token__c = :token 
                LIMIT 1
            ];

            Map<String, String> result = new Map<String, String>();
            result.put('status', design.Status__c);
            result.put('comments', design.Comments__c);

            String projectName = 'Architectural Design'; 
            if (design.Project__r != null) {
                projectName = design.Project__r.Name;
            } else if (design.Opportunity__r != null) {
                projectName = design.Opportunity__r.Name;
            }
            result.put('projectName', projectName);

            String clientName = 'Valued Client';
            if (design.Opportunity__r != null && design.Opportunity__r.Lead_Name__c != null) {
                clientName = design.Opportunity__r.Lead_Name__c;
            }
            result.put('clientName', clientName);

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid Link or Record Not Found');
        }
    }

    @AuraEnabled
    public static void submitDecision(String token, String status, String comments) {
        try {
            Architecture_Design__c design = [
                SELECT Id, Status__c, Comments__c, Related_File_Id__c,
                       Opportunity__r.Name, Opportunity__r.Lead_Name__c, 
                       Opportunity__r.Project_Description__c, Opportunity__r.Site_Space__c,
                       Opportunity__r.Primary_Contact__r.Email, 
                       Opportunity__r.Lead_Phone__c,
                       Opportunity__r.Supervisor_User_Email__c, 
                       Opportunity__r.Supervisor_User__r.FirstName,
                       Opportunity__r.Supervisor_User__r.LastName, 
                       Project__r.Name
                FROM Architecture_Design__c 
                WHERE Secure_Token__c = :token LIMIT 1
            ];

            design.Status__c = status;
            design.Comments__c = String.isNotBlank(comments) ? comments : 'Approved By Client';
            update design;

            sendResponseNotification(design, status, comments);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ============================================================================
    // 4. NOTIFICATION LOGIC
    // ============================================================================

    private static void sendResponseNotification(Architecture_Design__c design, String status, String comments) {
        try {
            List<String> toAddresses = getNotificationRecipients(design);
            
            if (toAddresses.isEmpty()) {
                System.debug('No Supervisor Email found. Notification skipped.');
                return;
            }

            EmailTemplate et = [SELECT Id, Subject, HtmlValue FROM EmailTemplate WHERE DeveloperName = :Label.Client_Response_Notification_Template LIMIT 1];
            NotificationData data = new NotificationData();
            data.design = design;
            data.status = status;
            data.comments = comments;

            Messaging.SingleEmailMessage mail = buildNotificationEmail(et, toAddresses, data);

            // Fetch & Attach ALL Files securely
            Set<Id> docIds = new Set<Id>();
            for(ContentDocumentLink link : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :design.Id]) {
                docIds.add(link.ContentDocumentId);
            }
            
            if (!docIds.isEmpty()) {
                List<String> fileIdList = new List<String>();
                for(Id idVal : docIds) {
                    fileIdList.add((String)idVal);
                }
                
                // FIX: Retrieve IDs and use setEntityAttachments to avoid Guest User binary access error
                List<Id> cvIds = getVersionIds(fileIdList);
                if (!cvIds.isEmpty()) {
                    mail.setEntityAttachments(cvIds);
                }
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) { 
            System.debug('Failed to send client response notification: ' + e.getMessage()); 
        }
    }

    private static Messaging.SingleEmailMessage buildNotificationEmail(EmailTemplate et, List<String> toAddresses, NotificationData data) {
        String projectName = 'Unknown Project';
        if (data.design.Opportunity__r != null) {
            projectName = data.design.Opportunity__r.Name;
        } else if (data.design.Project__r != null) {
            projectName = data.design.Project__r.Name;
        }

        String safeComments = String.isNotBlank(data.comments) ? data.comments : 'No comments provided.';
        ResolvedNames rNames = resolveNames(data);
        
        String oppDesc = (data.design.Opportunity__r != null) ? data.design.Opportunity__r.Project_Description__c : '';
        String siteSpace = (data.design.Opportunity__r != null) ? data.design.Opportunity__r.Site_Space__c : '';
        String clientEmail = (data.design.Opportunity__r != null && data.design.Opportunity__r.Primary_Contact__r != null) ? data.design.Opportunity__r.Primary_Contact__r.Email : '';
        
        String clientPhone = (data.design.Opportunity__r != null && data.design.Opportunity__r.Lead_Phone__c != null) 
                             ? data.design.Opportunity__r.Lead_Phone__c : 'N/A';

        String subject = et.Subject.replace('[CLIENT_NAME]', rNames.clientName).replace('[DECISION]', data.status);
        
        String htmlBody = et.HtmlValue.replace('[PROJECT_NAME]', projectName)
                                      .replace('[DECISION]', data.status)
                                      .replace('[COMMENTS]', safeComments)
                                      .replace('[SUPERVISOR_NAME]', rNames.supervisorName)
                                      .replace('[PROJECT_DESCRIPTION]', (oppDesc != null ? oppDesc : ''))
                                      .replace('[SITE_SPACE]', (siteSpace != null ? siteSpace : ''))
                                      .replace('[CLIENT_EMAIL]', (clientEmail != null ? clientEmail : ''))
                                      .replace('[CLIENT_MOBILE]', clientPhone) 
                                      .replace('[CLIENT_NAME]', rNames.clientName);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        setOrgWideAddress(mail);
        mail.setToAddresses(toAddresses);
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        return mail;
    }

    private static List<String> getNotificationRecipients(Architecture_Design__c design) {
        List<String> toAddresses = new List<String>();
        if (design.Opportunity__r != null && String.isNotBlank(design.Opportunity__r.Supervisor_User_Email__c)) {
            toAddresses.add(design.Opportunity__r.Supervisor_User_Email__c);
        }
        return toAddresses;
    }

    // ============================================================================
    // 5. GENERIC HELPERS
    // ============================================================================

    private static void linkDesignToParent(Architecture_Design__c designRec, Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            designRec.Opportunity__c = recordId;
        } else if (sObjName == 'Project__c') {
            designRec.Project__c = recordId;
        }
    }

    private static void updateOpportunityStatus(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        if (sObjName == 'Opportunity') {
            update new Opportunity(Id = recordId, Architecture_Client_Approval_Sent__c = true);
        }
    }

    private static RecipientInfo fetchRecipientDetails(Id recordId) {
        String sObjName = recordId.getSObjectType().getDescribe().getName();
        RecipientInfo info = new RecipientInfo();
        if (sObjName == 'Opportunity') { 
            Opportunity opp = [SELECT Email__c, Lead_Name__c FROM Opportunity WHERE Id = :recordId];
            if (String.isBlank(opp.Email__c)) {
                throw new AuraHandledException('No email address found on Opportunity.');
            }
            info.email = opp.Email__c;
            info.name = (opp.Lead_Name__c != null) ? opp.Lead_Name__c : 'Valued Client';
        } else if (sObjName == 'Project__c') { 
            SObject proj = Database.query('SELECT Client_Email__c FROM Project__c WHERE Id = :recordId LIMIT 1');
            String email = (String)proj.get('Client_Email__c');
            if (String.isBlank(email)) {
                throw new AuraHandledException('No email address found on Project.');
            }
            info.email = email;
            info.name = 'Valued Client';
        }
        return info;
    }

    private static void setOrgWideAddress(Messaging.SingleEmailMessage mail) {
        try {
            OrgWideEmailAddress[] owd = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :System.Label.Arelia_OWD LIMIT 1];
            if (!owd.isEmpty()) {
                mail.setOrgWideEmailAddressId(owd[0].Id);
            }
        } catch (Exception ex) { 
            System.debug('OWD Error: ' + ex.getMessage()); 
        }
    }

    private static ResolvedNames resolveNames(NotificationData data) {
        ResolvedNames names = new ResolvedNames();
        names.supervisorName = 'Enrollment Team';
        names.clientName = 'Valued Client';
        if (data.design.Opportunity__r != null) {
            if (data.design.Opportunity__r.Supervisor_User__r != null) {
                String fname = data.design.Opportunity__r.Supervisor_User__r.FirstName;
                String lname = data.design.Opportunity__r.Supervisor_User__r.LastName;
                String fullName = (fname != null ? fname + ' ' : '') + (lname != null ? lname : '');
                if (String.isNotBlank(fullName)) {
                    names.supervisorName = fullName.trim();
                }
            }
            if (data.design.Opportunity__r.Lead_Name__c != null) {
                names.clientName = data.design.Opportunity__r.Lead_Name__c;
            }
        }
        return names;
    }
}