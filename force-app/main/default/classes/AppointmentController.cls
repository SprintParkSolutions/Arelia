/**
 * @name        AppointmentController
 * @description Enforces Supervisor/Date/Slot availability across Pending holds, Approved,
 *              and all Rescheduled variants. Also handles approval/reschedule updates and
 *              supervisor email notifications.
 *
 * Slot is BLOCKED when ANY Lead (same Supervisor) has:
 *   - Approved with (Appointment_Date__c + Appointment_Time_Slots__c)
 *   - Rescheduled-like (Rescheduled / Appointment Rescheduled / Appointment RescheduledStatus)
 *       with (Appointment_Rescheduled_Time__c + Time_Slots__c)
 *       OR with initial (Appointment_Date__c + Appointment_Time_Slots__c) still populated
 *   - Pending with initial (Appointment_Date__c + Appointment_Time_Slots__c) populated
 *
 * @author      Arelia Living
 * @version     1.0
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class AppointmentController {

    // ---------------------------
    // Constants (PMD friendly)
    // ---------------------------
    private static final String STATUS_PENDING                      = 'Pending';
    private static final String STATUS_APPROVED                     = 'Approved';
    private static final String STATUS_RESCHEDULED                  = 'Rescheduled';
    private static final String STATUS_APPT_RESCHEDULED             = 'Appointment Rescheduled';

    // Any status that should behave like "Rescheduled"
    private static final Set<String> RESCHEDULE_STATUSES = new Set<String>{
        STATUS_RESCHEDULED,
        STATUS_APPT_RESCHEDULED
    };

    // Approved + all reschedule variants
    private static final Set<String> APPROVED_OR_RESCHEDULED = new Set<String>{
        STATUS_APPROVED,
        STATUS_RESCHEDULED,
        STATUS_APPT_RESCHEDULED
    };

    private static final String TEMPLATE_APPROVED    = Label.Arelia_Living_Appointment_Approved_Email;
    private static final String TEMPLATE_RESCHEDULED = Label.Arelia_Living_Appointment_Rescheduled_Email;

    private static final String TEMPLATE_CUSTOMER_APPROVED    = Label.Customer_Appointment_Approved_Email;
    private static final String TEMPLATE_CUSTOMER_RESCHEDULED = Label.Customer_Appointment_Rescheduled_Email;

    /**
     * Updates appointment status:
     *  - Approved: keep initial (date/slot), clear reschedule fields
     *  - Rescheduled (any variant): require date+slot, validate availability, clear initial fields, store reschedule fields
     * Guard: allow only if existing is Pending / Appointment Rescheduled / Appointment RescheduledStatus
     */
    @AuraEnabled
    public static void updateAppointmentStatus(
        Id    leadId,
        String status,
        String rejectionReason,
        Date  rescheduleDate,
        String timeSlot
    ) {
        enforceNotBlankId(leadId, 'Lead ID is missing.');
        enforceNotBlank(status, 'Status is required.');

        Lead leadRecord = [SELECT Id, FirstName, LastName, Email, Appointment_Status__c,Appointment_Completed__c,
            Appointment_Date__c, Appointment_Time_Slots__c, Appointment_Rescheduled_Time__c, Time_Slots__c,
            Supervisor_User__c, Supervisor_User__r.Email FROM Lead WHERE Id = :leadId LIMIT 1];

        final String existing = leadRecord.Appointment_Status__c;
        if (String.isNotBlank(existing)
            && !(existing == STATUS_PENDING
                 || existing == STATUS_APPT_RESCHEDULED)) {
            throw new AuraHandledException('Your response was already submitted as ' + existing + '. Further changes are not allowed.');
        }

        final String normalized = normalizeStatus(status);

        if (normalized == STATUS_APPROVED) {
            leadRecord.Appointment_Status__c           = STATUS_APPROVED;
            leadRecord.Appointment_Rescheduled_Time__c = null;
            leadRecord.Time_Slots__c                   = null;
            leadRecord.Appointment_Completed__c = true;
        } else if (RESCHEDULE_STATUSES.contains(normalized)) {
            enforceNotNull(rescheduleDate, 'Please select both a date and a time slot.');
            enforceNotBlank(timeSlot, 'Please select both a date and a time slot.');
            final String trimmedSlot = sanitizeSlot(timeSlot);

            // Strict availability on reschedule destination
            if (!isSlotAvailableForSupervisor(leadRecord.Supervisor_User__c, rescheduleDate, trimmedSlot)) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            // Save reschedule fields; clear initial
            leadRecord.Appointment_Status__c           = STATUS_RESCHEDULED; // normalize persisted value
            leadRecord.Appointment_Date__c             = null;
            leadRecord.Appointment_Time_Slots__c       = null;
            leadRecord.Appointment_Rescheduled_Time__c = rescheduleDate;
            leadRecord.Time_Slots__c                   = trimmedSlot;
            leadRecord.Appointment_Completed__c = true;
        } else {
            throw new AuraHandledException('Unsupported status: ' + status);
        }

        update leadRecord;

        sendNotifications(leadRecord, leadRecord.Appointment_Status__c);
    }

    /**
     * Returns available slot labels for a given date & the current lead's Supervisor.
     * Blocks slots that match ANY of:
     *  (1) Approved initial pair
     *  (2) Rescheduled-like reschedule pair
     *  (3) Rescheduled-like initial pair (if still populated)
     *  (4) Pending initial pair
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableTimeSlots(Date forDate, Id currentLeadId) {
        enforceNotNull(forDate, 'Please select a date first.');
        enforceNotBlankId(currentLeadId, 'Lead ID is missing.');

        Lead currentLead = [SELECT Id, Supervisor_User__c FROM Lead WHERE Id = :currentLeadId LIMIT 1];

        List<String> allSlots = getPicklistValues(Lead.Time_Slots__c);
        if (allSlots.isEmpty()) {
            return allSlots;
        }

        Set<String> taken = new Set<String>();

        // (A) Reschedule pair blocked: (reschedule date + Time_Slots__c) for any Approved/Rescheduled-like
        for (AggregateResult arA : [SELECT Time_Slots__c slot FROM Lead
                WHERE Supervisor_User__c = :currentLead.Supervisor_User__c
                AND Appointment_Rescheduled_Time__c = :forDate
                AND Time_Slots__c != null AND Appointment_Status__c IN :APPROVED_OR_RESCHEDULED
                GROUP BY Time_Slots__c])
        {
            taken.add(sanitizeSlot((String)arA.get('slot')));
        }

        // (B) Initial pair blocked for Approved AND Rescheduled-like (KEY FIX)
        for (AggregateResult arB : [SELECT Appointment_Time_Slots__c slot FROM Lead
                        WHERE Supervisor_User__c = :currentLead.Supervisor_User__c
                        AND Appointment_Date__c = :forDate AND Appointment_Time_Slots__c != null
                        AND Appointment_Status__c IN :APPROVED_OR_RESCHEDULED
                        GROUP BY Appointment_Time_Slots__c])
        {
            taken.add(sanitizeSlot((String)arB.get('slot')));
        }

        // (C) Pending initial pair holds
        for (AggregateResult arC : [SELECT Appointment_Time_Slots__c slot FROM Lead
                    WHERE Supervisor_User__c = :currentLead.Supervisor_User__c
                    AND Appointment_Date__c = :forDate AND Appointment_Time_Slots__c != null
                    AND Appointment_Status__c = :STATUS_PENDING GROUP BY Appointment_Time_Slots__c])
        {
            taken.add(sanitizeSlot((String)arC.get('slot')));
        }

        List<String> available = new List<String>();
        for (String s : allSlots) {
            String key = sanitizeSlot(s);
            if (!taken.contains(key)) {
                // Return original label to preserve UI fidelity/casing
                available.add(s);
            }
        }
        return available;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        return getPicklistValues(Lead.Time_Slots__c);
    }

    /**
     * True only if destination (Supervisor + onDate + slot) has NO conflicts across:
     *  - Approved initial pair
     *  - Rescheduled-like reschedule pair
     *  - Rescheduled-like initial pair (if present)
     *  - Pending initial pair
     */
    private static Boolean isSlotAvailableForSupervisor(Id supervisorUserId, Date onDate, String slotLabel) {
        if (supervisorUserId == null || onDate == null || String.isBlank(slotLabel)) {
            return false;
        }
        final String slot = sanitizeSlot(slotLabel);

        // Approved initial pair
        Integer approvedInitial = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supervisorUserId AND Appointment_Status__c = :STATUS_APPROVED
              AND Appointment_Date__c = :onDate AND Appointment_Time_Slots__c = :slot];

        // Rescheduled-like reschedule pair OR Approved referencing reschedule fields
        Integer reschedPair = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supervisorUserId AND Appointment_Status__c IN :APPROVED_OR_RESCHEDULED
                AND Appointment_Rescheduled_Time__c = :onDate AND Time_Slots__c = :slot];

        // Rescheduled-like initial pair (if still populated)
        Integer reschedInitial = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supervisorUserId AND Appointment_Status__c IN :RESCHEDULE_STATUSES
                AND Appointment_Date__c = :onDate AND Appointment_Time_Slots__c = :slot];

        // Pending initial pair
        Integer pendingInitial = [SELECT COUNT() FROM Lead
                WHERE Supervisor_User__c = :supervisorUserId AND Appointment_Status__c = :STATUS_PENDING
                AND Appointment_Date__c = :onDate AND Appointment_Time_Slots__c = :slot];

        return (approvedInitial + reschedPair + reschedInitial + pendingInitial) == 0;
    }

    /** Get picklist labels for a field. */
    private static List<String> getPicklistValues(Schema.sObjectField fieldRef) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry e : fieldRef.getDescribe().getPicklistValues()) {
            values.add(e.getLabel());
        }
        return values;
    }

    private static void sendNotifications(Lead ld, String finalStatus) {
        // ---------------------------
        // 1) Supervisor email (internal template)
        //    - Use TO address = Supervisor email
        //    - Use TargetObjectId = Lead.Id (for Lead merge fields)
        //    - TreatTargetObjectAsRecipient = false
        //    - NO WhatId (avoid error)
        // ---------------------------
        if (ld.Supervisor_User__r != null && !String.isBlank(ld.Supervisor_User__r.Email)) {
            String supervisorTpl = (finalStatus == STATUS_APPROVED)
                ? TEMPLATE_APPROVED
                : TEMPLATE_RESCHEDULED;

            sendToEmailWithLeadTemplate(ld,ld.Supervisor_User__r.Email,supervisorTpl);
        }

        // ---------------------------
        // 2) Customer email (customer template)
        //    - TargetObjectId = Lead.Id (Lead recipient)
        //    - TreatTargetObjectAsRecipient = true
        // ---------------------------
        if (!String.isBlank(ld.Email)) {
            String customerTpl = (finalStatus == STATUS_APPROVED)
                ? TEMPLATE_CUSTOMER_APPROVED
                : TEMPLATE_CUSTOMER_RESCHEDULED;

            sendToLeadRecipientWithTemplate(ld, customerTpl);
        }
    }

    /**
     * Supervisor email:
     * - Sends using a template
     * - Recipient is a plain email address (Supervisor email)
     * - Template merges from Lead because TargetObjectId = Lead.Id
     */
    private static void sendToEmailWithLeadTemplate(Lead ld, String toEmail, String templateDevName) {
        if (ld == null || String.isBlank(toEmail) || String.isBlank(templateDevName)) {
            return;
        }

        Id tplId = getTemplateIdByDevName(templateDevName);
        if (tplId == null) {
            return;
        }

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });

        // Lead merge fields work because target is Lead
        msg.setTargetObjectId(ld.Id);
        msg.setTreatTargetObjectAsRecipient(false);

        // Do NOT set WhatId here (causes error for UserId scenarios)
        msg.setTemplateId(tplId);
        msg.setSaveAsActivity(true);
        msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /**
     * Customer email:
     * - Recipient is the Lead itself
     * - Works perfectly with Lead email templates
     */
    private static void sendToLeadRecipientWithTemplate(Lead ld, String templateDevName) {
        if (ld == null || String.isBlank(ld.Email) || String.isBlank(templateDevName)) {
            return;
        }

        Id tplId = getTemplateIdByDevName(templateDevName);
        if (tplId == null) { return;}

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setTargetObjectId(ld.Id);
        msg.setTreatTargetObjectAsRecipient(true);

        msg.setTemplateId(tplId);
        msg.setSaveAsActivity(true);
        msg.setOrgWideEmailAddressId(getDefaultOrgWideEmailAddressId());

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    private static Id getTemplateIdByDevName(String devName) {
        List<EmailTemplate> tpls = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :devName LIMIT 1];
        return tpls.isEmpty() ? null : tpls[0].Id;
    }

    /** Resolve Org-Wide Email Address by label value. */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> owd = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return owd.isEmpty() ? null : owd[0].Id;
    }

    // ---------------------------
    // Tiny utilities (help PMD)
    // ---------------------------
    private static String normalizeStatus(String s) {
        if (String.isBlank(s)) {return s;}
        String t = s.trim();
        if (t.equalsIgnoreCase(STATUS_PENDING)) {return STATUS_PENDING;}
        if (t.equalsIgnoreCase(STATUS_APPROVED)){return STATUS_APPROVED;}
        if (t.equalsIgnoreCase(STATUS_RESCHEDULED)){return STATUS_RESCHEDULED;}
        if (t.equalsIgnoreCase(STATUS_APPT_RESCHEDULED)){return STATUS_APPT_RESCHEDULED;}
        return t; // unsupported handled by caller
    }

    private static String sanitizeSlot(String label) {
        if (String.isBlank(label)){return null;}
        String t = label.trim();
        return t == '' ? null : t;
    }

    private static void enforceNotBlankId(Id i, String msg) {
        if (i == null) {throw new AuraHandledException(msg);}
    }
    private static void enforceNotNull(Object o, String msg) {
        if (o == null) {throw new AuraHandledException(msg);}
    }
    private static void enforceNotBlank(String s, String msg) {
        if (String.isBlank(s)) {throw new AuraHandledException(msg);}
    }
}