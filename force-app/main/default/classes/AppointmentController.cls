/**
 * @name AppointmentController
 * @description LWC controller for Site Visit appointment response.
 *
 * Responsibilities:
 * - Capture Approved or Rescheduled response from LWC.
 * - Update response fields on Lead.
 * - Return available time slots for UI.
 *
 * Business processing is handled globally by:
 * LeadTrigger -> LeadAppointmentResponseHandler.
 *
 * @version 2.0
 */
public without sharing class AppointmentController {

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_RESCHEDULED = 'Rescheduled';
    private static final String STATUS_APPOINTMENT_RESCHEDULED = 'Appointment Rescheduled';
    private static final Set<String> APPROVED_OR_RESCHEDULED = new Set<String>{STATUS_APPROVED,STATUS_RESCHEDULED,
                                                                                    STATUS_APPOINTMENT_RESCHEDULED};
    // =========================================================
    // CAPTURE LWC RESPONSE
    // =========================================================
    /**
     * Captures customer response from LWC.
     * This method intentionally contains no email or
     * appointment business logic.
     * The Lead update fires LeadTrigger.
     * @param leadId Lead Id.
     * @param status Approved or Rescheduled.
     * @param rescheduleDate Requested new date.
     * @param timeSlot Requested new time.
     */
    @AuraEnabled
    public static void updateAppointmentStatus(Id leadId, String status, Date rescheduleDate, String timeSlot) {
        enforceNotBlankId(leadId, 'Lead ID is missing.');
        enforceNotBlank(status,'Status is required.');
        String normalizedStatus = normalizeResponseStatus(status);
        Lead responseUpdate =new Lead(Id = leadId, Appointment_Status__c = normalizedStatus);
        // =====================================================
        // RESCHEDULE RESPONSE FIELDS
        // =====================================================
        if ( normalizedStatus ==STATUS_RESCHEDULED) {
            enforceNotNull(rescheduleDate, 'Please select both a date '+ 'and a time slot.');
            enforceNotBlank(timeSlot,'Please select both a date ' + 'and a time slot.');
            /*
             * Capture requested values only.
             * Trigger performs final validation and
             * remaining business processing.
             */
            responseUpdate.Appointment_Rescheduled_Time__c = rescheduleDate;
            responseUpdate.Time_Slots__c =sanitizeSlot(timeSlot);
        }
        // =====================================================
        // UPDATE LEAD
        // =====================================================
        try {
            /*
             * This fires:
             * LeadTrigger BEFORE UPDATE    ↓
             * LeadAppointmentResponseHandler.beforeUpdate()
             * then:
             * LeadTrigger AFTER UPDATE     ↓
             * LeadAppointmentResponseHandler.afterUpdate()
             */
            update responseUpdate;
        } catch (
            DmlException exceptionValue
        ) {
            throw new AuraHandledException(getDmlErrorMessage(exceptionValue
                )
            );
        }
    }

    // =========================================================
    // AVAILABLE TIME SLOTS
    // =========================================================
    /**
     * Returns available appointment slots.
     * This is for UI display only.
     * Trigger performs the final availability validation.
     * @param forDate Selected date.
     * @param currentLeadId Current Lead.
     * @return Available time slots.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableTimeSlots(Date forDate,Id currentLeadId) {
        enforceNotNull(forDate,'Please select a date first.');
        enforceNotBlankId(currentLeadId,'Lead ID is missing.');
        
        Lead currentLead = [SELECT Id,Supervisor_User__c FROM Lead WHERE Id = :currentLeadId LIMIT 1];
        
        List<String> allSlots = getPicklistValues( Lead.Time_Slots__c );
        if(allSlots.isEmpty()) {
            return allSlots;
        }
        if (currentLead.Supervisor_User__c == null) {
            return new List<String>();
        }
        Set<String> taken = new Set<String>();
        // =====================================================
        // RESCHEDULED PAIR
        // =====================================================
        for (AggregateResult resultValue : [SELECT Time_Slots__c slot FROM Lead WHERE Id != :currentLeadId
                    AND Supervisor_User__c = :currentLead.Supervisor_User__c AND Appointment_Rescheduled_Time__c =:forDate
                    AND Time_Slots__c != null AND Appointment_Status__c IN :APPROVED_OR_RESCHEDULED GROUP BY Time_Slots__c])
        {
            String slot =sanitizeSlot((String)resultValue.get('slot'));
            if (slot != null) {
                taken.add(slot.toLowerCase());
            }
        }

        // =====================================================
        // APPROVED / RESCHEDULED ORIGINAL PAIR
        // =====================================================
        for (AggregateResult resultValue : [SELECT Appointment_Time_Slots__c slot FROM Lead WHERE Id != :currentLeadId
                    AND Supervisor_User__c = :currentLead.Supervisor_User__c AND Appointment_Date__c = :forDate
                    AND Appointment_Time_Slots__c != null AND Appointment_Status__c IN :APPROVED_OR_RESCHEDULED
                    GROUP BY Appointment_Time_Slots__c])
        {
            String slot = sanitizeSlot((String) resultValue.get('slot'));
            if(slot != null) {
                taken.add(slot.toLowerCase());
            }
        }

        // =====================================================
        // PENDING APPOINTMENTS
        // =====================================================

        for(AggregateResult resultValue : [SELECT Appointment_Time_Slots__c slot FROM Lead WHERE Id != :currentLeadId
                    AND Supervisor_User__c = :currentLead.Supervisor_User__c
                    AND Appointment_Date__c = :forDate AND Appointment_Time_Slots__c != null
                    AND Appointment_Status__c = :STATUS_PENDING GROUP BY Appointment_Time_Slots__c])
        {
            String slot = sanitizeSlot((String) resultValue.get('slot'));
            
            if (slot != null) {
                taken.add(slot.toLowerCase());
            }
        }
        
        // =====================================================
        // BUILD AVAILABLE LIST
        // =====================================================
        List<String> available = new List<String>();
        for (String slot : allSlots)
        {
            String cleanSlot = sanitizeSlot(slot);
            if ( cleanSlot != null && !taken.contains( cleanSlot.toLowerCase()))
            {
                available.add(slot);
            }
        }
        return available;
    }


    // =========================================================
    // ALL PICKLIST VALUES
    // =========================================================

    /**
     * Returns Time_Slots__c picklist values.
     * @return Available configured values.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        return getPicklistValues( Lead.Time_Slots__c);
    }

    // =========================================================
    // PICKLIST HELPER
    // =========================================================
    /**
     * Returns active picklist entries.
     * @param fieldReference Picklist field.
     * @return Picklist values.
     */
    private static List<String> getPicklistValues(Schema.SObjectField fieldReference) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry :fieldReference.getDescribe().getPicklistValues())
        {
            if (entry.isActive()) {
                values.add(entry.getLabel());
            }
        }
        return values;
    }

    // =========================================================
    // RESPONSE NORMALIZATION
    // =========================================================
    /**
     * Allows only Approved or Rescheduled.
     * @param status Incoming status.
     * @return Normalized status.
     */
    private static String normalizeResponseStatus(String status) {

        String value = status == null ? null : status.trim();
        
        if (value != null && value.equalsIgnoreCase(STATUS_APPROVED))
        {
            return STATUS_APPROVED;
        }
        
        if (value != null && value.equalsIgnoreCase( STATUS_RESCHEDULED ))
        {
            return STATUS_RESCHEDULED;
        }
        throw new AuraHandledException('Unsupported appointment response. ' + 'Allowed values are Approved ' + 'and Rescheduled.');
    }

    // =========================================================
    // HELPERS
    // =========================================================
    private static String sanitizeSlot(String slot) {
        return String.isBlank(slot)? null: slot.trim();
    }

    private static void enforceNotBlankId(Id valueValue,String message) {
        if(valueValue == null) {
            throw new AuraHandledException(message);
        }
    }
    
    private static void enforceNotNull(Object valueValue,String message) {
        if (valueValue == null) {
            throw new AuraHandledException(message);
        }
    }

    private static void enforceNotBlank(String valueValue,String message) {
        if (String.isBlank(valueValue)) {
            throw new AuraHandledException(message);
        }
    }

    private static String getDmlErrorMessage(DmlException exceptionValue) {
        if (exceptionValue == null || exceptionValue.getNumDml() == 0) {
            return 'Unable to update appointment response.';
        }
        String message = exceptionValue.getDmlMessage(0);
        return String.isBlank(message) ? 'Unable to update appointment response.' : message;
    }
}