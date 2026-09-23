/**
 * @name        ScheduleAppointmentController
 * @description Schedules an appointment only.
 *              Email sending is handled by Lead trigger.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class ScheduleAppointmentController {

    @AuraEnabled
    public static void scheduleAppointmentAndSendEmails(Id leadId,Id supervisorId,
        String appointmentDate,String timeSlot,String appointmentType)
    {
        try {
            validateAppointmentInput(appointmentDate, timeSlot, appointmentType);

            Lead lead = fetchLeadDetails(leadId);
            validateLeadFields(lead);

            Date selectedDate = Date.valueOf(appointmentDate);
            String slot = timeSlot == null ? null : timeSlot.trim();
            Id supId = (lead.Supervisor_User__r == null) ? null : lead.Supervisor_User__r.Id;

            if (supId == null) {
                throw new AuraHandledException('Supervisor is missing for this Lead.');
            }

            Integer approvedConflicts = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supId AND Appointment_Status__c = 'Approved'
                AND Appointment_Date__c = :selectedDate AND Appointment_Time_Slots__c = :slot];

            Integer rescheduledConflicts = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supId AND Appointment_Status__c IN ('Approved','Rescheduled')
                AND Appointment_Rescheduled_Time__c = :selectedDate
                AND Time_Slots__c = :slot];

            if ((approvedConflicts + rescheduledConflicts) > 0) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            lead.Appointment_Date__c = selectedDate;
            lead.Appointment_Time_Slots__c = slot;
            lead.Appointment_Confirmation_Type__c = appointmentType;
            lead.Appointment_Completed__c = false;

            update lead;

        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to schedule appointment: ' + ex.getMessage());
        }
    }

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
            validateTodayTimeSlot(timeSlot);
        }
    }

    private static void validateTodayTimeSlot(String timeSlot) {
        String startTime = extractStartTime(timeSlot);
        Time parsedTime = parseStartTime(startTime);
        DateTime slotDateTime = DateTime.newInstance(Date.today(), parsedTime);

        if (isPastSlot(slotDateTime)) {
            throw new AuraHandledException('Selected time slot has already passed.');
        }
    }

    private static String extractStartTime(String timeSlot) {
        List<String> timeParts = timeSlot.split('-');
        if (timeParts.isEmpty()) {
            throw new AuraHandledException('Unable to parse time slot format.');
        }
        return timeParts[0].trim().toUpperCase();
    }

    private static Time parseStartTime(String startTime) {
        Pattern p = Pattern.compile('(\\d{1,2})(?::(\\d{2}))?\\s*(AM|PM)');
        Matcher m = p.matcher(startTime);

        if (!m.find()) {
            throw new AuraHandledException('Unable to parse time slot format.');
        }

        Integer hour = Integer.valueOf(m.group(1));
        Integer minute = (m.group(2) == null) ? 0 : Integer.valueOf(m.group(2));
        String ampm = m.group(3);

        hour = convertTo24Hour(hour, ampm);

        return Time.newInstance(hour, minute, 0, 0);
    }

    private static Integer convertTo24Hour(Integer hour, String ampm) {
        if (ampm == 'PM' && hour != 12) {
            return hour + 12;
        }
        if (ampm == 'AM' && hour == 12) {
            return 0;
        }
        return hour;
    }

    private static Boolean isPastSlot(DateTime slotDateTime) {
        return DateTime.now() >= slotDateTime;
    }

    private static Lead fetchLeadDetails(Id leadId) {
        return [
            SELECT Id, FirstName, LastName, Email, Appointment_Completed__c,
                   Supervisor_User__c, Supervisor_User__r.Id, Supervisor_User__r.Name,
                   Supervisor_User__r.Email, Supervisor_User__r.Phone
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
    }

    private static void validateLeadFields(Lead lead) {
        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('Lead email is missing.');
        }
        if (lead.Supervisor_User__r == null ||
            String.isBlank(lead.Supervisor_User__r.Email) ||
            String.isBlank(lead.Supervisor_User__r.Phone)) {
            throw new AuraHandledException('Supervisor contact details are incomplete.');
        }
    }

   @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Lead.Appointment_Time_Slots__c.getDescribe().getPicklistValues()) {
            values.add(entry.getLabel());
        }
        return values;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getAppointmentTypesPicklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : Lead.Appointment_Confirmation_Type__c.getDescribe().getPicklistValues()) {
            values.add(entry.getLabel());
        }
        return values;
    }
}