/**
 * @description  Sends a supervisor reminder email (once) for Invoice__c
 *               after file(s) are uploaded to the Invoice (Salesforce Files).
 *
 * Best practices:
 * - Bulkified (no SOQL/DML in loops)
 * - Guard clauses to reduce complexity
 * - Uses EmailTemplate (DeveloperName from Custom Label)
 * - Uses token replacement with clean tokens: {{{invoiceName}}}, {{{grandTotal}}}, etc.
 * - Sends plain text (removes any HTML tags from template HtmlValue)
 * - Marks Invoice_Sent__c only after successful send
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class InvoiceEmailHandler {

    /** Email Template DeveloperName stored in Custom Label */
    private static final String TEMPLATE_DEV_NAME = System.Label.Proforma_Invoice_Sent_To_Supervisor;

    /** Optional status gate. Keep blank to ignore status logic. */
    private static final String TARGET_STATUS = '';

    /** Max number of file attachments per email to avoid limits */
    private static final Integer MAX_ATTACHMENTS = 10;

    /**
     * @description Entry point called from InvoiceTrigger (after insert/update).
     */
    public static void sendInvoiceEmailOnce(List<Invoice__c> newList,
        Map<Id, Invoice__c> oldMap,Boolean isInsert,Boolean isUpdate)
    {
        Set<Id> candidateIds = collectCandidateInvoiceIds(newList, oldMap, isUpdate);
        if (candidateIds.isEmpty()) {return;}

        EmailTemplate template = fetchTemplateByDeveloperName(TEMPLATE_DEV_NAME);
        if (template == null) {return;}

        Map<Id, Invoice__c> invById = fetchInvoices(candidateIds);
        if (invById.isEmpty()) {return;}

        Map<Id, List<Messaging.EmailFileAttachment>> attachmentsByInv =
            buildAttachmentsByInvoice(candidateIds);

        // Send only after upload (must have at least one file for at least one invoice)
        if (attachmentsByInv.isEmpty()) {return;}

        EmailBuildResult build = buildEmails(invById, attachmentsByInv, template);
        if (build.emails.isEmpty()) {return;}

        Messaging.SendEmailResult[] results = Messaging.sendEmail(build.emails, false);

        List<Invoice__c> successUpdates = buildSuccessUpdates(results, build.updatesInEmailOrder);
        if (!successUpdates.isEmpty()) {
            update successUpdates;
        }
    }

    // ============================================================
    // 1) Candidate invoice selection
    // ============================================================

    /**
     * @description Collect invoices that are eligible to send (only once).
     *              Applies optional status gating if TARGET_STATUS is set.
     */
    private static Set<Id> collectCandidateInvoiceIds(List<Invoice__c> newList,
        Map<Id, Invoice__c> oldMap, Boolean isUpdate)
    {
        Set<Id> ids = new Set<Id>();
        if (newList == null || newList.isEmpty()) {return ids;}

        for (Invoice__c inv : newList) {
            if (inv == null || inv.Id == null) {continue;}
            if (inv.Invoice_Sent__c) {continue;} // already sent

            // Optional: send only for target status
            if (!String.isBlank(TARGET_STATUS) && String.valueOf(inv.Status__c) != TARGET_STATUS) {
                continue;
            }

            // Optional: on update, require status changed to target
            if (isUpdate && !String.isBlank(TARGET_STATUS) && oldMap != null && oldMap.containsKey(inv.Id)) {
                Invoice__c oldInv = oldMap.get(inv.Id);
                if (oldInv != null && String.valueOf(oldInv.Status__c) == TARGET_STATUS) {
                    continue;
                }
            }

            ids.add(inv.Id);
        }
        return ids;
    }

    // ============================================================
    // 2) Fetch template
    // ============================================================

    /**
     * @description Fetch EmailTemplate by DeveloperName.
     */
    private static EmailTemplate fetchTemplateByDeveloperName(String devName) {
        if (String.isBlank(devName)) {return null;}

        List<EmailTemplate> tpls = [SELECT Id, DeveloperName, Subject, HtmlValue, Body
                    FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
        return tpls.isEmpty() ? null : tpls[0];
    }

    // ============================================================
    // 3) Fetch invoice data
    // ============================================================

    /**
     * @description Fetch Invoice + Supervisor + Primary Contact data for token replacement.
     */
    private static Map<Id, Invoice__c> fetchInvoices(Set<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {return new Map<Id, Invoice__c>();}

        List<Invoice__c> invoices = [SELECT Id, Name, Grand_Total__c, Invoice_Sent__c, Status__c,
                    Opportunity__c,Opportunity__r.Name, Opportunity__r.Primary_Contact__r.Name,
                    Opportunity__r.Supervisor_User__r.FirstName, Opportunity__r.Supervisor_User__r.LastName,
                    Opportunity__r.Supervisor_User__r.Email FROM Invoice__c WHERE Id IN :invoiceIds];

        return new Map<Id, Invoice__c>(invoices);
    }

    // ============================================================
    // 4) Build file attachments
    // ============================================================

    /**
     * @description Build attachments from Salesforce Files linked to invoices.
     *              Uses ContentDocumentLink -> latest ContentVersion.
     */
    private static Map<Id, List<Messaging.EmailFileAttachment>> buildAttachmentsByInvoice(Set<Id> invoiceIds) {
        Map<Id, List<Messaging.EmailFileAttachment>> out = new Map<Id, List<Messaging.EmailFileAttachment>>();
        if (invoiceIds == null || invoiceIds.isEmpty()) {return out;}

        List<ContentDocumentLink> links = [SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink WHERE LinkedEntityId IN :invoiceIds];

        Map<Id, Set<Id>> docIdsByInv = new Map<Id, Set<Id>>();
        Set<Id> allDocIds = new Set<Id>();

        for (ContentDocumentLink l : links) {
            if (l == null || l.LinkedEntityId == null || l.ContentDocumentId == null) {continue;}

            if (!docIdsByInv.containsKey(l.LinkedEntityId)) {
                docIdsByInv.put(l.LinkedEntityId, new Set<Id>());
            }
            docIdsByInv.get(l.LinkedEntityId).add(l.ContentDocumentId);
            allDocIds.add(l.ContentDocumentId);
        }

        if (allDocIds.isEmpty()) {return out;}

        List<ContentVersion> versions = [SELECT ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion WHERE IsLatest = true AND ContentDocumentId IN :allDocIds];

        Map<Id, ContentVersion> latestByDocId = new Map<Id, ContentVersion>();
        for (ContentVersion v : versions) {
            if (v != null && v.ContentDocumentId != null) {
                latestByDocId.put(v.ContentDocumentId, v);
            }
        }

        for (Id invId : docIdsByInv.keySet()) {
            List<Messaging.EmailFileAttachment> files = new List<Messaging.EmailFileAttachment>();
            Integer added = 0;

            for (Id docId : docIdsByInv.get(invId)) {
                if (added >= MAX_ATTACHMENTS) {break;}

                ContentVersion cv = latestByDocId.get(docId);
                if (cv == null || cv.VersionData == null) {continue;}

                files.add(toAttachment(cv));
                added++;
            }

            if (!files.isEmpty()) {
                out.put(invId, files);
            }
        }

        return out;
    }

    private static Messaging.EmailFileAttachment toAttachment(ContentVersion cv) {
        Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();

        String title = String.isBlank(cv.Title) ? 'InvoiceFile' : cv.Title;
        String ext = String.isBlank(cv.FileExtension) ? '' : ('.' + cv.FileExtension);

        efa.setFileName(title + ext);
        efa.setBody(cv.VersionData);
        return efa;
    }

    // ============================================================
    // 5) Build emails from template + replacements
    // ============================================================

    private static EmailBuildResult buildEmails(Map<Id, Invoice__c> invById,
        Map<Id, List<Messaging.EmailFileAttachment>> attachmentsByInv,
        EmailTemplate template)
    {
        EmailBuildResult res = new EmailBuildResult();

        for (Id invId : invById.keySet()) {
            Invoice__c inv = invById.get(invId);
            if (inv == null) {continue;}

            if (!attachmentsByInv.containsKey(invId)) {continue;} // only after file uploaded

            String supervisorEmail = getSupervisorEmail(inv);
            if (String.isBlank(supervisorEmail)) {continue;}

            String subj = applyTokens(getTemplateSubject(template), inv);
            String body = applyTokens(getTemplateBody(template), inv);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ supervisorEmail });
            msg.setSubject(subj);
            msg.setHtmlBody(body);
            msg.setFileAttachments(attachmentsByInv.get(invId));
            msg.setSaveAsActivity(true);
            msg.setWhatId(invId);
            msg.setTreatTargetObjectAsRecipient(false);
            msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

            res.emails.add(msg);
            res.updatesInEmailOrder.add(new Invoice__c(Id = invId, Invoice_Sent__c = true));
        }

        return res;
    }

    /**
     * @description Gets Org-Wide Email Address ID used for outbound emails.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    private static String getTemplateSubject(EmailTemplate template) {
        return (template == null || template.Subject == null) ? '' : template.Subject;
    }

    private static String getTemplateBody(EmailTemplate template) {
        if (template == null) {return '';}
        if (!String.isBlank(template.HtmlValue)) {return template.HtmlValue;}
        return template.Body == null ? '' : template.Body;
    }

    /**
     * @description Applies clean tokens to subject/body.
     * Tokens expected in template:
     *  - {{{supervisorName}}}
     *  - {{{primaryContactName}}}
     *  - {{{invoiceName}}}
     *  - {{{opportunityName}}}
     *  - {{{grandTotal}}}
     */
    private static String applyTokens(String src, Invoice__c inv) {
        if (String.isBlank(src) || inv == null) {return String.valueOf(src);}

        String supervisorName = getSupervisorName(inv);
        String primaryContactName = getPrimaryContactName(inv);
        String invoiceName = inv.Name == null ? '' : inv.Name;
        String opportunityName = getOpportunityName(inv);
        String grandTotal = inv.Grand_Total__c == null ? '0' : String.valueOf(inv.Grand_Total__c);

        String out = src;
        out = out.replace('{{{supervisorName}}}', supervisorName);
        out = out.replace('{{{primaryContactName}}}', primaryContactName);
        out = out.replace('{{{invoiceName}}}', invoiceName);
        out = out.replace('{{{opportunityName}}}', opportunityName);
        out = out.replace('{{{grandTotal}}}', grandTotal);

        return out;
    }

    private static String getSupervisorEmail(Invoice__c inv) {
        if (inv == null || inv.Opportunity__r == null || inv.Opportunity__r.Supervisor_User__r == null) {return null;}
        return inv.Opportunity__r.Supervisor_User__r.Email;
    }

    private static String getSupervisorName(Invoice__c inv) {
        if (inv == null || inv.Opportunity__r == null || inv.Opportunity__r.Supervisor_User__r == null) {return '';}
        return joinName(inv.Opportunity__r.Supervisor_User__r.FirstName, inv.Opportunity__r.Supervisor_User__r.LastName);
    }

    private static String getPrimaryContactName(Invoice__c inv) {
        if (inv == null || inv.Opportunity__r == null || inv.Opportunity__r.Primary_Contact__r == null) {return '';}
        return inv.Opportunity__r.Primary_Contact__r.Name;
    }

    private static String getOpportunityName(Invoice__c inv) {
        if (inv == null || inv.Opportunity__r == null) {return '';}
        return inv.Opportunity__r.Name;
    }

    private static String joinName(String first, String last) {
        String f = String.isBlank(first) ? '' : first.trim();
        String l = String.isBlank(last) ? '' : last.trim();
        return (f + ' ' + l).trim();
    }

    // ============================================================
    // 7) Update only successful sends
    // ============================================================

    private static List<Invoice__c> buildSuccessUpdates(
        Messaging.SendEmailResult[] results,
        List<Invoice__c> updatesInOrder
    ) {
        List<Invoice__c> out = new List<Invoice__c>();
        if (results == null || updatesInOrder == null) {return out;}

        Integer n = Math.min(results.size(), updatesInOrder.size());
        for (Integer i = 0; i < n; i++) {
            if (results[i] != null && results[i].isSuccess()) {
                out.add(updatesInOrder[i]);
            }
        }
        return out;
    }

    /**
     * @description Simple wrapper to keep email + update order aligned.
     */
    private class EmailBuildResult {
        public List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        public List<Invoice__c> updatesInEmailOrder = new List<Invoice__c>();
    }
}