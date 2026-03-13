/**
 * @description Utility class to send approval emails for Site Visit Reports.
 * Emails are sent to management emails from a custom label using a predefined email template.
 * Also handles synchronization of status fields to parent Lead/Opportunity records.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation')
public without sharing class SiteVisitReportHandler {

    private static Id cachedOrgWideEmailId;

    /**
     * @description Sends approval notification emails for the given Site Visit Report IDs.
     * @param reportIds List of Site_Visit_Report__c record IDs
     */
    public static void sendApprovalEmails(List<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {return;}

        List<Site_Visit_Report__c> reports = fetchReportsWithDetails(reportIds);
        if (reports.isEmpty()) { return;}

        List<String> recipients = collectRecipients();
        if (recipients.isEmpty()) {return;}

        Map<String, EmailTemplate> templates = getEmailTemplatesMap();
        List<Messaging.SingleEmailMessage> emails = buildEmailMessages(reports, recipients, templates);

        if (!emails.isEmpty()) {
            sendEmailBatch(emails);
        }
    }

    // -------------------------------------------------------------------------
    // Data Retrieval Helpers
    // -------------------------------------------------------------------------

    private static List<Site_Visit_Report__c> fetchReportsWithDetails(List<Id> reportIds) {
        return [SELECT Id, Name, Site_Visit_Date__c, Site_Visit_Time_Slot__c, Site_Visit_Report_Status__c,
                   Estimated_Completion_Date__c, Estimated_Completion_Months__c, Total_Estimated_Cost__c,
                   Opportunity__c, Opportunity__r.Name,Negotiate__c,Negotation_Reason__c,
                   Supervisor_User__r.Name, Supervisor_User__r.Phone,
                   Lead__r.FirstName, Lead__r.LastName, Lead__r.Email, Lead__r.Phone, Lead__r.Company,
                   Lead__r.Estimated_Start_Date__c, Lead__r.Status, Lead__r.Approval_Status__c,
                   RecordType.DeveloperName FROM Site_Visit_Report__c WHERE Id IN :reportIds];
    }

    private static List<String> collectRecipients() {
        List<String> addresses = new List<String>();
        addresses.addAll(getManagerEmailsByRole());
        addresses.addAll(getManagementEmails());
        return addresses;
    }

    private static Map<String, EmailTemplate> getEmailTemplatesMap() {
        Map<String, EmailTemplate> templateMap = new Map<String, EmailTemplate>();
        Set<String> neededTemplates = new Set<String>{
            Label.Arelia_Living_Opportunity_Re_Visit_Site_Manager_Approval_Email_Template,
            Label.Arelia_Living_Lead_Conversion_Approval_Email_Template,
            Label.Arelia_Living_Lead_Site_Manager_Review_Approval_Email_Template,
            Label.Arelia_Living_Opportunity_Site_Manager_Review_Approval_Email_Template

        };

        List<EmailTemplate> templates = [SELECT Id, DeveloperName, Subject, HtmlValue
            FROM EmailTemplate WHERE DeveloperName IN :neededTemplates];

        for (EmailTemplate et : templates) {
            templateMap.put(et.DeveloperName, et);
        }
        return templateMap;
    }

    // -------------------------------------------------------------------------
    // Email Construction
    // -------------------------------------------------------------------------

    private static List<Messaging.SingleEmailMessage> buildEmailMessages(List<Site_Visit_Report__c> reports,
                        List<String> recipients,Map<String, EmailTemplate> templates)
    {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Site_Visit_Report__c report : reports) {

            // ✅ Identify “Negotiation second-time approval”
            Boolean isNegotiationReapproval = report.Negotiate__c == true && String.isNotBlank(report.Negotation_Reason__c);
            String templateName;

            // ✅ If negotiation is present, send a DIFFERENT template
            if (isNegotiationReapproval) {
                templateName = (report.RecordType.DeveloperName == 'Opportunity_Site_Visit_Report')
                    ? Label.Arelia_Living_Opportunity_Site_Manager_Review_Approval_Email_Template
                    : Label.Arelia_Living_Lead_Site_Manager_Review_Approval_Email_Template;

            } else {
                // ✅ Existing “first-time approval” templates (your current logic)
                templateName = (report.RecordType.DeveloperName == 'Opportunity_Site_Visit_Report')
                    ? Label.Arelia_Living_Opportunity_Re_Visit_Site_Manager_Approval_Email_Template
                    : Label.Arelia_Living_Lead_Conversion_Approval_Email_Template;
            }
            EmailTemplate selectedTemplate = templates.get(templateName);
            if (selectedTemplate != null) {
                emails.add(createSingleEmail(report, recipients, selectedTemplate));
            }
        }

        return emails;
    }


    private static Messaging.SingleEmailMessage createSingleEmail(Site_Visit_Report__c report,
        List<String> recipients, EmailTemplate template)
    {
        String htmlBody = populateTemplate(template.HtmlValue, report);
        String subject = populateSubject(template.Subject, report);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(recipients);

        Id owdId = getOrgWideEmailAddressId();
        if (owdId != null) {
            email.setOrgWideEmailAddressId(owdId);
        }
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setSaveAsActivity(true);

        List<Messaging.EmailFileAttachment> reportFiles = getReportEmailAttachments(report.Id);
        if (!reportFiles.isEmpty()) {
            email.setFileAttachments(reportFiles);
        }
        return email;
    }

    private static void sendEmailBatch(List<Messaging.SingleEmailMessage> emails) {
        if (emails == null || emails.isEmpty()) { return; }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
        // If any failed, throw one error so you can see it in debug logs
        for (Messaging.SendEmailResult r : results) {
            if (!r.isSuccess()) {
                String msg = (r.getErrors() != null && !r.getErrors().isEmpty())
                    ? r.getErrors()[0].getMessage()
                    : 'Unknown email error';
                throw new AuraHandledException('Email failed: ' + msg);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Utilities & Formatting
    // -------------------------------------------------------------------------

    private static List<String> getManagementEmails() {
        String mgmtEmails = Label.Arelia_Living_Enrollment_Members;
        List<String> emails = new List<String>();
        if (String.isNotBlank(mgmtEmails)) {
            for (String email : mgmtEmails.split(',')) {
                if (String.isNotBlank(email)) {
                    emails.add(email.trim());
                }
            }
        }
        return emails;
    }

    private static List<String> getManagerEmailsByRole() {
        List<String> managerEmails = new List<String>();
        for (User u : [
            SELECT Email FROM User
            WHERE UserRole.Name LIKE '%Manager%' AND IsActive = true AND Email != null
        ]) {
            managerEmails.add(u.Email.trim());
        }
        return managerEmails;
    }

    private static Id getOrgWideEmailAddressId() {
        if (cachedOrgWideEmailId != null) {
            return cachedOrgWideEmailId;
        }
        List<OrgWideEmailAddress> addresses = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD
            LIMIT 1
        ];
        if (!addresses.isEmpty()) {
            cachedOrgWideEmailId = addresses[0].Id;
        }
        return cachedOrgWideEmailId;
    }

    private static List<Messaging.EmailFileAttachment> getReportEmailAttachments(Id reportId) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :reportId 
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }

        if (!docIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, Title, FileExtension, VersionData FROM ContentVersion
                WHERE ContentDocumentId IN :docIds AND IsLatest = true 
            ]) {
                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                efa.setFileName(cv.Title + '.' + cv.FileExtension);
                efa.setBody(cv.VersionData);
                attachments.add(efa);
            }
        }

        for (Attachment att : [
            SELECT Id, Name, Body FROM Attachment WHERE ParentId = :reportId 
        ]) {
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(att.Name);
            efa.setBody(att.Body);
            attachments.add(efa);
        }

        return attachments;
    }

    private static String populateTemplate(String templateHtml, Site_Visit_Report__c report) {
        if (templateHtml == null) { return ''; }
        String link = Label.Arelia_Site_Label + 'detail/' + report.Id;

        return templateHtml
            .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(report.Supervisor_User__r?.Name))
            .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Phone}}}', safeString(report.Supervisor_User__r?.Phone))
            .replace('{{{Site_Visit_Report__c.Lead__r.FirstName}}}', safeString(report.Lead__r?.FirstName))
            .replace('{{{Site_Visit_Report__c.Lead__r.LastName}}}', safeString(report.Lead__r?.LastName))
            .replace('{{{Site_Visit_Report__c.Lead__r.Email}}}', safeString(report.Lead__r?.Email))
            .replace('{{{Site_Visit_Report__c.Lead__r.Phone}}}', safeString(report.Lead__r?.Phone))
            .replace('{{{Site_Visit_Report__c.Lead__r.Company}}}', safeString(report.Lead__r?.Company))
            .replace('{{{Site_Visit_Report__c.Lead__r.Estimated_Start_Date__c}}}', formatDate(report.Lead__r?.Estimated_Start_Date__c))
            .replace('{{{Site_Visit_Report__c.Lead__r.Status}}}', safeString(report.Lead__r?.Status))
            .replace('{{{Site_Visit_Report__c.Lead__r.Approval_Status__c}}}', safeString(report.Lead__r?.Approval_Status__c))
            .replace('{{{Site_Visit_Report__c.Opportunity__r.Name}}}', safeString(report.Opportunity__r?.Name))
            .replace('{{{Site_Visit_Report__c.Name}}}', safeString(report.Name))
            .replace('{{{SiteVisitReportId}}}', safeString(report.Id))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Date__c}}}', formatDate(report.Site_Visit_Date__c))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Time_Slot__c}}}', safeString(report.Site_Visit_Time_Slot__c))
            .replace('{{{Site_Visit_Report__c.Site_Visit_Report_Status__c}}}', safeString(report.Site_Visit_Report_Status__c))
            .replace('{{{Site_Visit_Report__c.Estimated_Completion_Date__c}}}', formatDate(report.Estimated_Completion_Date__c))
            .replace('{{{Site_Visit_Report__c.Estimated_Completion_Months__c}}}', safeString(report.Estimated_Completion_Months__c))
            .replace('{{{Site_Visit_Report__c.Total_Estimated_Cost__c}}}', safeString(report.Total_Estimated_Cost__c))
            .replace('{{{Site_Visit_Report__c.Negotiate__c}}}', safeString(report.Negotiate__c))
            .replace('{{{Site_Visit_Report__c.Negotation_Reason__c}}}', safeString(report.Negotation_Reason__c))
            .replace('{{{siteVisitRecordPageLink}}}', link);
    }

    private static String populateSubject(String subject, Site_Visit_Report__c report) {
        if (subject == null) { return ''; }
        return subject.replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(report.Supervisor_User__r?.Name));
    }

    private static String safeString(Object obj) {
        return obj != null ? String.valueOf(obj) : '';
    }

    private static String formatDate(Date dt) {
        return dt != null ? dt.format() : '';
    }

    // -------------------------------------------------------------------------
    // Trigger Handlers
    // -------------------------------------------------------------------------

    /**
     * @description Handles logic for After Insert trigger event.
     * @param newList List of new Site_Visit_Report__c records.
     */
    public static void afterInsert(List<Site_Visit_Report__c> newList) {
        if (newList == null || newList.isEmpty()) { return; }
        for (Site_Visit_Report__c svr : newList) {
            if (svr != null) {
                SiteVisitReportFileService.attachFilesToLead(svr.Id);
            }
        }
    }

    /**
     * @description Handles logic for After Update trigger event.
     * @param newList List of updated records.
     * @param oldMap Map of old records by ID.
     */

    public static void afterUpdate(List<Site_Visit_Report__c> newList, Map<Id, Site_Visit_Report__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) { return; }

        List<Site_Visit_Report__c> reportsForSync = new List<Site_Visit_Report__c>();
        Set<Id> emailReportIds = new Set<Id>();

        for (Site_Visit_Report__c newRec : newList) {
            if (newRec == null) { continue; }
            Site_Visit_Report__c oldRec = oldMap.get(newRec.Id);

            // 1. Files (unchanged)
            SiteVisitReportFileService.attachFilesToLead(newRec.Id);

            // 2. Sync candidates (unchanged)
            if (isSyncRequired(newRec, oldRec)) {
                reportsForSync.add(newRec);
            }

            // 3. ✅ Email candidates (FIXED)
            if (oldRec != null && shouldSendManagerEmail(newRec, oldRec)) {
                emailReportIds.add(newRec.Id);
            }
        }

        if (!reportsForSync.isEmpty()) {
            syncParentsFromReports(reportsForSync);
        }

        if (!emailReportIds.isEmpty()) {
            SiteVisitReportHandler.sendApprovalEmails(new List<Id>(emailReportIds));
        }

        // Part 4 (unchanged)
        SiteVisitApprovalController.handleAfterUpdate(newList, oldMap);
    }

    private static Boolean shouldSendManagerEmail(Site_Visit_Report__c n, Site_Visit_Report__c o) {
        // A) First time approved (existing behavior)
        Boolean firstTimeApproved =
            n.Site_Visit_Report_Status__c == 'Approved' &&
            o.Site_Visit_Report_Status__c != 'Approved';

        // B) Negotiation re-approval email:
        //    status is already Approved, but negotiation checkbox/reason changed
        Boolean negotiationNowPresent =
            n.Negotiate__c == true &&
            String.isNotBlank(n.Negotation_Reason__c); // <-- change if your API name differs

        Boolean negotiationChanged =
            (n.Negotiate__c != o.Negotiate__c) ||
            (n.Negotation_Reason__c != o.Negotation_Reason__c); // <-- change if your API name differs

        Boolean negotiationReApproval =
            (n.Site_Visit_Report_Status__c == 'Approved') &&
            negotiationNowPresent &&
            negotiationChanged;

        return firstTimeApproved || negotiationReApproval;
    }


    private static Boolean isSyncRequired(Site_Visit_Report__c newRec, Site_Visit_Report__c oldRec) {
        Boolean statusChanged = (oldRec == null)
            ? String.isNotBlank(newRec.Site_Visit_Report_Status__c)
            : newRec.Site_Visit_Report_Status__c != oldRec.Site_Visit_Report_Status__c;

        Boolean estChanged = (oldRec == null)
            ? String.isNotBlank(newRec.Estimated_Completion_Months__c)
            : newRec.Estimated_Completion_Months__c != oldRec.Estimated_Completion_Months__c;

        Boolean dateChanged = (oldRec == null)
            ? (newRec.Estimated_Completion_Date__c != null)
            : (newRec.Estimated_Completion_Date__c != oldRec.Estimated_Completion_Date__c);

        return (statusChanged || estChanged || dateChanged);
    }

    // -------------------------------------------------------------------------
    // Parent Sync Logic
    // -------------------------------------------------------------------------

    private static void syncParentsFromReports(List<Site_Visit_Report__c> reports) {
        if (reports == null || reports.isEmpty()) { return; }

        Map<Id, String> rtMap = getRecordTypeDeveloperNames(reports);
        List<Site_Visit_Report__c> leadReports = new List<Site_Visit_Report__c>();
        List<Site_Visit_Report__c> oppReports = new List<Site_Visit_Report__c>();

        // Separate reports by parent type to flatten logic
        for (Site_Visit_Report__c r : reports) {
            if (r == null || String.isBlank(r.Site_Visit_Report_Status__c)) { continue; }
            String rtName = rtMap.get(r.RecordTypeId);

            if (rtName == 'Opportunity_Site_Visit_Report') {
                oppReports.add(r);
            } else {
                leadReports.add(r);
            }
        }

        updateLeads(leadReports);
        updateOpportunities(oppReports);
    }

    private static Map<Id, String> getRecordTypeDeveloperNames(List<Site_Visit_Report__c> reports) {
        Set<Id> rtIds = new Set<Id>();
        for (Site_Visit_Report__c r : reports) {
            if (r.RecordTypeId != null) { rtIds.add(r.RecordTypeId); }
        }
        Map<Id, String> rtMap = new Map<Id, String>();
        if (!rtIds.isEmpty()) {
            for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :rtIds ]) {
                rtMap.put(rt.Id, rt.DeveloperName);
            }
        }
        return rtMap;
    }

    private static void updateLeads(List<Site_Visit_Report__c> reports) {
        if (reports.isEmpty()) { return; }
        Map<Id, Lead> leadMap = new Map<Id, Lead>();

        for (Site_Visit_Report__c r : reports) {
            if (r.Lead__c != null) {
                leadMap.put(r.Lead__c, new Lead(
                    Id = r.Lead__c,
                    Site_Visit_Status__c = r.Site_Visit_Report_Status__c,
                    Project_Estimated_Completion_Months__c = r.Estimated_Completion_Months__c,
                    Project_End_Date_by_Supervisor__c = r.Estimated_Completion_Date__c
                ));
            }
        }
        if (!leadMap.isEmpty()) {
            try {
                Database.update(leadMap.values());
            } catch (Exception ex) {
                 System.debug('Exception occurred: ' + ex.getMessage());
            }
        }
    }

    private static void updateOpportunities(List<Site_Visit_Report__c> reports) {
        if (reports.isEmpty()) { return; }
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();

        for (Site_Visit_Report__c r : reports) {
            if (r.Opportunity__c != null) {
                oppMap.put(r.Opportunity__c, new Opportunity(
                    Id = r.Opportunity__c,
                    Re_Visit_Site_Status__c = r.Site_Visit_Report_Status__c,
                    ReVisit_Site_Estimated_Completion_Months__c = r.Estimated_Completion_Months__c,
                    Re_Visit_Site_Supervisor_Completion_Date__c = r.Estimated_Completion_Date__c
                ));
            }
        }
        if (!oppMap.isEmpty()) {
            try {
                Database.update(oppMap.values());
            } catch (Exception ex) {
                 System.debug('Exception occurred: ' + ex.getMessage());
            }
        }
    }
}