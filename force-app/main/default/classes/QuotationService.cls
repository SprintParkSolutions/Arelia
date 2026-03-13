/**
 * @description Service class for Quotation approvals.
 * Run as "without sharing" to allow Guest Users to update records in System Mode.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
 public without sharing class QuotationService {
    
    // --- PART A: CALLED BY INTERNAL USER ("SEND FOR APPROVAL" BUTTON) ---
    
    @InvocableMethod(
        label='Send Quote Approval Email'
        description='Sends email with Project Specifications PDF'
    )
    public static void sendApprovalEmail(List<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }
        Id oppId = oppIds[0];

        // 1. Fetch Opportunity Info + Supervisor Details (Owner)
        Opportunity opp = [SELECT Id, Name, Owner.Name, Owner.Email
                FROM Opportunity WHERE Id = :oppId LIMIT 1];

        // --- EMAIL LOGIC ---
        String labelValue = System.Label.Arelia_Living_Enrollment_Members;
        List<String> targetEmails = new List<String>();

        if (String.isNotBlank(labelValue)) {
            for (String email : labelValue.split(',')) {
                targetEmails.add(email.trim());
            }
        }
        
        if (targetEmails.isEmpty()) {
            System.debug('Error: No email addresses found in Custom Label');
            return;
        }

        // 2. Fetch Latest Quotation
        List<Quotation__c> quotes = [SELECT Id, Name FROM Quotation__c
                WHERE Opportunity__c = :oppId ORDER BY CreatedDate DESC LIMIT 1];
        
        if (quotes.isEmpty()) {
            return;
        }
        Quotation__c quote = quotes[0];

        // 3. Load Template
        EmailTemplate et = [SELECT HtmlValue, Subject FROM EmailTemplate
            WHERE DeveloperName =: System.Label.Arelia_Living_Quotation_Manager_Approval LIMIT 1];

        String htmlBody = et.HtmlValue;
        
        // Replace Placeholders
        htmlBody = htmlBody.replace('[OPPORTUNITY_NAME]', opp.Name);
        
        // Inject Supervisor Details (using Owner details)
        String supervisorName = (opp.Owner.Name != null) ? opp.Owner.Name : 'N/A';
        String supervisorEmail = (opp.Owner.Email != null) ? opp.Owner.Email : '';
        
        htmlBody = htmlBody.replace('[PROJECT_SUPERVISOR_NAME]', supervisorName);
        htmlBody = htmlBody.replace('[PROJECT_SUPERVISOR_EMAIL]', supervisorEmail);

        // Generate Link
        String siteBaseUrl = System.Label.Arelia_Site_Label;
        String siteUrl = siteBaseUrl + System.Label.Quotation_Approval_Page + '?id=' + quote.Id;

        htmlBody = htmlBody.replace('[APPROVAL_LINK_URL]', siteUrl);

        // 4. Build Email
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(targetEmails);
        
        // *** UPDATED SUBJECT LINE TO USE OPPORTUNITY NAME ***
        mail.setSubject('Project Specifications Approval: ' + opp.Name);
        
        mail.setHtmlBody(htmlBody);
        
        Id owdId = getOWD();
        if (owdId != null) {
            mail.setOrgWideEmailAddressId(owdId);
        }

        // 5. ATTACH PDF FROM FILES
        List<ContentDocumentLink> docLinks = [SELECT ContentDocumentId FROM ContentDocumentLink 
                WHERE LinkedEntityId = :quote.Id AND ContentDocument.FileType = 'PDF'
                ORDER BY ContentDocument.CreatedDate DESC LIMIT 1];

        if (!docLinks.isEmpty()) {
            ContentVersion cv = [SELECT Title, FileExtension, VersionData 
                    FROM ContentVersion WHERE ContentDocumentId = :docLinks[0].ContentDocumentId 
                    AND IsLatest = true LIMIT 1];

            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(cv.Title + '.' + cv.FileExtension);
            efa.setBody(cv.VersionData);
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ efa });
        }

        // 6. Send Email
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    // --- PART B: CALLED BY GUEST USER (PUBLIC SITE) ---

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void processRejection(Id quoteId, String reason) {
        if (quoteId == null) {return;}

        Quotation__c q = [SELECT Id, Rejection_Reason__c FROM Quotation__c WHERE Id = :quoteId LIMIT 1];
        q.Rejection_Reason__c = reason;
        q.Manager_Approval__c = false;
        update q;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void processApproval(Id quoteId) {
        if (quoteId == null) {return;}

        Quotation__c q = [SELECT Id, Manager_Approval__c FROM Quotation__c 
                                WHERE Id = :quoteId LIMIT 1];
        q.Manager_Approval__c = true;
        update q;
    }

    private static Id getOWD() {
        List<OrgWideEmailAddress> ow = [SELECT Id FROM OrgWideEmailAddress 
                                    WHERE IsAllowAllProfiles = true LIMIT 1];
        return ow.isEmpty() ? null : ow[0].Id;
    }
}