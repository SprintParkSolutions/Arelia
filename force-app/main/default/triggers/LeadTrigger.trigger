/**
 * @name        LeadTrigger
 * @description Handles logic after Lead update:
 *              - On Update:
 *                  • When Project_Request_Submitted__c becomes true -> email enrollment/management
 *                  • When Approval_Status__c becomes 'Approved' -> email Lead
 *              - On Supervisor assignment change, call assignment handler in bulk.
 * @version     3.0
 */
trigger LeadTrigger on Lead (before insert, after insert, after update) {// NOPMD
    if (Trigger.isAfter && Trigger.isUpdate) {

        List<Lead> submittedLeads = new List<Lead>();
        List<Lead> approvedLeads  = new List<Lead>();
        List<Lead> leadsForSupervisorAssignment = new List<Lead>();

        for (Lead leadRecord : Trigger.new) {
            Lead oldRecord = Trigger.oldMap.get(leadRecord.Id);

            // 1️⃣ When record is submitted: Project_Request_Submitted__c goes from false -> true
            Boolean wasSubmitted = (oldRecord != null && oldRecord.Project_Request_Submitted__c == true);
            Boolean isSubmitted  = (leadRecord.Project_Request_Submitted__c == true);

            if (isSubmitted && !wasSubmitted) {
                submittedLeads.add(leadRecord);
            }

            // 2️⃣ When record is approved: Approval_Status__c goes from not Approved -> Approved
            String oldStatus = (oldRecord == null) ? null : oldRecord.Approval_Status__c;
            String newStatus = leadRecord.Approval_Status__c;

            if (newStatus == 'Approved' &&
                oldStatus != 'Approved' &&
                String.isNotBlank(leadRecord.Email))
            {
                approvedLeads.add(leadRecord);
            }

            // 3️⃣ Supervisor assignment logic – collect for bulk call
            if (String.isNotBlank(leadRecord.Supervisor_User__c)) {
                String oldSupervisorId = (oldRecord == null) ? null : oldRecord.Supervisor_User__c;
                if (leadRecord.Supervisor_User__c != oldSupervisorId) {
                    leadsForSupervisorAssignment.add(leadRecord);
                }
            }
        }

        // 🔹 Bulk email for submission
        if (!submittedLeads.isEmpty()) {
            LeadEmailHandler.sendEnrollmentEmailOnSubmission(submittedLeads);
        }

        // 🔹 Bulk email for approval
        if (!approvedLeads.isEmpty()) {
            LeadEmailHandler.sendLeadEmailOnApproval(approvedLeads);
        }

        // 🔹 Bulk supervisor assignment handling
        if (!leadsForSupervisorAssignment.isEmpty()) {
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                leadsForSupervisorAssignment,
                Trigger.oldMap
            );
        }
        WhatsAppChatRelinker.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}