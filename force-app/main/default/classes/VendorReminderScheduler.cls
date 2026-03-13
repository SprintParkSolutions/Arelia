@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList,PMD.AvoidGlobalModifier,PMD.ApexSOQLInjection,PMD.CognitiveComplexity')
global without sharing class VendorReminderScheduler implements Schedulable {

    // ---------- Config ----------
    private static final String TEMPLATE_DEV_NAME  = Label.Arelia_Living_VA_Due_Alert_to_the_Supervisor_User;
    private static final String ROLE_LIKE_FILTER   = '%Manager%';
    private static final String STATUS_FIELD       = 'Status__c';
    private static final String STATUS_IN_PROGRESS = 'In-Progress';
    private static final Boolean DEBUG_LOGS        = true;

    // ---------- DTO ----------
    private class RiskWindow {
        Integer daysBefore;
        String  label;
        RiskWindow(Integer d, String l){ daysBefore = d; label = l; }
    }

    // ---------- Entry ----------
    global void execute(SchedulableContext sc) {
        run(Date.today());
    }

    private static void run(Date today) {
        List<Vendor_Assignment__c> assignments = queryAssignmentsInProgress();
        debugLine('Found In-Progress assignments: ' + assignments.size());

        if (assignments.isEmpty()) { 
            debugLine('No assignments to process. Exiting.');
            return; 
        }

        EmailTemplate tpl = queryTemplate();
        debugLine('Template ' + TEMPLATE_DEV_NAME + (tpl == null ? ' NOT found' : ' found'));

        List<String> managers = queryManagerEmails();
        debugLine('Active manager emails found: ' + managers.size());

        List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();

        Integer idx = 0;
        for (Vendor_Assignment__c va : assignments) {
            idx++;
            debugLine('--- Assignment #' + idx + ' :: ' + safe(va.Name) + ' ---');
            handleAssignment(va, today, tpl, managers, outbox);
        }
        send(outbox);
    }

    // ---------- Per Assignment ----------
    private static void handleAssignment(
        Vendor_Assignment__c va,
        Date today,
        EmailTemplate tpl,
        List<String> managers,
        List<Messaging.SingleEmailMessage> outbox
    ) {
        if (!isInProgress(va)) { 
            debugLine('Skipped: Status is not In-Progress or not readable.');
            return; 
        }

        Decimal pct = (va.Completion__c == null) ? 0 : va.Completion__c;
        Integer totalDays = calcTotalDays(va);
        Integer daysLeft  = calcDaysLeft(va, today);
        Boolean hasStarted = (va.Vendor_Work_Start_Date__c != null && today >= va.Vendor_Work_Start_Date__c);

        RiskWindow rw = classify(va);     // dynamic window from total duration + %
        if (rw == null) { 
            debugLine('No risk window (possibly invalid dates or >=96% complete).');
            logSnapshot(va, pct, totalDays, daysLeft, hasStarted, null);
            return; 
        }

        // Local decision mirrors shouldNotifyVendor/Leaders to log reasons clearly
        Boolean vendorShouldSend = false;
        if (va.Vendor_Work_End_Date__c == null || va.Vendor_Work_Start_Date__c == null) {
            vendorShouldSend = false;
        } else if (pct >= 100) {
            vendorShouldSend = false;
        } else if (!hasStarted) {
            vendorShouldSend = false;
        } else {
            vendorShouldSend = (daysLeft != null && daysLeft <= rw.daysBefore);
        }

        Boolean leadersShouldSend = (pct < 100 && daysLeft != null && daysLeft == 1);

        logSnapshot(va, pct, totalDays, daysLeft, hasStarted, rw);
        debugLine('Decision -> Vendor: ' + vendorShouldSend + ', Leaders: ' + leadersShouldSend);

        if (vendorShouldSend) {
            outbox.add(buildVendorEmail(va, rw.label, pct, today));
            //debugLine('Enqueued VENDOR email to: ' + safe(va.Vendor__r != null ? va.Vendor__r.Email__c : null));
        } else {
            debugLine('Did NOT enqueue VENDOR email (conditions not met).');
        }

        if (leadersShouldSend) {
            String taskTable = buildTaskTable(va.Id);
            addSupervisorEmail(outbox, va, tpl, pct, taskTable);
            addManagerEmails(outbox, va, tpl, pct, taskTable, managers);
            debugLine('Enqueued LEADER emails (Supervisor + Managers).');
        } else {
            debugLine('Did NOT enqueue LEADER emails (conditions not met).');
        }
    }

    // ---------- Dynamic Risk Classification ----------
    private static RiskWindow classify(Vendor_Assignment__c va) {
        if (va == null || va.Vendor_Work_Start_Date__c == null || va.Vendor_Work_End_Date__c == null) { return null; }

        Decimal pct = (va.Completion__c == null) ? 0 : va.Completion__c;
        Integer totalDays = calcTotalDays(va);
        if (totalDays == null || totalDays <= 0) { return null; }

        String  label;
        Decimal bufferFraction;

        if (pct < 25) {
            label = 'High Risk';
            bufferFraction = 0.5;
        } else if (pct <= 50) {
            label = 'Risk';
            bufferFraction = 0.3;
        } else if (pct <= 70) {
            label = 'Low Risk';
            bufferFraction = 0.2;
        } else if (pct <= 95) {
            label = 'At Risk';
            bufferFraction = 0.1;
        } else {
            return null; // >=96% complete, no reminder
        }

        Integer daysBefore = Math.max(1, Integer.valueOf(Math.floor(totalDays * bufferFraction)));
        return new RiskWindow(daysBefore, label);
    }

    // ---------- Queries ----------
    private static List<Vendor_Assignment__c> queryAssignmentsInProgress() {
        String whereStatus = ' ' + STATUS_FIELD + ' = :STATUS_IN_PROGRESS ';

        List<Vendor_Assignment__c> rows = Database.query(
            'SELECT Id, Name,' +
            '       Vendor__r.Name, Vendor__r.Email__c,' +
            '       Vendor_Work_Start_Date__c,' +
            '       Vendor_Work_End_Date__c,' +
            '       Number_of_Days__c,' +
            '       Completion__c,' +
            '       Vendor_Category__c,' +  // ✅ Added
            '       ' + STATUS_FIELD + ',' +
            '       Supervisor_User__r.Email, Supervisor_User__r.Name,' +
            '       Project__r.Name ' +
            'FROM Vendor_Assignment__c ' +
             
             'WHERE Vendor__r.Email__c != null AND ' + whereStatus
        );
        return rows;
    }

    private static EmailTemplate queryTemplate() {
        List<EmailTemplate> t = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :TEMPLATE_DEV_NAME
            LIMIT 1
        ];
        return t.isEmpty() ? null : t[0];
    }

    private static List<String> queryManagerEmails() {
        List<String> emails = new List<String>();
        for (User u : [
            SELECT Email
            FROM User
            WHERE IsActive = true
              AND Email != null
              AND UserRole.Name LIKE :ROLE_LIKE_FILTER
        ]) {
            String e = (u.Email == null) ? null : u.Email.trim();
            if (!String.isBlank(e)) { emails.add(e); }
        }
        return emails;
    }

    // ---------- Gates ----------
    private static Boolean isInProgress(Vendor_Assignment__c va) {
        if (va == null) {return false;}
        Object statusVal = va.get(STATUS_FIELD);
        return statusVal != null && String.valueOf(statusVal) == STATUS_IN_PROGRESS;
    }

    // ---------- Email Builders (Vendor) ----------
    private static Messaging.SingleEmailMessage buildVendorEmail(
        Vendor_Assignment__c va, String riskLabel, Decimal percent, Date today
    ) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ va.Vendor__r.Email__c });

        // String subject = '[' + riskLabel + '] ' + safe(va.Name) + ' — Reminder';
        // m.setSubject(subject);

        String assignment   = safe(va.Name);  // e.g., VA-0062
        String projectName  = safe(va.Project__r != null ? va.Project__r.Name : '');
        String subject = 'Action Required: ' + assignment +
                        (String.isBlank(projectName) ? '' : ' – ' + projectName) +
                        ' at ' + riskLabel;
        m.setSubject(subject);

        String project      = safe(va.Project__r != null ? va.Project__r.Name : '');
        String startDateStr = fmt(va.Vendor_Work_Start_Date__c);
        String endDateStr   = fmt(va.Vendor_Work_End_Date__c);
        String pctStr       = String.valueOf(percent == null ? 0 : percent) + '%';
        Integer total       = calcTotalDays(va);
        Integer left        = calcDaysLeft(va, today);

        String html =
            '<div style="font-family:Arial, Helvetica, sans-serif; font-size:13px;">' +
              '<p>Hello ' + escapeHtml(va.Vendor__r != null ? va.Vendor__r.Name : 'Vendor') + ',</p>' +
              '<p>Please find your assignment status below:</p>' +
              '<table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;">' +
                row('Vendor Assignment', safe(va.Name)) +
                row('Name Of the Project', project) +
                row('Start Date', startDateStr) +
                row('End Date', endDateStr) +
                row('Completion Percentage', pctStr) +
                row('Status', riskLabel) +
                row('Total Duration (days)', (total == null ? '' : String.valueOf(total))) +
                row('Days Left (incl. today)', (left == null ? '' : String.valueOf(left))) +
              '</table>' +
              '<p style="margin-top:14px;">Please make progress to meet the deadline. ' +
              'If you need help or a clarification, reply to this email.</p>' +
              '<p>Best regards,<br/>Arelia Living Team</p>' +
            '</div>';

        m.setHtmlBody(html);
        m.setSaveAsActivity(true);
        return m;
    }

    private static String row(String label, String value) {
        return '<tr><td><b>' + escapeHtml(label) + '</b></td><td>' +
               escapeHtml(value == null ? '' : value) + '</td></tr>';
    }

    // ---------- Email Builders (Leaders) ----------
    private static void addSupervisorEmail(
        List<Messaging.SingleEmailMessage> outbox,
        Vendor_Assignment__c va,
        EmailTemplate tpl,
        Decimal percent,
        String taskTableHtml
    ) {
        if (va.Supervisor_User__r == null || String.isBlank(va.Supervisor_User__r.Email)) { 
            debugLine('Supervisor email missing; skipping supervisor email.'); 
            return; 
        }
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ va.Supervisor_User__r.Email });
        m.setSubject(buildSubject(tpl, va));
        m.setHtmlBody(supMgrHtml(tpl, va, percent, taskTableHtml, false));
        m.setSaveAsActivity(true);
        outbox.add(m);
    }

    private static void addManagerEmails(
        List<Messaging.SingleEmailMessage> outbox,
        Vendor_Assignment__c va,
        EmailTemplate tpl,
        Decimal percent,
        String taskTableHtml,
        List<String> managers
    ) {
        if (managers.isEmpty()) { 
            debugLine('No manager recipients configured; skipping manager emails.');
            return; 
        }
        String subject = buildSubject(tpl, va);
        String html    = supMgrHtml(tpl, va, percent, taskTableHtml, true);
        for (String addr : managers) {
            if (String.isBlank(addr)) { continue; }
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses(new List<String>{ addr });
            m.setSubject(subject);
            m.setHtmlBody(html);
            m.setSaveAsActivity(true);
            outbox.add(m);
        }
    }

    private static String buildSubject(EmailTemplate tpl, Vendor_Assignment__c va) {
        String assignmentName = safe(va.Name);
        String projectName    = safe(va.Project__r != null ? va.Project__r.Name : '');
        String vendorCategory = safe(va.Vendor_Category__c);

        // Fallback if template missing
        if (tpl == null || String.isBlank(tpl.Subject)) {
            return 'Vendor Reminder: ' + assignmentName +
                (String.isBlank(projectName) ? '' : ' for ' + projectName);
        }

        return tpl.Subject
            .replace('{{AssignmentName}}', assignmentName)
            .replace('{{ProjectName}}', projectName)
            .replace('{{VendorCategory}}', vendorCategory);
    }

    private static String supMgrHtml(
        EmailTemplate tpl,
        Vendor_Assignment__c va,
        Decimal percent,
        String taskTableHtml,
        Boolean isMgr
    ) {
        if (tpl != null && !String.isBlank(tpl.HtmlValue)) {
            return tpl.HtmlValue
                .replace('{{SupervisorName}}', isMgr ? 'Manager' :
                    (va.Supervisor_User__r != null ? safe(va.Supervisor_User__r.Name) : 'Supervisor'))
                .replace('{{ProjectName}}', safe(va.Project__r != null ? va.Project__r.Name : ''))
                .replace('{{AssignmentName}}', safe(va.Name))
                .replace('{{VendorName}}', safe(va.Vendor__r != null ? va.Vendor__r.Name : ''))
                .replace('{{DueDate}}', va.Vendor_Work_End_Date__c != null ? va.Vendor_Work_End_Date__c.format() : '')
                .replace('{{CompletionPercentage}}', String.valueOf(percent == null ? 0 : percent) + '%')
                .replace('{{WorkStartDate}}', va.Vendor_Work_Start_Date__c != null ? va.Vendor_Work_Start_Date__c.format() : '')
                .replace('{{NumberOfDays}}', va.Number_of_Days__c != null ? String.valueOf(va.Number_of_Days__c.intValue()) : '')
                .replace('{{TaskTable}}', taskTableHtml);
        }
        return '<p>Hi ' + escapeHtml(isMgr ? 'Manager' :
            (va.Supervisor_User__r != null ? va.Supervisor_User__r.Name : 'Supervisor')) + ',</p>' +
               '<p>Assignment <b>' + escapeHtml(va.Name) + '</b> is approaching due date.</p>' +
               taskTableHtml;
    }

    // ---------- Task Table ----------
    private static String buildTaskTable(Id vendorAssignmentId) {
        List<Task> tasks = [
            SELECT Subject, Status, Priority, ActivityDate, Start_Date__c
            FROM Task
            WHERE WhatId = :vendorAssignmentId
        ];

        String html = '<table border="1"><tr>' +
                      '<th>Subject</th><th>Status</th><th>Priority</th><th>Start</th><th>Due</th></tr>';
        for (Task t : tasks) {
            html += '<tr>' +
                    '<td>' + escapeHtml(t.Subject) + '</td>' +
                    '<td>' + escapeHtml(t.Status)  + '</td>' +
                    '<td>' + escapeHtml(t.Priority)+ '</td>' +
                    '<td>' + (t.get('Start_Date__c') == null ? '' : ((Date)t.get('Start_Date__c')).format()) + '</td>' +
                    '<td>' + (t.ActivityDate == null ? '' : t.ActivityDate.format()) + '</td>' +
                    '</tr>';
        }
        return html + '</table>';
    }

    // ---------- Send ----------
    private static void send(List<Messaging.SingleEmailMessage> outbox) {
        debugLine('Outbox emails to send: ' + outbox.size());
        if (outbox.isEmpty()) { 
            debugLine('No emails to send today.');
            return; 
        }
        Messaging.sendEmail(outbox);
        debugLine('Emails sent successfully: ' + outbox.size());
    }

    // ---------- Date Math Helpers (directional) ----------
    private static Integer calcTotalDays(Vendor_Assignment__c va) {
        if (va == null || va.Vendor_Work_Start_Date__c == null || va.Vendor_Work_End_Date__c == null){ return null;}
        return va.Vendor_Work_Start_Date__c.daysBetween(va.Vendor_Work_End_Date__c);
    }

    private static Integer calcDaysLeft(Vendor_Assignment__c va, Date asOf) {
        if (va == null || va.Vendor_Work_End_Date__c == null){ return null;}
        if (asOf == null) {asOf = Date.today();}
        if (asOf > va.Vendor_Work_End_Date__c) { return 0; }   // already past due
        return asOf.daysBetween(va.Vendor_Work_End_Date__c);
    }

    // ---------- Debug helpers ----------
    private static void logSnapshot(
        Vendor_Assignment__c va,
        Decimal pct,
        Integer totalDays,
        Integer daysLeft,
        Boolean hasStarted,
        RiskWindow rw
    ) {
        String msg =
            'Snapshot :: ' +
            'Name=' + safe(va.Name) +
            ', Status=' + String.valueOf(va.get(STATUS_FIELD)) +
            ', %=' + String.valueOf(pct) +
            ', Start=' + fmt(va.Vendor_Work_Start_Date__c) +
            ', End=' + fmt(va.Vendor_Work_End_Date__c) +
            ', totalDays=' + String.valueOf(totalDays) +
            ', daysLeft=' + String.valueOf(daysLeft) +
            ', hasStarted=' + String.valueOf(hasStarted) +
            ', riskLabel=' + (rw == null ? 'null' : rw.label) +
            ', windowDaysBefore=' + (rw == null ? 'null' : String.valueOf(rw.daysBefore));
        debugLine(msg);
    }

    private static void debugLine(String s) {
        if (DEBUG_LOGS) {System.debug(LoggingLevel.INFO, '[VendorReminderScheduler] ' + s);}
    }

    // ---------- Misc Helpers ----------
    private static String fmt(Date d) { return (d == null) ? '' : d.format(); }
    private static String safe(String s) { return (s == null) ? '' : s; }
    private static String escapeHtml(String s) {
        if (s == null) {return '';}
        return s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
                .replace('"','&quot;').replace('\'','&#39;');
    }
}