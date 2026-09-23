/**
 * @name        LeadAppointmentEmailHandler
 * @description Decides when appointment email should be sent.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class LeadAppointmentEmailHandler {

    private static Boolean isRunning = false;

    public static Boolean shouldSendAppointmentEmail(Lead newLead, Lead oldLead) {
        if (newLead == null || oldLead == null) {
            return false;
        }

        // Required fields must be populated
        Boolean hasRequiredFields =
            newLead.Appointment_Date__c != null &&
            String.isNotBlank(newLead.Appointment_Time_Slots__c) &&
            String.isNotBlank(newLead.Appointment_Confirmation_Type__c) &&
            String.isNotBlank(newLead.Email) &&
            String.isNotBlank(newLead.Supervisor_User__c);

        if (!hasRequiredFields) {
            return false;
        }

        // Send when any appointment-driving field changes
        Boolean appointmentChanged =
            oldLead.Appointment_Date__c != newLead.Appointment_Date__c ||
            oldLead.Appointment_Time_Slots__c != newLead.Appointment_Time_Slots__c ||
            oldLead.Appointment_Confirmation_Type__c != newLead.Appointment_Confirmation_Type__c;

        return appointmentChanged;
    }

    public static void sendAppointmentEmailsOnUpdate(List<Lead> leadsFromTrigger) {
        if (isRunning || leadsFromTrigger == null || leadsFromTrigger.isEmpty()) {
            return;
        }

        isRunning = true;

        Set<Id> leadIds = new Set<Id>();
        for (Lead l : leadsFromTrigger) {
            if (l.Id != null) {
                leadIds.add(l.Id);
            }
        }

        if (!leadIds.isEmpty()) {
            LeadAppointmentEmailService.sendAppointmentEmails(new List<Id>(leadIds));
        }
    }
}