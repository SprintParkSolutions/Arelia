/**
 * @name LeadTrigger
 * @description Central Lead trigger for Arelia functionality.
 *
 * Appointment responses are handled globally regardless
 * of whether the update comes from:
 *
 * - LWC
 * - Flutter / Mobile
 * - REST API
 * - Flow
 * - Apex
 * - Salesforce UI
 *
 * Supported customer appointment responses:
 * - Approved
 * - Rescheduled
 *
 * @version 5.0
 */
trigger LeadTrigger on Lead (before insert,before update,after insert,after update) { // NOPMD

    // =========================================================
    // BEFORE UPDATE
    // GLOBAL APPOINTMENT RESPONSE
    // =========================================================

    if (Trigger.isBefore && Trigger.isUpdate ) {
        LeadAppointmentResponseHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }

    // =========================================================
    // AFTER INSERT
    // =========================================================

    if (Trigger.isAfter && Trigger.isInsert) {
        List<Lead> areliaInsertedLeads = new List<Lead>();
        for (Lead leadRecord : Trigger.new ) {
            if (LeadEmailHandler.isAreliaLead(leadRecord)) {
                areliaInsertedLeads.add(leadRecord);
            }
        }
        if (!areliaInsertedLeads.isEmpty()) {
            LeadEmailHandler.sendRegistrationEmailsOnCreate(areliaInsertedLeads);
        }
    }

    // =========================================================
    // AFTER UPDATE
    // =========================================================

    if (Trigger.isAfter && Trigger.isUpdate ) {
        
        List<Lead> areliaUpdatedLeads = new List<Lead>();
        Map<Id, Lead> areliaOldMap = new Map<Id, Lead>();
        List<Lead> submittedLeads = new List<Lead>();
        List<Lead> approvedLeads = new List<Lead>();
        List<Lead> leadsForSupervisorAssignment = new List<Lead>();
        List<Lead> appointmentLeads = new List<Lead>();

        for(Lead leadRecord : Trigger.new) {
            Lead oldRecord = Trigger.oldMap.get( leadRecord.Id );
            if (!LeadEmailHandler.isAreliaLead(leadRecord)) {
                continue;
            }
            areliaUpdatedLeads.add(leadRecord);
            areliaOldMap.put(leadRecord.Id,oldRecord);
            
            // =================================================
            // 1. PROJECT REQUEST SUBMITTED
            // =================================================

            Boolean wasSubmitted =oldRecord != null && oldRecord.Project_Request_Submitted__c == true;
            Boolean isSubmitted = leadRecord.Project_Request_Submitted__c == true;
            
            if (isSubmitted && !wasSubmitted) {
                submittedLeads.add(leadRecord);
            }
            // =================================================
            // 2. MANAGEMENT APPROVAL
            // =================================================
            String oldApprovalStatus = oldRecord == null ? null : oldRecord.Approval_Status__c;
            String newApprovalStatus = leadRecord.Approval_Status__c;
            
            if(newApprovalStatus =='Approved' && oldApprovalStatus != 'Approved' && String.isNotBlank( leadRecord.Email)) {
                approvedLeads.add(leadRecord);
            }

            // =================================================
            // 3. SUPERVISOR ASSIGNMENT
            // =================================================
            if (String.isNotBlank(leadRecord.Supervisor_User__c)) {
                
                String oldSupervisorId = oldRecord == null ? null : oldRecord.Supervisor_User__c;
                
                if (leadRecord.Supervisor_User__c != oldSupervisorId) {
                    leadsForSupervisorAssignment.add(leadRecord);
                }
            }

            // =================================================
            // 4. INITIAL APPOINTMENT EMAIL
            // =================================================
            /*
             * IMPORTANT:
             * Customer Approve / Reschedule response
             * must NOT enter the existing initial
             * appointment email handler.
             * This protects against duplicate emails.
             */
            Boolean customerResponse = LeadAppointmentResponseHandler.isCustomerResponseTransition(leadRecord,oldRecord);

            if (!customerResponse && LeadAppointmentEmailHandler.shouldSendAppointmentEmail(leadRecord,oldRecord)) {
                    appointmentLeads.add(leadRecord);
            }
        }

        // =====================================================
        // PROJECT SUBMISSION EMAIL
        // =====================================================
        if (!submittedLeads.isEmpty()) {
            LeadEmailHandler.sendEnrollmentEmailOnSubmission(submittedLeads);
        }

        // =====================================================
        // MANAGEMENT APPROVAL EMAIL
        // =====================================================

        if (!approvedLeads.isEmpty()) {
            LeadEmailHandler.sendLeadEmailOnApproval(approvedLeads);
        }

        // =====================================================
        // SUPERVISOR ASSIGNMENT EMAIL
        // =====================================================
        if (!leadsForSupervisorAssignment.isEmpty()) {
            LeadAssignmentEmailHandler.handleSupervisorAssignment(leadsForSupervisorAssignment,areliaOldMap);
        }

        // =====================================================
        // INITIAL APPOINTMENT EMAIL
        // =====================================================
        if (!appointmentLeads.isEmpty()) {
            LeadAppointmentEmailHandler.sendAppointmentEmailsOnUpdate(appointmentLeads);
        }
        
        // =====================================================
        // 5. GLOBAL APPROVE / RESCHEDULE RESPONSE EMAIL
        // =====================================================
        LeadAppointmentResponseHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        
        // =====================================================
        // 6. WHATSAPP RELINK
        // =====================================================

        if (!areliaUpdatedLeads.isEmpty()) {
            WhatsAppChatRelinker.onAfterUpdate(areliaUpdatedLeads,areliaOldMap);
        }
    }
}