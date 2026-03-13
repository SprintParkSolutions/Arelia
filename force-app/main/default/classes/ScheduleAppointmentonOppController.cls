/**
 * @name        ScheduleAppointmentonOppController
 * @description Schedule an appointment from Opportunity and send emails to the client & supervisor.
 *              - Validates date, slot, and type
 *              - Prevents booking a taken slot (Approved/Rescheduled) for the same Supervisor
 *              - Writes the appointment on Opportunity
 * @author      Naresh
 * @version     1.0
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class ScheduleAppointmentonOppController {


    @AuraEnabled
    public static void scheduleAppointmentAndSendEmails(Id opportunityId,String appointmentDate,String timeSlot,String appointmentType) 
    {
        try {
            validateAppointmentInput(appointmentDate, timeSlot, appointmentType);

            Opportunity opp = fetchOpp(opportunityId);
            validateOppFields(opp);

            // HARD availability check (same semantics you had on Lead)
            Date selectedDate = Date.valueOf(appointmentDate);
            String slot = timeSlot == null ? null : timeSlot.trim();
            Id supervisorId = opp.Supervisor_User__c;
            ensureSupervisor(supervisorId);

            Integer approvedConflicts = [SELECT COUNT() FROM Opportunity
                WHERE Supervisor_User__c = :supervisorId
                  AND Re_Visit_Site_Appointment_Status__c = 'Approved'
                  AND Re_Visit_Appointment_Date__c   = :selectedDate
                  AND Re_Visit_Appointment_Time_Slots__c = :slot];

            Integer rescheduledConflicts = [SELECT COUNT() FROM Opportunity
                WHERE Supervisor_User__c = :supervisorId
                  AND Re_Visit_Site_Appointment_Status__c IN ('Approved','Rescheduled')
                  AND Re_Visit_Appointment_Rescheduled_Date__c = :selectedDate
                  AND Re_Visit_Appointm_Rescheduled_Time_Slots__c = :slot];

            if ((approvedConflicts + rescheduledConflicts) > 0) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            String formattedDate = selectedDate.format();

            // Re-use your templates by developer name.
            // (You’re replacing tokens manually, so they don’t have to be Opportunity-specific.)
            EmailTemplate clientTpl     = fetchTemplate(Label.Arelia_Living_Lead_Site_Re_Visiting_Email_Template);
            EmailTemplate supervisorTpl = fetchTemplate(Label.Arelia_Living_Supervisor_Site_Re_Visiting_Email_Template);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>{
                prepareClientEmail(opp, clientTpl, formattedDate, slot, appointmentType),
                prepareSupervisorEmail(opp, supervisorTpl, formattedDate, slot, appointmentType)
            };

            handleEmailResults(Messaging.sendEmail(emails, false));

            // Persist booking on Opportunity
            opp.Re_Visit_Appointment_Date__c = selectedDate;
            opp.Re_Visit_Appointment_Time_Slots__c  = slot;
            opp.Re_Visit_Appointmnet_Confirmation__c   = true;
            opp.Re_Visit_Site_Appointment_Type__c = appointmentType;
            opp.Re_Visit_Site_Appointment_Status__c = 'Pending';
            opp.Appointment_Status__c = 'Re-Visit';
            update opp;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to send appointment emails: ' + e.getMessage());
        }
    }

    /**
     * Available slots for a specific day and the current Opportunity’s Supervisor.
     * Removes slots already booked (Approved/Rescheduled).
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableTimeSlotsOpp(Date forDate, Id currentOppId) {
        if (forDate == null || currentOppId == null) {return new List<String>();}

        Opportunity opp = [SELECT Id, Supervisor_User__c FROM Opportunity WHERE Id = :currentOppId LIMIT 1];
        ensureSupervisor(opp.Supervisor_User__c);

        // Start with the picklist values defined on Opportunity.Appointment_Time_Slots__c
        Set<String> all = new Set<String>();
        for (Schema.PicklistEntry e : Opportunity.Re_Visit_Appointment_Time_Slots__c.getDescribe().getPicklistValues()) {
            all.add(e.getLabel());
        }
        if (all.isEmpty()) {return new List<String>();}

        // Remove slots that are taken for this supervisor on this date
        for (Opportunity o : [SELECT Re_Visit_Appointment_Time_Slots__c, Rescheduled_Time_Slots__c, Appointment_Status__c,
                   Re_Visit_Appointment_Date__c, Appointment_Rescheduled_Date__c
              FROM Opportunity WHERE Supervisor_User__c = :opp.Supervisor_User__c
               AND (
                        (Appointment_Status__c = 'Approved'
                         AND Re_Visit_Appointment_Date__c = :forDate)
                     OR (Appointment_Status__c IN ('Approved','Rescheduled')
                         AND Appointment_Rescheduled_Date__c = :forDate)
                   )
        ]) {
            if (o.Appointment_Status__c == 'Approved' && String.isNotBlank(o.Re_Visit_Appointment_Time_Slots__c)) {
                all.remove(o.Re_Visit_Appointment_Time_Slots__c.trim());
            }
            if (o.Appointment_Status__c != null && String.isNotBlank(o.Rescheduled_Time_Slots__c)) {
                all.remove(o.Rescheduled_Time_Slots__c.trim());
            }
        }
        return new List<String>(all);
    }

    // Expose picklists for the LWC

    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Opportunity.Re_Visit_Appointment_Time_Slots__c.getDescribe().getPicklistValues()) {
            values.add(e.getLabel());
        }
        return values;
    }

    // Using the field visible in screenshots for "type" on Opportunity.
    @AuraEnabled(cacheable=true)
    public static List<String> getAppointmentTypesPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : Opportunity.Re_Visit_Site_Appointment_Type__c.getDescribe().getPicklistValues()) {
            values.add(e.getLabel());
        }
        return values;
    }

    // ===== Helpers =====

    private static Opportunity fetchOpp(Id oppId) {
        return [SELECT Id, Name, Email__c, Supervisor_User__c, Supervisor_User__r.Name, Supervisor_User__r.Email, 
                Supervisor_User__r.Phone, Re_Visit_Appointmnet_Confirmation__c, Lead_Name__c, IsWon FROM Opportunity WHERE Id = :oppId LIMIT 1];
    }

    private static void validateOppFields(Opportunity opp) {
         if (opp.IsWon == true) {
            throw new AuraHandledException('This Opportunity is Closed Won. Scheduling is not allowed.');
        }
        
        if (opp.Re_Visit_Appointmnet_Confirmation__c == true) {
            throw new AuraHandledException('Appointment already scheduled. Please uncheck "Appointment Confirmed" to reschedule.');
        }
        if (String.isBlank(opp.Email__c)) {
            throw new AuraHandledException('Client email on Opportunity is missing.');
        }
        if (opp.Supervisor_User__c == null ||
            opp.Supervisor_User__r == null ||
            String.isBlank(opp.Supervisor_User__r.Email) ||
            String.isBlank(opp.Supervisor_User__r.Phone)) {
            throw new AuraHandledException('Supervisor contact details are incomplete.');
        }
    }

    private static void ensureSupervisor(Id supId) {
        if (supId == null) {
            throw new AuraHandledException('Supervisor is missing for this Opportunity.');
        }
    }

    private static EmailTemplate fetchTemplate(String developerName) {
        return [SELECT Id, HtmlValue, Subject FROM EmailTemplate
                 WHERE DeveloperName = :developerName LIMIT 1];
    }

    private static Messaging.SingleEmailMessage prepareClientEmail(Opportunity opp, EmailTemplate tpl, String formattedDate,
                                                                        String timeSlot, String appointmentType) 
    {
        String clientName = opp.Lead_Name__c; // or derive from Primary Contact if you have it
        String approvalLink = Label.Arelia_Site_Label+ Label.Site_Appointment_Opp_Link_Page + '?id=' + opp.Id;
        String html = tpl.HtmlValue
            .replace('{{{Recipient.Name}}}', clientName)
            .replace('{{{Supervisor_User__c.Name}}}', opp.Supervisor_User__r.Name)
            .replace('{{{Supervisor_User__c.Phone}}}', opp.Supervisor_User__r.Phone)
            .replace('{{{Supervisor_User__c.Email}}}', opp.Supervisor_User__r.Email)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{appointmentApprovalLink}}}', approvalLink);

        String subject = tpl.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', clientName);

        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ opp.Email__c.trim() });
        m.setSubject(subject);
        m.setHtmlBody(html);
        m.setWhatId(opp.Id);
        m.setSaveAsActivity(true);
        m.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
        return m;
    }

    private static Messaging.SingleEmailMessage prepareSupervisorEmail(Opportunity opp, EmailTemplate tpl, String formattedDate,
                                                                            String timeSlot, String appointmentType) 
    {
        String clientName = opp.Lead_Name__c;

        String html = tpl.HtmlValue
            .replace('{{{Recipient.Name}}}', opp.Supervisor_User__r.Name)
            .replace('{{{leadName}}}', clientName)
            .replace('{{{leadEmail}}}', opp.Email__c)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType);

        String subject = tpl.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', clientName);

        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ opp.Supervisor_User__r.Email.trim() });
        m.setSubject(subject);
        m.setHtmlBody(html);
        m.setWhatId(opp.Id);
        m.setSaveAsActivity(true);
        m.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());
        return m;
    }

    private static void handleEmailResults(Messaging.SendEmailResult[] results) {
        for (Messaging.SendEmailResult r : results) {
            if (!r.isSuccess()) {
                Messaging.SendEmailError[] errs = r.getErrors();
                if (errs != null && !errs.isEmpty()) {
                    throw new AuraHandledException('Email failed: ' + errs[0].getMessage());
                }
            }
        }
    }

    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> listOWEA = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD
                                                AND IsAllowAllProfiles = true LIMIT 1];
        return listOWEA.isEmpty() ? null : listOWEA[0].Id;
    }

    // Input validation (date in future, today’s slot not in the past, etc.)
    private static void validateAppointmentInput(String appointmentDate, String timeSlot, String appointmentType) {
        if (String.isBlank(appointmentDate)) {
            throw new AuraHandledException('Appointment Date is required.');
        }
        if (String.isBlank(timeSlot)) {
            throw new AuraHandledException('Appointment Time Slot is required.');
        }
        if (String.isBlank(appointmentType)) {
            throw new AuraHandledException('Appointment Type is required.');
        }

        Date selectedDate = Date.valueOf(appointmentDate);

        if (selectedDate < Date.today()) {
            throw new AuraHandledException('You cannot select a past date.');
        }

        if (selectedDate == Date.today()) {
            List<String> parts = timeSlot.split('-');
            if (!parts.isEmpty()) {
                String start = parts[0].trim().toUpperCase(); // e.g., 9 AM / 9:30 AM

                Pattern p = Pattern.compile('(\\d{1,2})(?::(\\d{2}))?\\s*(AM|PM)');
                Matcher m = p.matcher(start);
                if (m.find()) {
                    Integer hour   = Integer.valueOf(m.group(1));
                    Integer minute = (m.group(2) == null) ? 0 : Integer.valueOf(m.group(2));
                    String ampm    = m.group(3);

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
}