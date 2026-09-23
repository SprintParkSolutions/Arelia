/**
 * @name        LeadTrigger
 * @description Handles logic after Lead update:
 *              - On Update:
 *                  • When Project_Request_Submitted__c becomes true -> email enrollment/management
 *                  • When Approval_Status__c becomes 'Approved' -> email Lead
 *                  • When appointment fields change -> send appointment emails
 *              - On Supervisor assignment change, call assignment handler in bulk.
 * @version     4.0
 */
trigger LeadTrigger on Lead (before insert, after insert, after update) { // NOPMD

    if (Trigger.isAfter && Trigger.isInsert) {
        List<Lead> areliaInsertedLeads = new List<Lead>();
        for (Lead leadRecord : Trigger.new) {
            if (LeadEmailHandler.isAreliaLead(leadRecord)) {
                areliaInsertedLeads.add(leadRecord);
            }
        }

        if (!areliaInsertedLeads.isEmpty()) {
            LeadEmailHandler.sendRegistrationEmailsOnCreate(areliaInsertedLeads);
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {

        List<Lead> areliaUpdatedLeads = new List<Lead>();
        Map<Id, Lead> areliaOldMap = new Map<Id, Lead>();
        List<Lead> submittedLeads = new List<Lead>();
        List<Lead> approvedLeads  = new List<Lead>();
        List<Lead> leadsForSupervisorAssignment = new List<Lead>();
        List<Lead> appointmentLeads = new List<Lead>();

        for (Lead leadRecord : Trigger.new) {
            Lead oldRecord = Trigger.oldMap.get(leadRecord.Id);

            if (!LeadEmailHandler.isAreliaLead(leadRecord)) {
                continue;
            }

            areliaUpdatedLeads.add(leadRecord);
            areliaOldMap.put(leadRecord.Id, oldRecord);

            // 1. Submission logic
            Boolean wasSubmitted = (oldRecord != null && oldRecord.Project_Request_Submitted__c == true);
            Boolean isSubmitted  = (leadRecord.Project_Request_Submitted__c == true);

            if (isSubmitted && !wasSubmitted) {
                submittedLeads.add(leadRecord);
            }

            // 2. Approval logic
            String oldStatus = (oldRecord == null) ? null : oldRecord.Approval_Status__c;
            String newStatus = leadRecord.Approval_Status__c;

            if (newStatus == 'Approved' &&
                oldStatus != 'Approved' &&
                String.isNotBlank(leadRecord.Email)) {
                approvedLeads.add(leadRecord);
            }

            // 3. Supervisor assignment logic
            if (String.isNotBlank(leadRecord.Supervisor_User__c)) {
                String oldSupervisorId = (oldRecord == null) ? null : oldRecord.Supervisor_User__c;
                if (leadRecord.Supervisor_User__c != oldSupervisorId) {
                    leadsForSupervisorAssignment.add(leadRecord);
                }
            }

            // 4. Appointment email logic
            if (LeadAppointmentEmailHandler.shouldSendAppointmentEmail(leadRecord, oldRecord)) {
                appointmentLeads.add(leadRecord);
            }
        }

        if (!submittedLeads.isEmpty()) {
            LeadEmailHandler.sendEnrollmentEmailOnSubmission(submittedLeads);
        }

        if (!approvedLeads.isEmpty()) {
            LeadEmailHandler.sendLeadEmailOnApproval(approvedLeads);
        }

        if (!leadsForSupervisorAssignment.isEmpty()) {
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                leadsForSupervisorAssignment,
                areliaOldMap
            );
        }

        if (!appointmentLeads.isEmpty()) {
            LeadAppointmentEmailHandler.sendAppointmentEmailsOnUpdate(appointmentLeads);
        }

        if (!areliaUpdatedLeads.isEmpty()) {
            WhatsAppChatRelinker.onAfterUpdate(areliaUpdatedLeads, areliaOldMap);
        }
    }
}