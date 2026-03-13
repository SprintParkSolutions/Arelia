/**
 * @description
 * Controller to handle AFTER UPDATE automation for Site_Visit_Report__c.
 * Detects transitions to:
 *  - Management_Approval__c = true (from false)
 *  - Negotiate__c          = true (from false)
 * Then emails the Supervisor_User__c using Classic Email Templates (HTML/Body).
 *
 * @notes
 * - Trigger/handler should call handleAfterUpdate(...) in AFTER UPDATE context only.
 * - Logic is bulk-safe (List/Map) and performs 1 query for reports + 1 query for templates.
 * - Manual merge is used (string replace) because template rendering is not used here.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation, PMD.NcssMethodCount')
public without sharing class SiteVisitApprovalController {

    /* ===============================
       CONSTANTS / DEFAULTS
    =============================== */
    private static final String DEFAULT_SUBJECT = 'Site Visit Update';

    /**
     * @description
     * Trigger entry method for AFTER UPDATE.
     * - Compares Trigger.new vs Trigger.oldMap.
     * - Detects the specific transitions (false->true) for approval/negotiation flags.
     * - Delegates email send to sendEmailsToSupervisors(...) only if needed.
     *
     * @param newList  Trigger.new list (bulk)
     * @param oldMap   Trigger.oldMap (bulk)
     */
    public static void handleAfterUpdate(
        List<Site_Visit_Report__c> newList,
        Map<Id, Site_Visit_Report__c> oldMap
    ) {
        // Guard: Bulk-safe defensive checks
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        // Collect only those records that changed into the "action" states.
        List<Site_Visit_Report__c> reportsToProcess = new List<Site_Visit_Report__c>();

        for (Site_Visit_Report__c newRec : newList) {
            if (newRec == null || newRec.Id == null) {
                continue;
            }

            Site_Visit_Report__c oldRec = oldMap.get(newRec.Id);
            if (oldRec == null) {
                continue;
            }

            // Detect false->true transitions only.
            Boolean managerApprovedNow =
                !safeBool(oldRec.Management_Approval__c) && safeBool(newRec.Management_Approval__c);

            Boolean negotiatedNow =
    !safeBool(oldRec.Negotiate__c) && safeBool(newRec.Negotiate__c);

// ✅ NEW: fire again when reason changes while negotiate=true
Boolean negotiationReasonChanged =
    safeBool(newRec.Negotiate__c) &&
    (String.valueOf(oldRec.Negotation_Reason__c) != String.valueOf(newRec.Negotation_Reason__c)) &&
    String.isNotBlank(newRec.Negotation_Reason__c);

if (managerApprovedNow || negotiatedNow || negotiationReasonChanged) {
    reportsToProcess.add(newRec);
}

        }

        // Delegate to email sender only when there is something to process.
        if (!reportsToProcess.isEmpty()) {
            sendEmailsToSupervisors(reportsToProcess);
        }
    }

    /**
     * @description
     * Sends supervisor notification emails for the provided reports.
     *
     * Steps:
     *  1) Collect report Ids.
     *  2) Query the full report data needed for merges and supervisor email.
     *  3) Read template keys from Custom Labels.
     *  4) Query Classic templates by DeveloperName OR Name.
     *  5) For each report, pick correct template, do manual merge, enqueue email.
     *  6) Send emails in one call.
     *
     * @param reports Minimal list from trigger context (may not contain all fields required).
     */
    private static void sendEmailsToSupervisors(List<Site_Visit_Report__c> reports) {
        if (reports == null || reports.isEmpty()) {
            return;
        }

        // Collect Ids for a single bulk query.
        Set<Id> reportIds = new Set<Id>();
        for (Site_Visit_Report__c r : reports) {
            if (r != null && r.Id != null) {
                reportIds.add(r.Id);
            }
        }
        if (reportIds.isEmpty()) {
            return;
        }

        // Query complete data required for email composition.
        // NOTE: This preserves your original field list.
        List<Site_Visit_Report__c> fullReports = [
            SELECT Id, Name,
                   Management_Approval__c, Negotiate__c, Negotation_Reason__c,
                   Supervisor_User__c, Supervisor_User__r.Name, Supervisor_User__r.Email,
                   Lead__r.Name, Opportunity__r.Name, Opportunity__r.Lead_Name__c
            FROM Site_Visit_Report__c
            WHERE Id IN :reportIds
        ];

        // Template keys are stored in Custom Labels (either DeveloperName OR Name).
        String approvalTplKey = Label.Arelia_Living_Site_Visit_Approval_by_Manager_Template;
        String negoTplKey     = Label.Arelia_Living_Site_Visit_Negotation_by_Manager_Template;

        // Build a set of keys to query templates once.
        Set<String> keys = new Set<String>();
        if (String.isNotBlank(approvalTplKey)) {
            keys.add(approvalTplKey.trim());
        }
        if (String.isNotBlank(negoTplKey)) {
            keys.add(negoTplKey.trim());
        }
        if (keys.isEmpty()) {
            return;
        }

        // Load templates in one query.
        // We store them by BOTH DeveloperName and Name to support either label style.
        Map<String, EmailTemplate> templateMap = new Map<String, EmailTemplate>();
        for (EmailTemplate et : [
            SELECT Id, Name, DeveloperName, Subject, HtmlValue, Body
            FROM EmailTemplate
            WHERE DeveloperName IN :keys OR Name IN :keys
            LIMIT 50
        ]) {
            if (et == null) {
                continue;
            }
            if (String.isNotBlank(et.DeveloperName)) {
                templateMap.put(et.DeveloperName, et);
            }
            if (String.isNotBlank(et.Name)) {
                templateMap.put(et.Name, et);
            }
        }

        // Build email messages in memory (bulk).
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (Site_Visit_Report__c report : fullReports) {
            if (report == null) {
                continue;
            }

            // Supervisor email is mandatory.
            String supervisorEmail =
                (report.Supervisor_User__r != null) ? report.Supervisor_User__r.Email : null;

            if (String.isBlank(supervisorEmail)) {
                continue;
            }

            // Choose template key based on current flags (same logic as your code).
            String chosenKey = report.Management_Approval__c
                ? approvalTplKey
                : (report.Negotiate__c ? negoTplKey : null);

            if (String.isBlank(chosenKey)) {
                continue;
            }

            // Fetch template by the chosen key (trim for safety).
            EmailTemplate tpl = templateMap.get(chosenKey.trim());
            if (tpl == null) {
                // Template not found => likely label mismatch or Lightning template (not Classic).
                continue;
            }

            // Determine HTML body source:
            // - Classic HTML uses HtmlValue
            // - Some templates use Body (text/html in body)
            String htmlBody = String.isNotBlank(tpl.HtmlValue) ? tpl.HtmlValue : tpl.Body;
            String subject  = tpl.Subject;

            // Defaults
            if (String.isBlank(subject)) {
                subject = DEFAULT_SUBJECT;
            }
            if (String.isBlank(htmlBody)) {
                // If body is blank, template is not usable in this approach.
                continue;
            }

            // Manual merge replacements (preserves your placeholders and logic).
            // IMPORTANT: Use safeString to avoid null strings and PMD-safe style.
            String supervisorName = (report.Supervisor_User__r != null) ? report.Supervisor_User__r.Name : null;
            String leadName       = (report.Lead__r != null) ? report.Lead__r.Name : null;
            String oppLeadName = (report.Opportunity__r != null) ? report.Opportunity__r.Lead_Name__c : null;
            String finalName = leadName != null ? leadName : oppLeadName;

            htmlBody = htmlBody
                .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(supervisorName))
                .replace('{{{Site_Visit_Report__c.Lead__r.Name}}}', safeString(finalName))
                .replace('{{{Site_Visit_Report__c.Name}}}', safeString(report.Name))
                .replace('{{{Site_Visit_Report__c.Negotation_Reason__c}}}', safeString(report.Negotation_Reason__c));

            subject = subject
                .replace('{{{Site_Visit_Report__c.Supervisor_User__r.Name}}}', safeString(supervisorName))
                .replace('{{{Site_Visit_Report__c.Lead__r.Name}}}', safeString(leadName))
                .replace('{{{Site_Visit_Report__c.Name}}}', safeString(report.Name))
                .replace('{{{Site_Visit_Report__c.Negotation_Reason__c}}}', safeString(report.Negotation_Reason__c));

            // Create email (bulk-safe: do not send inside loop).
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ supervisorEmail.trim() });
            email.setSubject(subject);
            email.setHtmlBody(htmlBody);
            email.setSaveAsActivity(false);

            emailsToSend.add(email);
        }

        // Perform a single send call.
        if (!emailsToSend.isEmpty()) {
            // Keep results available (even if unused) to ensure execution occurred.
            // No debug statements (PMD-friendly). If needed later, log failures to a custom object.
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
        }
    }

    /**
     * @description
     * Null-safe conversion to String. Returns empty string for null.
     * Keeps template merge replacements safe from "null" strings.
     *
     * @param val Any object value
     * @return Empty string when null, otherwise String.valueOf(val)
     */
    private static String safeString(Object val) {
        return (val == null) ? '' : String.valueOf(val);
    }

    /**
     * @description
     * Null-safe boolean evaluation.
     * Returns true only when val is explicitly true.
     *
     * @param val Boolean input (nullable)
     * @return true if val == true, else false
     */
    private static Boolean safeBool(Boolean val) {
        return val != null && val == true;
    }
}