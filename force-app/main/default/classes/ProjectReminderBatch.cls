/**
 * @description
 *  Batch job that sends periodic project reminder emails to Managers and Supervisors
 *  for active projects that are In Progress and within the configured reminder interval.
 *
 *  This class:
 *   - Loads Org-Wide Email Address from custom label (Arelia_OWD)
 *   - Loads an Email Template from custom label (Arelia_Living_Project_Reminder_Template)
 *   - Loads Manager users (role = 'Managers')
 *   - Loads Enrollment label members from label (Arelia_Living_Enrollment_Members)
 *   - Reads reminder interval (in days) from label (Arelia_Living_Project_Reminder_Days)
 *   - Runs on all Project__c records that:
 *       * Have Start_Date__c and Estimated_End_Date__c
 *       * Are currently in Status__c = 'In Progress'
 *   - Sends reminder emails every N days from Start_Date__c until Estimated_End_Date__c
 *
 * @author
 *  (Update with your name if needed)
 *
 * @notes
 *  - Implements Database.Stateful to track total projects processed and emails sent.
 *  - Suppresses some PMD rules because:
 *      * Global visibility is required for Batchable classes.
 *      * Some CRUD/FLS checks are not feasible at this layer (system context batch).
 *      * Logic is non-trivial, hence Cognitive Complexity warning is suppressed.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList,PMD.AvoidGlobalModifier, PMD.ApexSharingViolations')
global class ProjectReminderBatch implements Database.Batchable<SObject>, Database.Stateful {

    // -----------------------------------------
    // STATEFUL FIELDS
    // -----------------------------------------
    /**
     * @description Org-Wide Email Address Id used as the sender for outbound emails.
     */
    Id orgWideEmailId;

    /**
     * @description Email template used for project reminder notifications.
     */
    EmailTemplate reminderTemplate;

    /**
     * @description List of Manager users who will receive reminder emails.
     */
    List<User> managerUsers = new List<User>();

    /**
     * @description List of email addresses from the "Arelia_Enrollment_Members" label used as CC recipients.
     */
    List<String> enrollmentLabelEmails = new List<String>();

    /**
     * @description Interval in days between reminder emails, taken from custom label.
     */
    Integer reminderIntervalDays;

    /**
     * @description Count of total Project__c records processed by the batch.
     */
    Integer totalProjectsProcessed = 0;

    /**
     * @description Count of total emails sent by this batch execution.
     */
    Integer totalEmailsSent       = 0;

    // -----------------------------------------
    // BATCH START
    // -----------------------------------------

    /**
     * @description
     *  Prepares batch execution by loading configuration (Org-Wide Email, Template,
     *  Manager users, label emails, reminder interval) and returns a query for
     *  Project__c records that are eligible for reminders.
     *
     * @param bc
     *  Batchable context passed by the platform.
     *
     * @return Database.QueryLocator
     *  Query locator over active projects that:
     *   - Have Start_Date__c and Estimated_End_Date__c
     *   - Are in Status__c = 'In Progress'
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        orgWideEmailId        = getOrgWideEmailAddressId();
        reminderTemplate      = getReminderTemplate();
        managerUsers          = getManagerUsers();
        enrollmentLabelEmails = parseEmailsFromLabel(Label.Arelia_Living_Enrollment_Members);
        reminderIntervalDays  = getReminderIntervalDays();

        // NOTE: We filter only "In Progress" here; rest of logic remains intact
        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   Client__r.Name,
                   Supervisor_User__r.Name,
                   Supervisor_User__r.Email,
                   Supervisor_Contact_Text_c__c,
                   Project_Completion_Status__c,
                   Type_Of_Project__c,
                   Status__c,
                   Project_Status__c,
                   Start_Date__c,
                   Estimated_End_Date__c,
                   Budget__c
            FROM Project__c
            WHERE Start_Date__c         != null
              AND Estimated_End_Date__c != null
              AND Status__c             = 'In Progress'
        ]);
    }

    // -----------------------------------------
    // BATCH EXECUTE
    // -----------------------------------------

    /**
     * @description
     *  Processes each batch scope of Project__c records. For each project:
     *   - Skips if Completed/Cancelled or not In Progress
     *   - Calculates days from Start_Date__c to today
     *   - Sends reminder emails when:
     *      * daysFromStart > 0
     *      * today <= Estimated_End_Date__c
     *      * daysFromStart % reminderIntervalDays == 0
     *   - Sends email:
     *      * To each Manager user (TO) + label emails (CC)
     *      * To Supervisor user (TO) + label emails (CC)
     *
     * @param bc
     *  Batchable context passed by the platform.
     *
     * @param scope
     *  List of Project__c records to process in this execution chunk.
     */
    global void execute(Database.BatchableContext bc, List<Project__c> scope) {
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        Date today = Date.today();

        for (Project__c project : scope) {
            totalProjectsProcessed++;

            // Keep existing status skip for safety
            if (project.Status__c == 'Completed' || project.Status__c == 'Cancelled') {
                System.debug('⚠ Skipping project ' + project.Name + ' due to status ' + project.Status__c);
                continue;
            }

            // Only operate when project is In Progress
            if (project.Status__c != 'In Progress') {
                System.debug('⚠ Skipping project ' + project.Name + ' because status is not In Progress.');
                continue;
            }

            Integer daysFromStart = project.Start_Date__c.daysBetween(today);

            // - Must not be before start
            // - Must be on/before Estimated_End_Date
            // - Must match the reminder interval (N days) AFTER start (so > 0)
            if (daysFromStart <= 0
                || today > project.Estimated_End_Date__c
                || Math.mod(daysFromStart, reminderIntervalDays) != 0) {

                System.debug(
                    '⚠ Skipping project ' + project.Name +
                    ' due to date conditions. Days from start: ' + daysFromStart +
                    ', Interval: ' + reminderIntervalDays
                );
                continue;
            }

            // ----- Completion Status -----
            String completionStatusStr = 'N/A';
            if (project.Project_Completion_Status__c != null) {
                completionStatusStr = String.valueOf(
                    project.Project_Completion_Status__c.setScale(2, RoundingMode.HALF_UP)
                ) + '%';
            }

            // ----- Merge Fields -----
            Map<String, String> mergeFields = new Map<String, String>{
                '{{ProjectName}}'       => project.Name,
                '{{ClientName}}'        => project.Client__r != null ? project.Client__r.Name : 'N/A',
                '{{SupervisorName}}'    => project.Supervisor_User__r != null ? project.Supervisor_User__r.Name : 'N/A',
                '{{SupervisorContact}}' => project.Supervisor_Contact_Text_c__c != null ? project.Supervisor_Contact_Text_c__c : 'N/A',
                '{{CompletionStatus}}'  => completionStatusStr,
                '{{TypeOfProject}}'     => project.Type_Of_Project__c != null ? project.Type_Of_Project__c : 'N/A',
                '{{Status}}'            => project.Status__c != null ? project.Status__c : 'N/A',
                '{{StartDate}}'         => formatDate(project.Start_Date__c),
                '{{EndDate}}'           => formatDate(project.Estimated_End_Date__c),
                '{{Budget}}'            => project.Budget__c != null ? '$' + String.valueOf(project.Budget__c) : 'N/A'
            };

            // ----- Send to all manager users (TO) + label members (CC) -----
            for (User manager : managerUsers) {
                if (String.isBlank(manager.Email)) {
                    continue;
                }

                mergeFields.put('{{RecipientName}}', manager.Name);
                String htmlBody = replaceMergeFields(reminderTemplate.HtmlValue, mergeFields);
                String subject  = replaceMergeFields(reminderTemplate.Subject,  mergeFields);

                Messaging.SingleEmailMessage email = buildEmail(
                    new List<String>{ manager.Email },
                    enrollmentLabelEmails,
                    subject,
                    htmlBody
                );
                emailsToSend.add(email);
                totalEmailsSent++;
            }

            // ----- Send to Supervisor (TO) + label members (CC) -----
            if (project.Supervisor_User__r != null && !String.isBlank(project.Supervisor_User__r.Email)) {
                mergeFields.put('{{RecipientName}}', project.Supervisor_User__r.Name);
                String htmlBody = replaceMergeFields(reminderTemplate.HtmlValue, mergeFields);
                String subject  = replaceMergeFields(reminderTemplate.Subject,  mergeFields);

                Messaging.SingleEmailMessage email = buildEmail(
                    new List<String>{ project.Supervisor_User__r.Email },
                    enrollmentLabelEmails,
                    subject,
                    htmlBody
                );
                emailsToSend.add(email);
                totalEmailsSent++;
            }
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.sendEmail(emailsToSend);
                System.debug('✅ Sent ' + emailsToSend.size() + ' reminder emails.');
            } catch (Exception e) {
                System.debug('❌ Email send failed: ' + e.getMessage());
            }
        } else {
            System.debug('⚠ No emails to send.');
        }
    }

    // -----------------------------------------
    // BATCH FINISH
    // -----------------------------------------

    /**
     * @description
     *  Executes once after all batch chunks are processed.
     *  Logs summary statistics for monitoring and debugging purposes.
     *
     * @param bc
     *  Batchable context passed by the platform.
     */
    global void finish(Database.BatchableContext bc) {
        System.debug('✅ Project Reminder Batch completed.');
        System.debug('📊 Total Projects Processed: ' + totalProjectsProcessed);
        System.debug('📬 Total Emails Sent: ' + totalEmailsSent);
    }

    // -----------------------------------------
    // HELPER: Org Wide Email
    // -----------------------------------------

    /**
     * @description
     *  Retrieves the Org-Wide Email Address Id using the email address
     *  stored in the custom label Arelia_OWD, limited to those that
     *  allow all profiles.
     *
     * @return Id
     *  OrgWideEmailAddress.Id if found; otherwise null.
     */
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD
              AND IsAllowAllProfiles = true
            LIMIT 1
        ];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    // -----------------------------------------
    // HELPER: Reminder Template
    // -----------------------------------------

    /**
     * @description
     *  Retrieves the reminder EmailTemplate using the DeveloperName
     *  from the custom label Arelia_Living_Project_Reminder_Template.
     *
     * @return EmailTemplate
     *  EmailTemplate record if found; otherwise null.
     */
    private static EmailTemplate getReminderTemplate() {
        List<EmailTemplate> templates = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :Label.Arelia_Living_Project_Reminder_Template
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    // -----------------------------------------
    // HELPER: Manager Users
    // -----------------------------------------

    /**
     * @description
     *  Fetches all active Manager users (UserRole.Name = 'Managers')
     *  with non-null email addresses.
     *
     * @return List<User>
     *  List of active Manager users with email populated.
     */
    private static List<User> getManagerUsers() {
        return [
            SELECT Id, Name, Email
            FROM User
            WHERE UserRole.Name = 'Managers'
              AND IsActive       = true
              AND Email          != null
        ];
    }

    // -----------------------------------------
    // HELPER: Parse interval from label
    // -----------------------------------------

    /**
     * @description
     *  Reads the reminder interval (in days) from the custom label
     *  Arelia_Living_Project_Reminder_Days. If the label is blank,
     *  invalid, or <= 0, falls back to a default of 15 days.
     *
     * @return Integer
     *  Valid reminder interval in days (>=1). Defaults to 15.
     */
    private static Integer getReminderIntervalDays() {
        // Label.Arelia_Living_Project_Reminder_Days should be something like "15"
        String raw = Label.Arelia_Living_Project_Reminder_Days;
        if (String.isBlank(raw)) {
            return 15;
        }

        Integer value;
        try {
            value = Integer.valueOf(raw.trim());
        } catch (Exception e) {
            // Fallback if label is invalid
            value = 15;
        }

        if (value == null || value <= 0) {
            value = 15;
        }
        return value;
    }

    // -----------------------------------------
    // HELPER: Parse emails from label (comma-separated)
    // Label: Arelia_Enrollment_Members
    // -----------------------------------------

    /**
     * @description
     *  Parses a comma-separated string of email addresses from a label value.
     *  Ignores blank segments and trims whitespace around each email.
     *
     *  Example supported formats:
     *   - "a@x.com , b@y.com, , c@z.com"
     *
     * @param labelValue
     *  Raw comma-separated string value from a custom label.
     *
     * @return List<String>
     *  List of cleaned, non-blank email addresses.
     */
    private static List<String> parseEmailsFromLabel(String labelValue) {
        List<String> emails = new List<String>();

        if (String.isBlank(labelValue)) {
            return emails;
        }

        // Apex split() does NOT support 2nd boolean param
        List<String> rawParts = labelValue.split(',');

        for (String part : rawParts) {
            if (String.isNotBlank(part)) {
                emails.add(part.trim());
            }
        }

        return emails;
    }

    // -----------------------------------------
    // HELPER: Build email message (TO + CC)
    // -----------------------------------------

    /**
     * @description
     *  Creates and configures a SingleEmailMessage instance using
     *  the provided TO/CC addresses, subject, and HTML body. Also
     *  associates the Org-Wide Email Address Id if configured.
     *
     * @param toAddresses
     *  List of primary recipients (TO).
     *
     * @param ccAddresses
     *  List of CC recipients.
     *
     * @param subject
     *  Email subject line.
     *
     * @param htmlBody
     *  Email HTML body.
     *
     * @return Messaging.SingleEmailMessage
     *  Configured email message ready to be sent.
     */
    private Messaging.SingleEmailMessage buildEmail(
        List<String> toAddresses,
        List<String> ccAddresses,
        String subject,
        String htmlBody
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        if (!ccAddresses.isEmpty()) {
            email.setCcAddresses(ccAddresses);
        }
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setSaveAsActivity(false);
        if (orgWideEmailId != null) {
            email.setOrgWideEmailAddressId(orgWideEmailId);
        }
        return email;
    }

    // -----------------------------------------
    // HELPER: Merge fields
    // -----------------------------------------

    /**
     * @description
     *  Replaces simple placeholder tokens in the given template string
     *  with the corresponding values from the mergeFields map.
     *
     *  Example:
     *   - template: "Hello {{RecipientName}}"
     *   - mergeFields: {{RecipientName}} => "John"
     *   - result: "Hello John"
     *
     * @param template
     *  Original template text with placeholder keys (e.g., {{ProjectName}}).
     *
     * @param mergeFields
     *  Map of placeholder tokens to replacement values.
     *
     * @return String
     *  Template with all placeholders replaced where keys were found.
     */
    private String replaceMergeFields(String template, Map<String, String> mergeFields) {
        String result = template;
        for (String key : mergeFields.keySet()) {
            result = result.replace(key, mergeFields.get(key));
        }
        return result;
    }

    // -----------------------------------------
    // HELPER: Format date
    // -----------------------------------------

    /**
     * @description
     *  Formats a Date value into a human-friendly string in the format
     *  "dd MMM yyyy" (e.g., "10 Jan 2026"). If the date is null, returns "N/A".
     *
     * @param dt
     *  Date value to format.
     *
     * @return String
     *  Formatted date string or "N/A" if dt is null.
     */
    private String formatDate(Date dt) {
        if (dt == null) {
            return 'N/A';
        }
        Datetime dtm = Datetime.newInstance(dt.year(), dt.month(), dt.day(), 0, 0, 0);
        return dtm.format('dd MMM yyyy');
    }
}