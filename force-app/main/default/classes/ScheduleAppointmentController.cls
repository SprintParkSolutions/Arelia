/**
 * @name        ScheduleAppointmentController
 * @description Schedules an appointment and sends email notifications to the Lead and Supervisor.
 *              It updates Appointment Date and Time Slot on the Lead record and ensures data validation.
 *              Utilizes Lightning Email Templates and Org-Wide Email Address for outbound emails.
 * @author      Naresh
 * @createdDate 2025-05-21
 * @version     1.1  (Adds slot availability check to block already-booked slots)
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class ScheduleAppointmentController {

    /**
     * @description Main method to schedule appointment and send emails to Lead and Supervisor.
     * @param leadId         Lead record Id.
     * @param supervisorId   Supervisor user Id. (kept for API compatibility; Supervisor is read from Lead)
     * @param appointmentDate Appointment date as string in 'yyyy-MM-dd' format.
     * @param timeSlot       Selected time slot (picklist value).
     * @throws AuraHandledException for validation or email send failure.
     */
    @AuraEnabled
    public static void scheduleAppointmentAndSendEmails(Id leadId, Id supervisorId, String appointmentDate, String timeSlot,String appointmentType) {
        try {
            validateAppointmentInput(appointmentDate, timeSlot, appointmentType);// ✅ NEW

            Lead lead = fetchLeadDetails(leadId);
            validateLeadFields(lead);

            // 🔒 HARD availability check (same semantics as AppointmentController)
            Date selectedDate = Date.valueOf(appointmentDate);
            String slot = timeSlot == null ? null : timeSlot.trim();
            Id supId = (lead.Supervisor_User__r == null) ? null : lead.Supervisor_User__r.Id;
            if (supId == null) {
                throw new AuraHandledException('Supervisor is missing for this Lead.');
            }

            Integer approvedConflicts = [SELECT COUNT() FROM Lead WHERE Supervisor_User__c = :supId
                  AND Appointment_Status__c = 'Approved' AND Appointment_Date__c = :selectedDate
                  AND Appointment_Time_Slots__c = :slot];

            Integer rescheduledConflicts = [SELECT COUNT() FROM Lead WHERE Supervisor_User__c = :supId
                  AND Appointment_Status__c IN ('Approved','Rescheduled')
                  AND Appointment_Rescheduled_Time__c = :selectedDate AND Time_Slots__c = :slot];

            if ((approvedConflicts + rescheduledConflicts) > 0) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            String formattedDate = selectedDate.format();

            EmailTemplate leadTemplate = fetchTemplate(Label.Arelia_Living_Lead_Site_Visiting_Email_Template);
            EmailTemplate supervisorTemplate = fetchTemplate(Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>{
                prepareLeadEmail(lead, leadTemplate, formattedDate, slot,appointmentType),
                prepareSupervisorEmail(lead, supervisorTemplate, formattedDate, slot,appointmentType)
            };

            handleEmailResults(Messaging.sendEmail(emails, false));

            System.debug('Selected Time Slot Value: ' + slot);

            // Persist booking on Lead
            lead.Appointment_Date__c = selectedDate;
            lead.Appointment_Time_Slots__c = slot;
            lead.Appointment_Confirmation_Type__c = appointmentType; // ✅ NEW
            lead.Appointment_Sent_date__c = System.Today();
            lead.Appointment_Completed__c = false;
            update lead;

        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to send appointment emails: ' + ex.getMessage());
        }
    }

    /**
     * @description Validates appointment date and time slot input.
     * @param appointmentDate Date string.
     * @param timeSlot Time slot picklist value.
     */
    private static void validateAppointmentInput(String appointmentDate, String timeSlot, String appointmentType) {
        if (String.isBlank(appointmentDate)) {
            throw new AuraHandledException('Appointment Date is required.');
        }
        if (String.isBlank(timeSlot)) {
            throw new AuraHandledException('Appointment Time Slot is required.');
        }
        if (String.isBlank(appointmentType)) { // ✅ NEW
            throw new AuraHandledException('Appointment Type is required.');
        }

        Date selectedDate = Date.valueOf(appointmentDate);

        // ❌ Block if selected date is before today
        if (selectedDate < Date.today()) {
            throw new AuraHandledException('You cannot select a past date.');
        }

        // ✅ For today only, validate time slot has not passed (HH:MM optional; AM/PM)
        if (selectedDate == Date.today()) {
            List<String> timeParts = timeSlot.split('-');
            if (!timeParts.isEmpty()) {
                String start = timeParts[0].trim().toUpperCase(); // e.g., "9AM" or "9 AM" or "9:30 AM"

                Pattern p = Pattern.compile('(\\d{1,2})(?::(\\d{2}))?\\s*(AM|PM)');
                Matcher m = p.matcher(start);
                if (m.find()) {
                    Integer hour = Integer.valueOf(m.group(1));
                    Integer minute = (m.group(2) == null) ? 0 : Integer.valueOf(m.group(2));
                    String ampm = m.group(3);

                    if (ampm == 'PM' && hour != 12) hour += 12;
                    if (ampm == 'AM' && hour == 12) hour = 0;

                    DateTime slotTime = DateTime.newInstance(Date.today(), Time.newInstance(hour, minute, 0, 0));
                    if (DateTime.now() >= slotTime) {
                        throw new AuraHandledException('Selected time slot has already passed.');
                    }
                } else {
                    throw new AuraHandledException('Unable to parse time slot format.');
                }
            }
        }
    }

    /**
     * @description Fetches full Lead record with Supervisor fields.
     * @param leadId Lead Id.
     * @return Populated Lead record.
     */
    private static Lead fetchLeadDetails(Id leadId) {
        return [SELECT Id, FirstName, LastName, Email, Appointment_Completed__c,
                   Supervisor_User__r.Name, Supervisor_User__r.Email, Supervisor_User__r.Phone
            FROM Lead WHERE Id = :leadId LIMIT 1];
    }

    /**
     * @description Validates required fields on Lead and Supervisor.
     * @param lead Lead record.
     */
    private static void validateLeadFields(Lead lead) {
        // if (lead.Appointment_Completed__c) {
        //     throw new AuraHandledException('Appointment already scheduled. Please uncheck the "Appointment Completed" field to reschedule.');
        // }
        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('Lead email is missing.');
        }
        if (lead.Supervisor_User__r == null ||
            String.isBlank(lead.Supervisor_User__r.Email) ||
            String.isBlank(lead.Supervisor_User__r.Phone)) {
            throw new AuraHandledException('Supervisor contact details are incomplete.');
        }
    }

    /**
     * @description Fetches EmailTemplate by developer name.
     */
    private static EmailTemplate fetchTemplate(String developerName) {
        return [SELECT Id, HtmlValue, Subject FROM EmailTemplate
            WHERE DeveloperName = :developerName LIMIT 1];
    }

    /**
     * @description Prepares email to be sent to the Lead.
     */
    private static Messaging.SingleEmailMessage prepareLeadEmail(Lead lead, EmailTemplate template, String formattedDate, String timeSlot, String appointmentType) {
        String leadName = lead.FirstName + ' ' + lead.LastName;
        String approvalLink = Label.Arelia_Site_Label+ Label.Site_Appointment_Link_Page + '?id=' + lead.Id;

        String htmlBody = template.HtmlValue
            .replace('{{{Recipient.Name}}}', leadName)
            .replace('{{{Supervisor_User__c.Name}}}', lead.Supervisor_User__r.Name)
            .replace('{{{Supervisor_User__c.Phone}}}', lead.Supervisor_User__r.Phone)
            .replace('{{{Supervisor_User__c.Email}}}', lead.Supervisor_User__r.Email)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{appointmentApprovalLink}}}', approvalLink);

        String subject = template.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', leadName);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        // If you want to actually send to the Lead, uncomment the next line:
        // email.setToAddresses(new String[] { lead.Email });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setTargetObjectId(lead.Id);
        email.setSaveAsActivity(true);
        email.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
        return email;
    }

    /**
     * @description Prepares email to be sent to the Supervisor.
     */
    private static Messaging.SingleEmailMessage prepareSupervisorEmail(Lead lead, EmailTemplate template, String formattedDate, String timeSlot, String appointmentType) {
        String leadName = lead.FirstName + ' ' + lead.LastName;

        String htmlBody = template.HtmlValue
            .replace('{{{Recipient.Name}}}', lead.Supervisor_User__r.Name)
            .replace('{{{leadName}}}', leadName)
            .replace('{{{leadEmail}}}', lead.Email)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType);


        String subject = template.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', leadName);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { lead.Supervisor_User__r.Email });
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);
        email.setTargetObjectId(lead.Id);
        email.setTreatTargetObjectAsRecipient(false);
        email.setSaveAsActivity(true);
        email.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
        return email;
    }

    /**
     * @description Handles result of email sending. Throws exception if any failure.
     */
    private static void handleEmailResults(Messaging.SendEmailResult[] results) {
        for (Messaging.SendEmailResult res : results) {
            if (!res.isSuccess()) {
                Messaging.SendEmailError[] errors = res.getErrors();
                if (errors != null && !errors.isEmpty()) {
                    throw new AuraHandledException('Email failed: ' + errors[0].getMessage());
                }
            }
        }
    }

    /**
     * @description Gets Org-Wide Email Address ID used for outbound emails.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    /**
     * @description Returns list of time slot picklist values from Lead.Time_Slots__c field.
     *              (Kept for compatibility; the LWC now loads available slots by date.)
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Lead.Time_Slots__c.getDescribe().getPicklistValues()) {
            values.add(entry.getLabel());
        }
        return values;
    }

    /**
     * @description ✅ Returns list of Appointment Type picklist values from Lead.Appointment_Confirmation_Type__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAppointmentTypesPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Lead.Appointment_Confirmation_Type__c.getDescribe().getPicklistValues()) {
            values.add(entry.getLabel());
        }
        return values;
    }
}