@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList,PMD.ExcessiveClassLength')
public without sharing class ProjectAdditionalBudgetController {

    /* ===============================
       CONFIG
    =============================== */
    private static final String FIELDSET_API_NAME = System.Label.Additional_Request_FieldSet_Label;

    private static final String STATUS_PENDING  = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';

    private static final String HISTORY_TOKEN_PENDING = 'Status=PENDING';

    // Email Template Developer Names
    private static final String TPL_MANAGER_APPROVAL = System.Label.AdditionalBudget_Manager_Template;
    private static final String TPL_APPROVED_NOTIFY  = System.Label.AdditionalBudget_Approved_Template;
    private static final String TPL_REJECTED_NOTIFY  = System.Label.AdditionalBudget_Rejected_Template;

    // Attachment safeguards
    private static final Integer MAX_ATTACHMENTS = 10;
    private static final Integer MAX_TOTAL_BYTES = 7000000; // ~7MB safe buffer

    /* ===============================
       DTOs
    =============================== */
    public class FieldDTO {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean required;

        public FieldDTO(String apiName, String label, Boolean required) {
            this.apiName = apiName;
            this.label = label;
            this.required = required;
        }
    }

    public class ProjectDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;

        @AuraEnabled public Decimal additionalBudget;
        @AuraEnabled public Decimal supervisorEstimatedBudget;

        @AuraEnabled public String requestStatus;
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public String pendingReason;

        // ✅ NEW FIELD (stored rejection reason)
        @AuraEnabled public String additionalBudgetRejectionReason;

        @AuraEnabled public Boolean hasPending;

        @AuraEnabled public String historyRaw;
        @AuraEnabled public List<String> historyPretty;
    }

    private class TokenContext {
        public Project__c project;
        public Decimal pendingAmount;
        public String pendingReason;
        public String requestStatus;
        public String approvalLink;
        public String rejectionReason;
    }

    /* ===============================
       FIELD SET (labels)
       - Returns configured field-set fields for UI rendering.
    =============================== */
    @AuraEnabled(cacheable=true)
    public static List<FieldDTO> getFieldSetFields() {
        Schema.FieldSet fs = Schema.SObjectType.Project__c.fieldSets.getMap().get(FIELDSET_API_NAME);
        if (fs == null) {
            throw new AuraHandledException('Field Set not found: ' + FIELDSET_API_NAME);
        }

        List<FieldDTO> outList = new List<FieldDTO>();
        for (Schema.FieldSetMember m : fs.getFields()) {
            outList.add(new FieldDTO(m.getFieldPath(), m.getLabel(), m.getRequired()));
        }
        return outList;
    }

    /* ===============================
       READ (Approval Page)
       - Loads current project + pending request details for the approval UI.
    =============================== */
    @AuraEnabled(cacheable=true)
    public static ProjectDTO getProject(Id projectId) {
        if (projectId == null) {
            throw new AuraHandledException('Project Id is required.');
        }

        // ✅ FIX for your error: include budget fields because DTO reads them
        Project__c p = fetchProject(projectId, false, true);

        ProjectDTO dto = new ProjectDTO();
        dto.id = p.Id;
        dto.name = p.Name;

        dto.additionalBudget = p.Additional_Budget__c;
        dto.supervisorEstimatedBudget = p.Supervisor_Estimated_Budget__c;

        dto.requestStatus = safeString(p.Additional_Request_Status__c);
        dto.pendingAmount = p.Pending_Additional_Amount__c;
        dto.pendingReason = p.Pending_Additional_Reason__c;

        // ✅ New stored rejection reason
        dto.additionalBudgetRejectionReason = p.Additional_Budget_Rejection_Reason__c;

        dto.hasPending =
            (dto.requestStatus == STATUS_PENDING) &&
            (dto.pendingAmount != null && dto.pendingAmount > 0) &&
            !String.isBlank(dto.pendingReason);

        dto.historyRaw = p.Additional_Budget_History__c;
        dto.historyPretty = buildPrettyHistory(dto.historyRaw);

        return dto;
    }

    /* ===============================
       SUBMIT (Request Page)
       ✅ Supports file attachments via ContentDocumentIds
    =============================== */
    @AuraEnabled
    public static void submitRequest(Id projectId, Decimal amount, String reason, List<Id> contentDocumentIds) {
        if (projectId == null) { throw new AuraHandledException('Project Id is required.'); }
        if (amount == null || amount <= 0) { throw new AuraHandledException('Amount must be greater than 0.'); }
        if (String.isBlank(reason)) { throw new AuraHandledException('Reason is required.'); }

        Project__c p = fetchProject(projectId, true, false);

        // Block multiple pending requests
        if (safeString(p.Additional_Request_Status__c) == STATUS_PENDING &&
            p.Pending_Additional_Amount__c != null && p.Pending_Additional_Amount__c > 0) {
            throw new AuraHandledException('One request is already pending approval.');
        }

        p.Pending_Additional_Amount__c = amount;
        p.Pending_Additional_Reason__c = oneLine(reason);
        p.Additional_Request_Status__c = STATUS_PENDING;

        // ✅ Store uploaded ContentDocumentIds (comma separated) for approve email
        List<Id> ids = normalizeIds(contentDocumentIds);
        p.Additional_Budget_ContentDocumentIds__c = joinIds(ids);

        String history = safeTrim(p.Additional_Budget_History__c);
        Integer seq = nextSequence(history);

        String line =
            seq + ') +' + String.valueOf(amount) +
            ' | ' + oneLine(reason) +
            ' | Status=PENDING' +
            ' | ReqBy=' + UserInfo.getName() +
            ' | ReqOn=' + String.valueOf(System.today());

        p.Additional_Budget_History__c = String.isBlank(history) ? line : (history + '\n' + line);

        update p;

        // Email to manager label emails + attach uploaded files
        sendManagerApprovalEmail(p, amount, reason, normalizeIds(contentDocumentIds));
    }

    /* ===============================
       APPROVE
       ✅ Adds to budgets, clears pending, sends emails
    =============================== */
    @AuraEnabled
    public static void approveRequest(Id projectId) {
        if (projectId == null) { throw new AuraHandledException('Project Id is required.'); }

        Project__c p = fetchProject(projectId, true, true);
        validatePending(p);

        Decimal amt = p.Pending_Additional_Amount__c;
        String rsn = p.Pending_Additional_Reason__c;

        // ✅ Pull stored document ids and attach
        List<Id> contentDocIds = parseIds(p.Additional_Budget_ContentDocumentIds__c);

        p.Additional_Budget__c = (p.Additional_Budget__c == null ? 0 : p.Additional_Budget__c) + amt;
        p.Supervisor_Estimated_Budget__c =
            (p.Supervisor_Estimated_Budget__c == null ? 0 : p.Supervisor_Estimated_Budget__c) + amt;

        p.Additional_Request_Status__c = STATUS_APPROVED;

        p.Additional_Budget_History__c = replaceLastPendingLine(
            p.Additional_Budget_History__c,
            'Status=APPROVED | AppBy=' + UserInfo.getName() + ' | AppOn=' + String.valueOf(System.today())
        );

        p.Pending_Additional_Amount__c = null;
        p.Pending_Additional_Reason__c = null;

        // ✅ Optional (recommended): clear stored ids once used
        p.Additional_Budget_ContentDocumentIds__c = null;

        update p;

        sendApprovedEmail(p, amt, rsn, contentDocIds);
    }

    /* ===============================
       REJECT (UPDATED)
       ✅ Requires rejection reason
       ✅ Stores into new field Additional_Budget_Rejection_Reason__c
       ✅ Updates status/history, clears pending, sends email with token
    =============================== */
    @AuraEnabled
    public static void rejectRequest(Id projectId, String rejectionReason) {
        if (projectId == null) { throw new AuraHandledException('Project Id is required.'); }
        if (String.isBlank(rejectionReason)) { throw new AuraHandledException('Rejection reason is required.'); }

        Project__c p = fetchProject(projectId, true, true);
        validatePending(p);

        // ✅ Pull stored document ids and attach
        List<Id> contentDocIds = parseIds(p.Additional_Budget_ContentDocumentIds__c);

        Decimal amt = p.Pending_Additional_Amount__c;
        String reqReason = p.Pending_Additional_Reason__c;
        String rejReason = oneLine(rejectionReason);

        p.Additional_Request_Status__c = STATUS_REJECTED;

        // ✅ Store in new field
        p.Additional_Budget_Rejection_Reason__c = rejReason;

        p.Additional_Budget_History__c = replaceLastPendingLine(
            p.Additional_Budget_History__c,
            'Status=REJECTED | RejBy=' + UserInfo.getName() + ' | RejOn=' + String.valueOf(System.today()) +
            ' | RejReason=' + rejReason
        );

        p.Pending_Additional_Amount__c = null;
        p.Pending_Additional_Reason__c = null;
        // ✅ Optional (recommended): clear stored ids once used
        p.Additional_Budget_ContentDocumentIds__c = null;
        update p;

        sendRejectedEmail(p, amt, reqReason, rejReason, contentDocIds);
    }

    /* ===============================
       VALIDATION
    =============================== */
    private static void validatePending(Project__c p) {
        if (safeString(p.Additional_Request_Status__c) != STATUS_PENDING ||
            p.Pending_Additional_Amount__c == null || p.Pending_Additional_Amount__c <= 0 ||
            String.isBlank(p.Pending_Additional_Reason__c)) {
            throw new AuraHandledException('No pending request found.');
        }
    }

    /* ===============================
       SINGLE SOQL (avoid repeated queries)
       - includeBudgetFields: include Additional_Budget__c fields when needed
    =============================== */
    private static Project__c fetchProject(Id projectId, Boolean forUpdate, Boolean includeBudgetFields) {
        String soql =
            'SELECT Id, Name, ' +
            'Client__r.Name, ' +
            'Supervisor_User__r.FirstName, Supervisor_User__r.LastName, Supervisor_User__r.Name, Supervisor_User__c, ' +
            'Client_Email__c, Supervisor_Email_Text_c__c, ' +
            'Additional_Budget_History__c, Additional_Request_Status__c, ' +
            'Pending_Additional_Amount__c, Pending_Additional_Reason__c, ' +
            'Additional_Budget_Rejection_Reason__c,Additional_Budget_ContentDocumentIds__c';

        if (includeBudgetFields) {
            soql += ', Additional_Budget__c, Supervisor_Estimated_Budget__c';
        }

        soql += ' FROM Project__c WHERE Id = :projectId LIMIT 1';
        if (forUpdate) {
            soql += ' FOR UPDATE';
        }

        List<Project__c> rows = Database.query(soql);
        if (rows.isEmpty()) {
            throw new AuraHandledException('No Project record found for Id: ' + String.valueOf(projectId));
        }
        return rows[0];
    }

    /* ===============================
       EMAILS
    =============================== */
    private static void sendManagerApprovalEmail(Project__c project, Decimal amt, String rsn, List<Id> contentDocumentIds) {
        List<String> toEmails = parseEmails(System.Label.Arelia_Living_Enrollment_Members);
        if (toEmails.isEmpty()) { return; }

        EmailTemplate t = getTemplateByDevName(TPL_MANAGER_APPROVAL);

        String approvalLink = System.Label.Arelia_Site_Label + System.Label.AdditionalBudget_Approval_BaseUrl + '?id=' + project.Id;

        TokenContext ctx = new TokenContext();
        ctx.project = project;
        ctx.pendingAmount = amt;
        ctx.pendingReason = rsn;
        ctx.requestStatus = STATUS_PENDING;
        ctx.approvalLink = approvalLink;
        ctx.rejectionReason = null;

        String subject = applyProjectTokens(t.Subject, ctx);
        String bodyHtml = applyProjectTokens(t.HtmlValue, ctx);

        List<Messaging.EmailFileAttachment> atts = buildEmailAttachments(contentDocumentIds);
        sendEmailStrict(toEmails, subject, bodyHtml, atts);
    }

    /**
     * @description
     *  Sends approved notification email to Client + Supervisor + Enrollment Members.
     *  Also attaches files uploaded during the request (stored in Additional_Budget_ContentDocumentIds__c).
     */
    private static void sendApprovedEmail(Project__c project, Decimal amt, String rsn, List<Id> contentDocumentIds) {
        List<String> toEmails = new List<String>();
        toEmails.addAll(parseEmails(project.Client_Email__c));
        toEmails.addAll(parseEmails(project.Supervisor_Email_Text_c__c));
        toEmails.addAll(parseEmails(Label.Arelia_Living_Enrollment_Members));
        toEmails = dedupe(toEmails);
        if (toEmails.isEmpty()) { return; }

        EmailTemplate t = getTemplateByDevName(TPL_APPROVED_NOTIFY);

        TokenContext ctx = new TokenContext();
        ctx.project = project;
        ctx.pendingAmount = amt;
        ctx.pendingReason = rsn;
        ctx.requestStatus = STATUS_APPROVED;
        ctx.approvalLink = null;
        ctx.rejectionReason = null;

        String subject = applyProjectTokens(t.Subject, ctx);
        String bodyHtml = applyProjectTokens(t.HtmlValue, ctx);

        List<Messaging.EmailFileAttachment> atts = buildEmailAttachments(contentDocumentIds);
        sendEmailStrict(toEmails, subject, bodyHtml, atts);
    }


    /**
     * @description
     *  Sends rejected notification email to Supervisor + Enrollment Members.
     *  Includes rejection reason token and attaches the original uploaded files.
     */
    private static void sendRejectedEmail(Project__c project, Decimal amt, String reqReason, String rejReason, List<Id> contentDocumentIds) {
        List<String> toEmails = new List<String>();
        toEmails.addAll(parseEmails(project.Supervisor_Email_Text_c__c));
        toEmails.addAll(parseEmails(Label.Arelia_Living_Enrollment_Members));
        toEmails = dedupe(toEmails);
        if (toEmails.isEmpty()) { return; }

        EmailTemplate t = getTemplateByDevName(TPL_REJECTED_NOTIFY);

        TokenContext ctx = new TokenContext();
        ctx.project = project;
        ctx.pendingAmount = amt;
        ctx.pendingReason = reqReason;
        ctx.requestStatus = STATUS_REJECTED;
        ctx.approvalLink = null;
        ctx.rejectionReason = rejReason;

        String subject = applyProjectTokens(t.Subject, ctx);
        String bodyHtml = applyProjectTokens(t.HtmlValue, ctx);

        List<Messaging.EmailFileAttachment> atts = buildEmailAttachments(contentDocumentIds);
        sendEmailStrict(toEmails, subject, bodyHtml, atts);
    }

    private static EmailTemplate getTemplateByDevName(String developerName) {
        List<EmailTemplate> ts = [SELECT Id, DeveloperName, Subject, HtmlValue
                        FROM EmailTemplate WHERE DeveloperName = :developerName LIMIT 1];
        if (ts.isEmpty()) {
            throw new AuraHandledException('Email Template not found: ' + developerName);
        }
        return ts[0];
    }

    /**
     * Token replacement (your {{{ }}} style)
     * Supports {{{rejectionReason}}} token for rejected template
     */
    private static String applyProjectTokens(String templateHtml, TokenContext ctx) {
        String out = (templateHtml == null) ? '' : templateHtml;

        String supervisorName = ctx.project.Supervisor_User__r.FirstName +''+ctx.project.Supervisor_User__r.LastName;

        out = out
            .replace('{{{Project__c.Name}}}', safeString(ctx.project.Name))
            .replace('{{{Project__c.Client__r.Name}}}', (ctx.project.Client__r == null ? '' : safeString(ctx.project.Client__r.Name)))
            .replace('{{{Project__c.Supervisor__r.Name}}}', safeString(supervisorName))
            .replace('{{{Project__c.Supervisor_User__r.Name}}}', safeString(supervisorName))
            .replace('{{{Project__c.Pending_Additional_Amount__c}}}', safeString(ctx.pendingAmount))
            .replace('{{{Project__c.Pending_Additional_Reason__c}}}', safeString(ctx.pendingReason))
            .replace('{{{Project__c.Additional_Request_Status__c}}}', safeString(ctx.requestStatus))
            .replace('{{{approvalLink}}}', safeString(ctx.approvalLink))
            .replace('{{{rejectionReason}}}', safeString(ctx.rejectionReason));

        return out;
    }

    private static void sendEmailStrict(
        List<String> toEmails,
        String subject,
        String htmlBody,
        List<Messaging.EmailFileAttachment> atts
    ) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(toEmails);
        msg.setSubject(String.isBlank(subject) ? 'Additional Budget Request' : subject);
        msg.setHtmlBody(String.isBlank(htmlBody) ? ' ' : htmlBody);
        msg.setSaveAsActivity(false);
        msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

        if (atts != null && !atts.isEmpty()) {
            msg.setFileAttachments(atts);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            String err = 'Email failed.';
            if (results != null && !results.isEmpty() &&
                results[0].getErrors() != null && !results[0].getErrors().isEmpty()) {
                err = 'Email failed: ' + results[0].getErrors()[0].getMessage();
            }
            throw new AuraHandledException(err);
        }
    }

    /* ===============================
       EMAIL ATTACHMENTS
    =============================== */
    private static List<Messaging.EmailFileAttachment> buildEmailAttachments(List<Id> contentDocumentIds) {
        List<Messaging.EmailFileAttachment> outList = new List<Messaging.EmailFileAttachment>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) { return outList; }

        List<Id> ids = new List<Id>();
        Integer limitCount = Math.min(MAX_ATTACHMENTS, contentDocumentIds.size());
        for (Integer i = 0; i < limitCount; i++) {
            if (contentDocumentIds[i] != null) { ids.add(contentDocumentIds[i]); }
        }
        if (ids.isEmpty()) { return outList; }

        List<ContentVersion> vers = [SELECT ContentDocumentId, Title, FileExtension, VersionData, 
                                ContentSize FROM ContentVersion 
                                WHERE IsLatest = true AND ContentDocumentId IN :ids];

        Integer totalBytes = 0;
        for (ContentVersion cv : vers) {
            if (cv.VersionData == null) { continue; }

            Integer sizeBytes = (cv.ContentSize == null) ? 0 : Integer.valueOf(cv.ContentSize);
            if ((totalBytes + sizeBytes) > MAX_TOTAL_BYTES) {
                break;
            }
            totalBytes += sizeBytes;

            Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
            String ext = String.isBlank(cv.FileExtension) ? '' : ('.' + cv.FileExtension);
            att.setFileName(String.valueOf(cv.Title) + ext);
            att.setBody(cv.VersionData);
            outList.add(att);
        }
        return outList;
    }

    /* ===============================
       PRETTY HISTORY
    =============================== */
    private static List<String> buildPrettyHistory(String historyRaw) {
        List<String> pretty = new List<String>();
        if (String.isBlank(historyRaw)) { return pretty; }

        for (String ln : historyRaw.split('\n')) {
            if (String.isBlank(ln)) { continue; }
            pretty.add(prettyHistoryLine(ln.trim()));
        }
        return pretty;
    }

    private static String prettyHistoryLine(String line) {
        String reqNo = extractPrefixNumber(line);
        Decimal amt = extractAmountFromLine(line);
        String reason = extractPipeValue(line, 1);

        String status = extractTokenValue(line, 'Status');
        String reqBy = extractTokenValue(line, 'ReqBy');
        String reqOn = extractTokenValue(line, 'ReqOn');

        String appBy = extractTokenValue(line, 'AppBy');
        String appOn = extractTokenValue(line, 'AppOn');

        String rejBy = extractTokenValue(line, 'RejBy');
        String rejOn = extractTokenValue(line, 'RejOn');
        String rejReason = extractTokenValue(line, 'RejReason');

        String amountText = (amt == null) ? '' : ('₹' + String.valueOf(amt.setScale(2)));
        String prefix = String.isBlank(reqNo) ? 'Request' : ('Request #' + reqNo);

        if (status == 'PENDING') {
            return prefix + ': Requested additional budget of ' + amountText +
                ' for "' + safeString(reason) + '". Requested by ' + safeString(reqBy) +
                ' on ' + safeString(reqOn) + '. Status: Pending approval.';
        }
        if (status == 'APPROVED') {
            return prefix + ': Additional budget of ' + amountText +
                ' for "' + safeString(reason) + '" was approved by ' + safeString(appBy) +
                ' on ' + safeString(appOn) + '. (Originally requested by ' + safeString(reqBy) +
                ' on ' + safeString(reqOn) + '.)';
        }
        if (status == 'REJECTED') {
            String extra = String.isBlank(rejReason) ? '' : (' Rejection Reason: "' + safeString(rejReason) + '".');
            return prefix + ': Additional budget request of ' + amountText +
                ' for "' + safeString(reason) + '" was rejected by ' + safeString(rejBy) +
                ' on ' + safeString(rejOn) + '.' + extra +
                ' (Originally requested by ' + safeString(reqBy) +
                ' on ' + safeString(reqOn) + '.)';
        }
        return line;
    }

    /* ===============================
       HISTORY HELPERS
    =============================== */
    private static String replaceLastPendingLine(String history, String statusReplacement) {
        if (String.isBlank(history)) { return history; }

        List<String> lines = new List<String>(history.split('\n'));
        for (Integer i = lines.size() - 1; i >= 0; i--) {
            if (lines[i] != null && lines[i].contains(HISTORY_TOKEN_PENDING)) {
                String ln = lines[i];
                Integer idx = ln.indexOf(HISTORY_TOKEN_PENDING);
                String base = (idx > 0) ? ln.substring(0, idx).trim() : ln;
                lines[i] = base + ' ' + statusReplacement;
                break;
            }
        }
        return String.join(lines, '\n');
    }

    private static Integer nextSequence(String history) {
        if (String.isBlank(history)) { return 1; }

        Integer maxN = 0;
        for (String ln : history.split('\n')) {
            if (String.isBlank(ln)) { continue; }
            String s = ln.trim();
            Integer idx = s.indexOf(')');
            if (idx > 0) {
                String left = s.substring(0, idx).trim();
                if (left.isNumeric()) { maxN = Math.max(maxN, Integer.valueOf(left)); }
            }
        }
        return maxN + 1;
    }

    private static String extractPrefixNumber(String line) {
        Integer idx = (line == null) ? -1 : line.indexOf(')');
        if (idx > 0) {
            String left = line.substring(0, idx).trim();
            if (left.isNumeric()) { return left; }
        }
        return '';
    }

    private static Decimal extractAmountFromLine(String line) {
        if (String.isBlank(line)) { return null; }

        Integer plusIdx = line.indexOf('+');
        if (plusIdx < 0) { return null; }

        Integer pipeIdx = line.indexOf('|', plusIdx);
        if (pipeIdx < 0) { return null; }

        String amtStr = line.substring(plusIdx + 1, pipeIdx).trim();
        if (String.isBlank(amtStr)) { return null; }

        try {
            return Decimal.valueOf(amtStr);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String extractPipeValue(String line, Integer pipeIndex) {
        if (String.isBlank(line) || pipeIndex == null || pipeIndex < 0) { return ''; }

        List<String> parts = new List<String>();
        for (String p : line.split('\\|')) { parts.add((p == null) ? '' : p.trim()); }
        return (parts.size() > pipeIndex) ? safeString(parts[pipeIndex]) : '';
    }

    private static String extractTokenValue(String line, String tokenKey) {
        if (String.isBlank(line) || String.isBlank(tokenKey)) { return ''; }
        String key = tokenKey + '=';
        Integer idx = line.indexOf(key);
        if (idx < 0) { return ''; }

        Integer startPos = idx + key.length();
        Integer pipePos = line.indexOf('|', startPos);
        String val = (pipePos > startPos) ? line.substring(startPos, pipePos) : line.substring(startPos);
        return (val == null) ? '' : val.trim();
    }

    private static String oneLine(String txt) {
        if (String.isBlank(txt)) { return ''; }
        String t = txt.replace('\n', ' ').replace('\r', ' ').trim();
        return (t.length() > 240) ? (t.substring(0, 240) + '...') : t;
    }

    private static String safeTrim(String s) { return (s == null) ? '' : s.trim(); }
    private static String safeString(Object o) { return (o == null) ? '' : String.valueOf(o); }

    /* ===============================
       EMAIL UTIL
    =============================== */
    private static List<String> parseEmails(String raw) {
        List<String> outList = new List<String>();
        if (String.isBlank(raw)) { return outList; }

        for (String e : raw.split('[,;\\s]+')) {
            if (String.isBlank(e)) { continue; }
            String x = e.trim();
            if (x.contains('@')) { outList.add(x); }
        }
        return outList;
    }

    private static List<String> dedupe(List<String> emails) {
        Set<String> uniq = new Set<String>();
        for (String e : emails) {
            if (!String.isBlank(e)) { uniq.add(e.trim().toLowerCase()); }
        }
        return new List<String>(uniq);
    }

    private static List<Id> normalizeIds(List<Id> ids) {
        List<Id> outList = new List<Id>();
        if (ids == null) { return outList; }
        for (Id x : ids) {
            if (x != null) { outList.add(x); }
        }
        return outList;
    }

    /** Resolve Org-Wide Email Address by label value. */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owd = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return owd.isEmpty() ? null : owd[0].Id;
    }

    /**
     * @description
     *  Converts Id list to comma-separated string for storage.
     */
    private static String joinIds(List<Id> ids) {
        if (ids == null || ids.isEmpty()) { return null; }

        List<String> parts = new List<String>();
        for (Id x : ids) {
            if (x != null) { parts.add(String.valueOf(x)); }
        }
        return parts.isEmpty() ? null : String.join(parts, ',');
    }

    /**
     * @description
     *  Parses comma/semicolon/space separated ids string into List<Id>.
     */
    private static List<Id> parseIds(String raw) {
        List<Id> outList = new List<Id>();
        if (String.isBlank(raw)) { return outList; }

        for (String token : raw.split('[,;\\s]+')) {
            if (String.isBlank(token)) { continue; }
            String t = token.trim();
            try {
                outList.add((Id)t);
            } catch (Exception ex) {
                throw new AuraHandledException('Error::'+ex);
            }
        }
        return outList;
    }

}