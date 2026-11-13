/**
 * @description
 *  On Project__c AFTER UPDATE, whenever Project_Completion_Status__c changes, finds the next
 *  unpaid Payment_Term__c (installment) for the project - strictly in order, so an installment
 *  is only ever considered once every installment before it is marked paid - and emails the
 *  project's Supervisor and Management team an internal reminder once the project's completion
 *  percentage is approaching that installment's threshold, so the team can follow up with the
 *  client for payment before work on the next milestone needs to start.
 *
 *  Threshold logic: installments are evenly split across the achievement percentage. For N
 *  installments, installment i (1-based, in creation order) has a threshold of i * (100 / N).
 *  Example: 5 installments -> thresholds at 20%, 40%, 60%, 80%, 100%; 3 installments ->
 *  33.33%, 66.67%, 100%. The reminder for the next unpaid installment fires once completion
 *  reaches (threshold - EARLY_REMINDER_BUFFER), i.e. it fires slightly before that installment's
 *  own milestone is reached, not only after.
 *
 *  Reminders repeat on every completion-percentage change for as long as that installment
 *  remains unpaid and its early-reminder window has been reached.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation')
public without sharing class MilestonePaymentReminderHandler {

    private static final String TEMPLATE_DEV_NAME = 'Payment_Milestone_Reminder_Client';

    /**
     * How many percentage points before an installment's own threshold the reminder fires.
     */
    private static final Decimal EARLY_REMINDER_BUFFER = 5;

    /**
     * Pairs a due installment with the completion-percentage threshold that made it due.
     */
    private class DueInstallment {
        Payment_Term__c term;
        Decimal threshold;
        DueInstallment(Payment_Term__c term, Decimal threshold) {
            this.term = term;
            this.threshold = threshold;
        }
    }

    /**
     * Entry point from the trigger (AFTER UPDATE).
     */
    public static void afterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        if (newList == null) { return; }
        if (newList.isEmpty()) { return; }
        if (oldMap == null) { return; }
        if (oldMap.isEmpty()) { return; }

        List<Project__c> changedProjects = pickCompletionChanged(newList, oldMap);
        if (changedProjects.isEmpty()) { return; }

        sendDueReminders(changedProjects);
    }

    /**
     * Filters only the projects whose Project_Completion_Status__c changed, keeping the
     * up-to-date field values already provided by the trigger (Trigger.new).
     */
    private static List<Project__c> pickCompletionChanged(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        List<Project__c> changed = new List<Project__c>();
        for (Project__c pNew : newList) {
            Project__c pOld = oldMap.get(pNew.Id);
            if (pOld == null) { continue; }
            if (pNew.Project_Completion_Status__c != pOld.Project_Completion_Status__c) {
                changed.add(pNew);
            }
        }
        return changed;
    }

    /**
     * Orchestrates loading data and sending reminder emails for the given projects.
     * Uses the field values already present on the passed-in records (e.g. Trigger.new)
     * rather than re-querying, so callers control freshness.
     */
    public static void sendDueReminders(List<Project__c> projects) {
        if (projects == null) { return; }
        if (projects.isEmpty()) { return; }

        Map<Id, Project__c> uniqueProjects = new Map<Id, Project__c>();
        for (Project__c p : projects) {
            if (p != null) { uniqueProjects.put(p.Id, p); }
        }
        if (uniqueProjects.isEmpty()) { return; }

        Map<Id, List<Payment_Term__c>> termsByProject = queryOrderedTerms(uniqueProjects.keySet());
        if (termsByProject.isEmpty()) { return; }

        List<String> managerEmails = parseManagerEmails();
        EmailTemplate tpl = fetchTemplate();
        Id oweaId = fetchOwdId();

        List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();
        for (Project__c proj : uniqueProjects.values()) {
            List<Payment_Term__c> terms = termsByProject.get(proj.Id);
            if (terms == null || terms.isEmpty()) { continue; }

            List<DueInstallment> due = findDueUnpaidTerms(terms, proj.Project_Completion_Status__c);
            if (due.isEmpty()) { continue; }

            List<String> recipients = buildRecipients(proj, managerEmails);
            if (recipients.isEmpty()) { continue; }

            outbox.add(buildReminderEmail(proj, due, recipients, tpl, oweaId));
        }

        send(outbox);
    }

    /**
     * Loads Payment_Term__c records for the given projects, ordered per project in the same
     * creation order used by the Milestone Completion Overview component.
     */
    private static Map<Id, List<Payment_Term__c>> queryOrderedTerms(Set<Id> projectIds) {
        Map<Id, List<Payment_Term__c>> result = new Map<Id, List<Payment_Term__c>>();
        for (Payment_Term__c term : [
            SELECT Id, Name, Term_Label__c, Percentage__c, Payment_Received__c, Due_Date__c, Project__c
            FROM Payment_Term__c
            WHERE Project__c IN :projectIds
            ORDER BY Project__c, CreatedDate ASC
        ]) {
            if (!result.containsKey(term.Project__c)) {
                result.put(term.Project__c, new List<Payment_Term__c>());
            }
            result.get(term.Project__c).add(term);
        }
        return result;
    }

    /**
     * Parses the comma-separated Management_Email_Addresses label into a clean list.
     */
    private static List<String> parseManagerEmails() {
        List<String> emails = new List<String>();
        String raw = Label.Management_Email_Addresses;
        if (String.isBlank(raw)) { return emails; }
        for (String part : raw.split(',')) {
            if (String.isNotBlank(part)) { emails.add(part.trim()); }
        }
        return emails;
    }

    /**
     * Builds the recipient list for a project: its Supervisor Email (if present) plus the
     * Management_Email_Addresses label list.
     */
    private static List<String> buildRecipients(Project__c proj, List<String> managerEmails) {
        Set<String> recipients = new Set<String>();
        if (String.isNotBlank(proj.Supervisor_Email_Text_c__c)) {
            recipients.add(proj.Supervisor_Email_Text_c__c.trim());
        }
        recipients.addAll(managerEmails);
        return new List<String>(recipients);
    }

    /**
     * Finds the single next unpaid installment, strictly in order (every installment before it
     * must already be paid), and checks whether completion has entered its early-reminder
     * window - i.e. reached (threshold - EARLY_REMINDER_BUFFER). Later installments are never
     * considered while an earlier one is still unpaid.
     */
    private static List<DueInstallment> findDueUnpaidTerms(List<Payment_Term__c> orderedTerms, Decimal completion) {
        List<DueInstallment> due = new List<DueInstallment>();
        Integer total = orderedTerms.size();
        if (total == 0) { return due; }

        Decimal safeCompletion = completion == null ? 0 : completion;
        Decimal thresholdStep = 100.0 / total;

        for (Integer i = 0; i < total; i++) {
            Payment_Term__c term = orderedTerms[i];
            if (term.Payment_Received__c == true) { continue; }

            Decimal threshold = thresholdStep * (i + 1);
            Decimal earlyReminderPoint = threshold - EARLY_REMINDER_BUFFER;
            if (safeCompletion >= earlyReminderPoint) {
                due.add(new DueInstallment(term, threshold));
            }
            break; // Strictly sequential: this is the next unpaid installment, stop here either way.
        }
        return due;
    }

    /**
     * Exposes findDueUnpaidTerms for direct unit testing of the sequencing/buffer logic,
     * without depending on email side effects.
     */
    @TestVisible
    private static List<Id> findDueInstallmentIdsForTest(List<Payment_Term__c> orderedTerms, Decimal completion) {
        List<Id> ids = new List<Id>();
        for (DueInstallment di : findDueUnpaidTerms(orderedTerms, completion)) {
            ids.add(di.term.Id);
        }
        return ids;
    }

    /**
     * Exposes buildReminderEmail for direct unit testing of subject/body content
     * (recipients, due date, installment name), without needing to infer results
     * from email invocation counts alone.
     */
    @TestVisible
    private static Messaging.SingleEmailMessage buildReminderEmailForTest(
        Project__c proj,
        List<Payment_Term__c> orderedTerms,
        List<String> recipients,
        EmailTemplate tpl
    ) {
        List<DueInstallment> due = findDueUnpaidTerms(orderedTerms, proj.Project_Completion_Status__c);
        if (due.isEmpty()) { return null; }
        return buildReminderEmail(proj, due, recipients, tpl, null);
    }

    /**
     * Builds the reminder email for a project, using the configured EmailTemplate when
     * available and falling back to inline HTML otherwise.
     */
    private static Messaging.SingleEmailMessage buildReminderEmail(
        Project__c proj,
        List<DueInstallment> due,
        List<String> recipients,
        EmailTemplate tpl,
        Id oweaId
    ) {
        String installmentTable = buildInstallmentTable(due);
        String completionStr = formatPercentage(proj.Project_Completion_Status__c);
        String installmentNames = joinInstallmentNames(due);

        Map<String, String> replacements = new Map<String, String>{
            '{{PROJECT_NAME}}' => safe(proj.Name),
            '{{COMPLETION_PERCENTAGE}}' => completionStr,
            '{{INSTALLMENT_TABLE}}' => installmentTable,
            '{{INSTALLMENT_NAME}}' => installmentNames
        };

        String subject;
        String body;
        if (tpl != null && String.isNotBlank(tpl.HtmlValue)) {
            subject = doReplace(tpl.Subject, replacements);
            body = doReplace(tpl.HtmlValue, replacements);
        } else {
            subject = 'Payment Reminder: ' + safe(proj.Name) + ' - ' + installmentNames + ' Due';
            body = defaultBody(proj, completionStr, installmentTable);
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(recipients);
        mail.setSubject(subject);
        mail.setHtmlBody(body);
        mail.setWhatId(proj.Id);
        mail.setSaveAsActivity(false);
        if (oweaId != null) { mail.setOrgWideEmailAddressId(oweaId); }
        return mail;
    }

    private static String joinInstallmentNames(List<DueInstallment> due) {
        List<String> names = new List<String>();
        for (DueInstallment di : due) {
            Payment_Term__c term = di.term;
            names.add(String.isNotBlank(term.Term_Label__c) ? term.Term_Label__c : term.Name);
        }
        return names.isEmpty() ? '' : String.join(names, ', ');
    }

    private static String defaultBody(Project__c proj, String completionStr, String installmentTable) {
        return '<div style="font-family:Arial, Helvetica, sans-serif; font-size:13px;">' +
                 '<p>Hi Team,</p>' +
                 '<p>Project <strong>' + escapeHtml(proj.Name) + '</strong> has reached <strong>' +
                 completionStr + '</strong> completion. The installment(s) below are now due for client payment collection.</p>' +
                 installmentTable +
                 '<p>Please follow up with the client to collect this payment before work proceeds to the next milestone.</p>' +
                 '<p>Best Regards,<br/>Arelia Team.</p>' +
               '</div>';
    }

    private static String buildInstallmentTable(List<DueInstallment> due) {
        String html = '<table cellpadding="8" cellspacing="0" border="1" style="border-collapse:collapse;">' +
                       '<tr><th>Installment</th><th>Percentage</th><th>Due At Completion</th><th>Due Date</th></tr>';
        for (DueInstallment di : due) {
            Payment_Term__c term = di.term;
            html += '<tr>' +
                    '<td>' + escapeHtml(String.isNotBlank(term.Term_Label__c) ? term.Term_Label__c : term.Name) + '</td>' +
                    '<td>' + formatPercentage(term.Percentage__c) + '</td>' +
                    '<td>' + formatPercentage(di.threshold) + '</td>' +
                    '<td>' + formatDate(term.Due_Date__c) + '</td>' +
                    '</tr>';
        }
        return html + '</table>';
    }

    private static String formatDate(Date val) {
        return val == null ? 'N/A' : val.format();
    }

    private static String formatPercentage(Decimal val) {
        Decimal safeVal = val == null ? 0 : val;
        return String.valueOf(safeVal.setScale(2)) + '%';
    }

    private static EmailTemplate fetchTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :TEMPLATE_DEV_NAME
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    private static Id fetchOwdId() {
        try {
            List<OrgWideEmailAddress> owea = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :Label.Arelia_OWD
                LIMIT 1
            ];
            return owea.isEmpty() ? null : owea[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static void send(List<Messaging.SingleEmailMessage> outbox) {
        if (outbox.isEmpty()) { return; }
        try {
            Messaging.sendEmail(outbox);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MilestonePaymentReminderHandler: Email send failed: ' + e.getMessage());
        }
    }

    private static String safe(String val) { return val != null ? val : ''; }

    private static String doReplace(String content, Map<String, String> replacements) {
        if (content == null) { return ''; }
        String result = content;
        for (String key : replacements.keySet()) {
            result = result.replace(key, replacements.get(key));
        }
        return result;
    }

    private static String escapeHtml(String s) {
        if (s == null) { return ''; }
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                .replace('"', '&quot;').replace('\'', '&#39;');
    }
}