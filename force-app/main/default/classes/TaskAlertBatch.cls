global class TaskAlertBatch implements Database.Batchable<SObject>, Database.Stateful {

    Id orgWideEmailId;
    Map<String, EmailTemplate> templateMap = new Map<String, EmailTemplate>();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        // ✅ Fetch Lightning Email Templates (HtmlValue + Subject)
        for (EmailTemplate et : [
            SELECT DeveloperName, HtmlValue, Subject
            FROM EmailTemplate
            WHERE DeveloperName IN ('Task_Reminder_Email', 'Danger_Zone_Alert_Vendor', 'Danger_Zone_Alert_Supervisor')
        ]) {
            String key = et.DeveloperName.trim();
            System.debug('▶ Template Found: ' + key + ' | HtmlValue Loaded? ' + (String.isNotBlank(et.HtmlValue)) + ' | Subject: ' + et.Subject);
            templateMap.put(key, et);
        }

        System.debug('✅ Loaded Templates in Map: ' + templateMap.keySet());

        orgWideEmailId = getOrgWideEmailAddressId();

        return Database.getQueryLocator([
            SELECT Id, Subject, ActivityDate, Status, WhatId
            FROM Task
            WHERE What.Type = 'Vendor_Assignment__c'
            AND Status != 'Completed'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Task> scope) {
        System.debug('▶ Processing ' + scope.size() + ' Tasks...');
        System.debug('✅ TemplateMap Keys in Execute: ' + templateMap.keySet());

        if (scope.isEmpty()) {
            System.debug('⚠ No Tasks to process.');
            return;
        }

        Set<Id> assignmentIds = new Set<Id>();
        for (Task t : scope) {
            if (t.WhatId != null) assignmentIds.add(t.WhatId);
        }

        if (assignmentIds.isEmpty()) {
            System.debug('⚠ No related Vendor Assignments found.');
            return;
        }

        Map<Id, Vendor_Assignment__c> assignmentMap = new Map<Id, Vendor_Assignment__c>([
            SELECT Id, Name, Owner.Name, Owner.Email,
                   Vendor__r.Name, Vendor__r.Email__c,
                   Project__r.Name,
                   Vendor_Category__c
            FROM Vendor_Assignment__c
            WHERE Id IN :assignmentIds
        ]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Integer reminderCount = 0, supervisorDangerCount = 0, vendorDangerCount = 0;
        Date today = Date.today();

        for (Task t : scope) {
            Vendor_Assignment__c va = assignmentMap.get(t.WhatId);
            if (va == null) {
                System.debug('⚠ Skipping Task: ' + t.Id + ' - No Vendor Assignment found.');
                continue;
            }

            Integer daysDiff = t.ActivityDate != null ? today.daysBetween(t.ActivityDate) : null;
            System.debug('▶ Task: ' + t.Subject + ', Due: ' + t.ActivityDate + ', DaysDiff: ' + daysDiff);
            System.debug('▶ Supervisor: ' + va.Owner.Name + ' (' + va.Owner.Email + '), Vendor: ' + va.Vendor__r.Name + ' (' + va.Vendor__r.Email__c + ')');

            // Merge fields
            Map<String, String> mergeFields = new Map<String, String>{
                '{{SupervisorName}}' => va.Owner.Name,
                '{{VendorName}}' => va.Vendor__r.Name,
                '{{TaskSubject}}' => t.Subject,
                '{{AssignmentName}}' => va.Name,
                '{{ProjectName}}' => (va.Project__r != null ? va.Project__r.Name : 'N/A'),
                '{{DueDate}}' => formatDate(t.ActivityDate)
            };
            // mergeFields.put('{{VendorCategory}}', va.Vendor_Category__c != null ? va.Vendor_Category__c : 'N/A');
            mergeFields.put('{{VendorCategory}}',va.Vendor_Category__c != null ? String.valueOf(va.Vendor_Category__c) : '');



            // ✅ Reminder Email (1 day before)
            if (daysDiff == 1) {
                EmailTemplate template = templateMap.get('Task_Reminder_Email');
                if (template != null && String.isNotBlank(template.HtmlValue)) {
                    // Supervisor
                    if (String.isNotBlank(va.Owner.Email)) {
                        mergeFields.put('{{RecipientName}}', va.Owner.Name);
                        String emailBody = replaceMergeFields(template.HtmlValue, mergeFields);
                        String subject = replaceMergeFields(template.Subject, mergeFields);
                        System.debug('✅ Supervisor Reminder Email Subject: ' + subject);
                        emails.add(createDynamicEmail(va.Owner.Email, subject, emailBody));
                        reminderCount++;
                    }
                    // Vendor
                    if (String.isNotBlank(va.Vendor__r.Email__c)) {
                        mergeFields.put('{{RecipientName}}', va.Vendor__r.Name);
                        String emailBodyVendor = replaceMergeFields(template.HtmlValue, mergeFields);
                        String subjectVendor = replaceMergeFields(template.Subject, mergeFields);
                        System.debug('✅ Vendor Reminder Email Subject: ' + subjectVendor);
                        emails.add(createDynamicEmail(va.Vendor__r.Email__c, subjectVendor, emailBodyVendor));
                        reminderCount++;
                    }
                } else {
                    System.debug('⚠ Template missing or invalid: Task_Reminder_Email');
                }
            }

            // ✅ Danger Zone Emails (overdue)
            if (daysDiff != null && daysDiff < 0) {
                EmailTemplate supervisorTemplate = templateMap.get('Danger_Zone_Alert_Supervisor');
                EmailTemplate vendorTemplate = templateMap.get('Danger_Zone_Alert_Vendor');

                if (supervisorTemplate != null && String.isNotBlank(supervisorTemplate.HtmlValue) && String.isNotBlank(va.Owner.Email)) {
                    mergeFields.put('{{RecipientName}}', va.Owner.Name);
                    String supBody = replaceMergeFields(supervisorTemplate.HtmlValue, mergeFields);
                    String supSubject = replaceMergeFields(supervisorTemplate.Subject, mergeFields);
                    System.debug('✅ Supervisor Danger Email Subject: ' + supSubject);
                    emails.add(createDynamicEmail(va.Owner.Email, supSubject, supBody));
                    supervisorDangerCount++;
                }

                if (vendorTemplate != null && String.isNotBlank(vendorTemplate.HtmlValue) && String.isNotBlank(va.Vendor__r.Email__c)) {
                    mergeFields.put('{{RecipientName}}', va.Vendor__r.Name);
                    String venBody = replaceMergeFields(vendorTemplate.HtmlValue, mergeFields);
                    String venSubject = replaceMergeFields(vendorTemplate.Subject, mergeFields);
                    System.debug('✅ Vendor Danger Email Subject: ' + venSubject);
                    emails.add(createDynamicEmail(va.Vendor__r.Email__c, venSubject, venBody));
                    vendorDangerCount++;
                }
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
                System.debug('✅ Emails sent successfully: ' + emails.size());
            } catch (Exception e) {
                System.debug('❌ Error sending emails: ' + e.getMessage());
            }
        } else {
            System.debug('⚠ No Emails to Send.');
        }

        System.debug('Total Emails Prepared: ' + emails.size());
        System.debug('Reminder Emails: ' + reminderCount);
        System.debug('Supervisor Danger Emails: ' + supervisorDangerCount);
        System.debug('Vendor Danger Emails: ' + vendorDangerCount);
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch Finished Successfully ✅');
    }

    // ===== Helper: Replace placeholders =====
    private String replaceMergeFields(String template, Map<String, String> mergeFields) {
        String body = template;
        for (String key : mergeFields.keySet()) {
            body = body.replace(key, mergeFields.get(key));
        }
        return body;
    }

    // ===== Helper: Create Email =====
    private Messaging.SingleEmailMessage createDynamicEmail(String toAddress, String subject, String bodyHtml) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toAddress });
        email.setSubject(subject);
        email.setHtmlBody(bodyHtml);
        email.setSaveAsActivity(false);
        if (orgWideEmailId != null) {
            email.setOrgWideEmailAddressId(orgWideEmailId);
        }
        return email;
    }

    // ===== Helper: Get OrgWide Email ID =====
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> listOWEA = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE Address =: Label.Arelia_OWD AND IsAllowAllProfiles = true
            LIMIT 1
        ];
        return listOWEA.isEmpty() ? null : listOWEA[0].Id;
    }

    // ===== Helper: Format Date as '26 Jul 2025' =====
    private String formatDate(Date dt) {
        if (dt == null) return '';
        Datetime dtm = Datetime.newInstance(dt.year(), dt.month(), dt.day(), 0, 0, 0);
        return dtm.format('dd MMM yyyy');
    }
}