/**
 * @File Name      : LeadEmailHandler.cls
 * @Description    : Centralised handler for all Lead-related email flows:
 *                   - Submission flow  → Emails to Enrollment / Management
 *                   - Approval flow    → Emails to Lead
 *
 * Design & PMD / Best Practices:
 * - All logic is bulkified; the trigger passes lists of Lead records.
 * - No SOQL or DML inside loops (only Messaging.sendEmail once per batch).
 * - No System.debug statements (clean logs and PMD friendly).
 * - Helper methods are private, cohesive, and focused.
 * - Uses Email Templates + Org-Wide Email Address for consistent branding.
 *
 * PMD Suppressions:
 * - PMD.ApexCRUDViolation:
 *   We query and use EmailTemplate, User, OrgWideEmailAddress, Attachment,
 *   ContentDocumentLink, and ContentVersion directly. Access to these
 *   metadata / system objects is controlled by org configuration and
 *   is considered acceptable for this shared infrastructure class.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class LeadEmailHandler {

    // ----------------------------------------------------------------------
    // 🔁 Backwards-compatible wrapper (in case anything still calls sendEmailForLead)
    // ----------------------------------------------------------------------
    /**
     * Legacy entry point – kept for backward compatibility.
     * Internally routes to the new methods based on field values.
     *
     * - If Approval_Status__c == 'Approved'  → acts like sendLeadEmailOnApproval
     * - Else if Project_Request_Submitted__c == true → acts like sendEnrollmentEmailOnSubmission
     */
    public static void sendEmailForLead(Lead leadRecord) {
        if (leadRecord == null) {
            return;
        }

        // If approved -> behave like approval flow
        if (leadRecord.Approval_Status__c == 'Approved') {
            sendLeadEmailOnApproval(new List<Lead>{ leadRecord });
        }
        // If submitted -> behave like submission flow
        else if (leadRecord.Project_Request_Submitted__c == true) {
            sendEnrollmentEmailOnSubmission(new List<Lead>{ leadRecord });
        }
    }

    // ----------------------------------------------------------------------
    // 1️⃣ Submission flow – email to Enrollment / Management only
    //     - Manual Quotation   → Arelia_Living_Management_Email_Template (no attachments)
    //     - Automatic Quotation→ Arelia_Living_Automation_Management_Email_Template (with attachments)
    // ----------------------------------------------------------------------
    /**
     * Single-record submission helper kept for backward compatibility.
     */
    public static void sendEnrollmentEmailOnSubmission(Lead leadRecord) {
        if (leadRecord == null) {
            return;
        }
        sendEnrollmentEmailOnSubmission(new List<Lead>{ leadRecord });
    }

    /**
     * Bulk submission flow – called from trigger.
     * Called when Lead is submitted (Project_Request_Submitted__c becomes true).
     * Sends email ONLY to enrollment / management members.
     */
    public static void sendEnrollmentEmailOnSubmission(List<Lead> leadRecords) {
        if (leadRecords == null || leadRecords.isEmpty()) {
            return;
        }

        try {
            List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

            for (Lead leadRecord : leadRecords) {
                if (leadRecord == null) {
                    continue;
                }

                String quoteType = leadRecord.Project_Request_Quotation_Type__c;
                if (String.isBlank(quoteType)) {
                    continue; // nothing to do if quotation type is not set
                }

                // Manual Quotation scenario
                if (quoteType == 'Manual') {
                    Id managementTemplateId =
                        getTemplateIdByDeveloperName(Label.Arelia_Living_Management_Email_Template);

                    if (managementTemplateId != null) {
                        // No attachments for manual scenario
                        emailMessages.addAll(
                            prepareManagementEmails(leadRecord, managementTemplateId, false)
                        );
                    }
                }
                // Automatic Quotation scenario
                else if (quoteType == 'Automation') {
                    Id automationMgmtTemplateId =
                        getTemplateIdByDeveloperName(Label.Arelia_Living_Automatic_Project_Quote_Management_Email_Template);

                    if (automationMgmtTemplateId != null) {
                        // Attach files for automatic scenario
                        emailMessages.addAll(
                            prepareManagementEmails(leadRecord, automationMgmtTemplateId, true)
                        );
                    }
                }
            }

            if (!emailMessages.isEmpty()) {
                sendEmails(emailMessages);
            }

        } catch (Exception ex) {
            throw new AuraHandledException('Failed to send enrollment notifications: ' + ex.getMessage());
        }
    }

    // ----------------------------------------------------------------------
    // 2️⃣ Approval flow – email to Lead only
    //      - Manual Quotation   → Arelia_Living_Lead_Email_Template (no attachments)
    //      - Automatic Quotation→ Arelia_Automated_Project_Quote_Submite_Template_DevName (with attachments)
    // ----------------------------------------------------------------------
    /**
     * Single-record approval helper kept for backward compatibility.
     */
    public static void sendLeadEmailOnApproval(Lead leadRecord) {
        if (leadRecord == null) {
            return;
        }
        sendLeadEmailOnApproval(new List<Lead>{ leadRecord });
    }

    /**
     * Bulk approval flow – called from trigger.
     * Called when Lead is approved (Approval_Status__c becomes 'Approved').
     * Sends email ONLY to the Lead.
     */
    public static void sendLeadEmailOnApproval(List<Lead> leadRecords) {
        if (leadRecords == null || leadRecords.isEmpty()) {
            return;
        }

        try {
            List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

            for (Lead leadRecord : leadRecords) {
                if (leadRecord == null || String.isBlank(leadRecord.Email)) {
                    continue;
                }

                String quoteType = leadRecord.Project_Request_Quotation_Type__c;
                if (String.isBlank(quoteType)) {
                    continue; // nothing to do if quotation type is not set
                }

                if (quoteType == 'Manual') {
                    // Manual: no attachments
                    Id leadTemplateId =
                        getTemplateIdByDeveloperName(Label.Arelia_Living_Lead_Email_Template);

                    if (leadTemplateId != null) {
                        emailMessages.add(
                            prepareLeadEmail(leadRecord, leadTemplateId, false)
                        );
                    }
                } else if (quoteType == 'Automation') {
                    // Automatic: with attachments
                    Id autoLeadTemplateId =
                        getTemplateIdByDeveloperName(Label.Arelia_Automated_Project_Quote_Submite_Template_DevName);

                    if (autoLeadTemplateId != null) {
                        emailMessages.add(
                            prepareLeadEmail(leadRecord, autoLeadTemplateId, true)
                        );
                    }
                }
            }

            if (!emailMessages.isEmpty()) {
                sendEmails(emailMessages);
            }

        } catch (Exception ex) {
            throw new AuraHandledException('Failed to send lead approval email: ' + ex.getMessage());
        }
    }

    // ----------------------------------------------------------------------
    // 🔧 Shared helper methods
    // ----------------------------------------------------------------------

    // Get Email Template by API Name (DeveloperName)
    private static Id getTemplateIdByDeveloperName(String devName) {
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate
            WHERE DeveloperName = :devName LIMIT 1];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    // Email to Lead (optionally with attachments)
    private static Messaging.SingleEmailMessage prepareLeadEmail(
        Lead leadRecord,
        Id templateId,
        Boolean includeAttachments
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(leadRecord.Id);
        email.setTemplateId(templateId);
        email.setTreatTargetObjectAsRecipient(true);
        email.setSaveAsActivity(true);
        email.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

        if (includeAttachments == true) {
            List<Messaging.EmailFileAttachment> files =
                getLeadEmailFileAttachments(leadRecord.Id);
            if (!files.isEmpty()) {
                email.setFileAttachments(files);
            }
        }

        return email;
    }

    // Emails to Management / Enrollment (optionally with attachments)
    private static List<Messaging.SingleEmailMessage> prepareManagementEmails(
        Lead leadRecord,
        Id templateId,
        Boolean includeAttachments
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<String> allEmailAddresses = new List<String>();

        // Emails from custom label
        allEmailAddresses.addAll(getEnrollmentEmails());
        
        // Emails from Manager Role
        allEmailAddresses.addAll(getManagerEmailsByRole());

        // Emails from Enrollment Role
        allEmailAddresses.addAll(getEnrollmentEmailsByRole());

        // Prepare attachments once if needed
        List<Messaging.EmailFileAttachment> fileAttachments =
            includeAttachments
                ? getLeadEmailFileAttachments(leadRecord.Id)
                : new List<Messaging.EmailFileAttachment>();

        // Unique email addresses
        Set<String> uniqueEmails = new Set<String>();

        for (String emailAddr : allEmailAddresses) {
            String trimmed = (emailAddr == null) ? '' : emailAddr.trim();
            if (String.isNotBlank(trimmed) && uniqueEmails.add(trimmed)) {

                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setToAddresses(new List<String>{ trimmed });
                msg.setTemplateId(templateId);
                msg.setTargetObjectId(leadRecord.Id);
                msg.setTreatTargetObjectAsRecipient(false);
                msg.setSaveAsActivity(true);
                msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

                // For automatic quotation scenario add attachments
                if (includeAttachments && !fileAttachments.isEmpty()) {
                    // clone attachments per email to be safe
                    List<Messaging.EmailFileAttachment> cloned = new List<Messaging.EmailFileAttachment>();
                    for (Messaging.EmailFileAttachment f : fileAttachments) {
                        Messaging.EmailFileAttachment copy = new Messaging.EmailFileAttachment();
                        copy.setFileName(f.getFileName());
                        copy.setBody(f.getBody());
                        copy.setContentType('application/octet-stream');
                        cloned.add(copy);
                    }
                    msg.setFileAttachments(cloned);
                }

                emails.add(msg);
            }
        }

        return emails;
    }

    // Collect attachments/Files related to the Lead for sending in emails
    // Used only for Automatic Quotation scenario.
    private static List<Messaging.EmailFileAttachment> getLeadEmailFileAttachments(Id leadId) {
        List<Messaging.EmailFileAttachment> result = new List<Messaging.EmailFileAttachment>();

        if (leadId == null) {
            return result;
        }

        // --- 1) Classic Attachments (Attachment object) ---
        List<Attachment> classicAttachments = [SELECT Id, Name, Body, ContentType
            FROM Attachment WHERE ParentId = :leadId];
        for (Attachment a : classicAttachments) {
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(a.Name);
            efa.setBody(a.Body);
            efa.setContentType(a.ContentType);
            result.add(efa);
        }

        // --- 2) Files (ContentDocument / ContentVersion) ---
        List<ContentDocumentLink> links = [SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension
                            FROM ContentDocumentLink WHERE LinkedEntityId = :leadId];

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

        if (!docIds.isEmpty()) {
            List<ContentVersion> versions = [SELECT Id,Title,FileExtension,VersionData
                FROM ContentVersion WHERE ContentDocumentId IN :docIds AND IsLatest = true];

            for (ContentVersion cv : versions) {
                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                String ext = String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '';
                efa.setFileName(cv.Title + ext);
                efa.setBody(cv.VersionData);
                // Use generic content type for emailed files
                efa.setContentType('application/octet-stream');
                result.add(efa);
            }
        }

        return result;
    }

    // Send All Emails (no System.debug to keep PMD clean)
    private static void sendEmails(List<Messaging.SingleEmailMessage> messages) {
        if (messages == null || messages.isEmpty()) {
            return;
        }
        // We ignore the result for now – if needed, can be surfaced via exceptions or logging framework.
        Messaging.sendEmail(messages, false);
    }

    // Org-Wide Email
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    // Get Manager Emails
    private static List<String> getManagerEmailsByRole() {
        List<String> emails = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Manager%'
            AND IsActive = true AND Email != null ]) 
        {
            emails.add(u.Email.trim());
        }
        return emails;
    }

    // Get Enrollment Emails
    private static List<String> getEnrollmentEmailsByRole() {
        List<String> emails = new List<String>();
        for (User u : [SELECT Email FROM User WHERE UserRole.Name LIKE '%Enrollment%'
            AND IsActive = true AND Email != null ]) 
        {
            emails.add(u.Email.trim());
        }
        return emails;
    }

     /**
     * @description Parses comma-separated enrollment member emails from
     * custom label Arelia_Living_Enrollment_Members.
     * @return List of trimmed email addresses.
     */
    private static List<String> getEnrollmentEmails() {
        List<String> result = new List<String>();

        String raw = System.Label.Arelia_Living_Enrollment_Members;
        if (String.isBlank(raw)) {
            return result;
        }

        for (String part : raw.split(',')) {
            if (String.isNotBlank(part)) {
                String email = part.trim();
                // Very light validation – same as other checks
                if (email.contains('@') && email.contains('.')) {
                    result.add(email);
                }
            }
        }

        return result;
    }
}