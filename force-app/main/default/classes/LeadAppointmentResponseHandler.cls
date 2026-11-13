/**
 * @name LeadAppointmentResponseHandler
 * @description Central handler for customer Site Visit responses.
 *
 * Customer response can originate from:
 * - LWC
 * - Flutter / Mobile
 * - REST API
 * - Flow
 * - Apex
 * - Salesforce UI
 *
 * Supported responses:
 * - Approved
 * - Rescheduled
 *
 * BEFORE UPDATE:
 * - Detect response change
 * - Validate response
 * - Process Approved fields
 * - Process Rescheduled fields
 * - Validate Supervisor/date/time availability
 *
 * AFTER UPDATE:
 * - Send Supervisor notification
 * - Send Customer notification
 *
 * @version 1.0
 */
public without sharing class LeadAppointmentResponseHandler {

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_RESCHEDULED = 'Rescheduled';
    private static final String STATUS_APPOINTMENT_RESCHEDULED = 'Appointment Rescheduled';

    /*
     * Customer is allowed to respond only when the appointment
     * is waiting for customer confirmation.
     */
    private static final Set<String> RESPONSE_ALLOWED_FROM = new Set<String>{STATUS_PENDING, STATUS_APPOINTMENT_RESCHEDULED};

    /*
     * Original Appointment_Date__c +
     * Appointment_Time_Slots__c is blocked by these statuses.
     */
    private static final Set<String> INITIAL_SLOT_BLOCKING_STATUSES = new Set<String>{STATUS_PENDING,STATUS_APPROVED,STATUS_RESCHEDULED, STATUS_APPOINTMENT_RESCHEDULED};

    /*
     * Appointment_Rescheduled_Time__c +
     * Time_Slots__c is blocked by these statuses.
     */
    private static final Set<String> RESCHEDULE_SLOT_BLOCKING_STATUSES = new Set<String>{STATUS_APPROVED,STATUS_RESCHEDULED,STATUS_APPOINTMENT_RESCHEDULED};

    // =========================================================
    // EMAIL TEMPLATE LABELS
    // =========================================================

    private static final String SUPERVISOR_APPROVED_TEMPLATE = Label.Arelia_Living_Appointment_Approved_Email;
    private static final String SUPERVISOR_RESCHEDULED_TEMPLATE = Label.Arelia_Living_Appointment_Rescheduled_Email;
    private static final String CUSTOMER_APPROVED_TEMPLATE = Label.Customer_Appointment_Approved_Email;
    private static final String CUSTOMER_RESCHEDULED_TEMPLATE = Label.Customer_Appointment_Rescheduled_Email;

    // =========================================================
    // BEFORE UPDATE
    // =========================================================

    /**
     * Handles customer appointment response before Lead update.
     *
     * @param newLeads Updated Leads.
     * @param oldMap Previous Lead values.
     */
    public static void beforeUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || newLeads.isEmpty() || oldMap == null) {
            return;
        }
        List<Lead> rescheduleCandidates = new List<Lead>();
        
        for (Lead newLead : newLeads) {
            
            Lead oldLead = oldMap.get(newLead.Id);
            if (oldLead == null) { continue;}

            /*
             * Process only Arelia Leads.
             */
            if(!LeadEmailHandler.isAreliaLead(newLead)) {
                continue;
            }

            /*
             * Ignore normal Lead updates.
             * Continue only when Appointment_Status__c
             * actually changes to Approved or Rescheduled.
             */
            if(!isCustomerResponseTransition(newLead,oldLead)) {
                continue;
            }

            String oldStatus = normalizeStatus(oldLead.Appointment_Status__c);
            String newStatus = normalizeStatus(newLead.Appointment_Status__c);
            
            // =================================================
            // VALIDATE CURRENT STATUS
            // =================================================

            if(!RESPONSE_ALLOWED_FROM.contains(oldStatus)){
                newLead.addError(buildAlreadyRespondedMessage(oldStatus));
                continue;
            }
            
            // =================================================
            // VALIDATE APPOINTMENT EXISTS
            // =================================================
            if(!hasAppointment(oldLead)) {
                newLead.addError('No site visit appointment is available ' + 'for response.');
                continue;
            }

            // =================================================
            // APPROVED
            // =================================================
            if( newStatus == STATUS_APPROVED) {
                processApproval( newLead);
                continue;
            }

            // =================================================
            // RESCHEDULED
            // =================================================
            if(newStatus == STATUS_RESCHEDULED ) {
                Boolean valid = prepareReschedule(newLead,oldLead);
                if(valid) {
                    rescheduleCandidates.add(newLead);
                }
            }
        }

        // =====================================================
        // BULK RESCHEDULE SLOT VALIDATION
        // =====================================================
        if(!rescheduleCandidates.isEmpty()) {
            validateRescheduleAvailability(rescheduleCandidates);
        }
    }

    // =========================================================
    // AFTER UPDATE
    // =========================================================

    /**
     * Sends customer and supervisor emails after successful
     * appointment response.
     *
     * @param newLeads Updated Leads.
     * @param oldMap Previous Lead values.
     */
    public static void afterUpdate(List<Lead> newLeads, Map<Id, Lead> oldMap) {

        if(newLeads == null || newLeads.isEmpty() || oldMap == null ) {
            return;
        }
        
        Set<Id> notificationLeadIds = new Set<Id>();

        for (Lead newLead : newLeads) {
            Lead oldLead = oldMap.get(newLead.Id);
            if (oldLead == null) {
                continue;
            }
            
            if (!LeadEmailHandler.isAreliaLead(newLead)) {
                continue;
            }
            
            String oldStatus = normalizeStatus(oldLead.Appointment_Status__c);
            String newStatus = normalizeStatus(newLead.Appointment_Status__c);
            
            Boolean approvedNow = newStatus == STATUS_APPROVED && oldStatus != STATUS_APPROVED;
            Boolean rescheduledNow = newStatus == STATUS_RESCHEDULED && oldStatus != STATUS_RESCHEDULED;
            
            if (approvedNow || rescheduledNow ) {
                notificationLeadIds.add( newLead.Id);
            }
        }

        if ( notificationLeadIds.isEmpty()) { return; }

        sendNotifications(notificationLeadIds);
    }

    // =========================================================
    // RESPONSE TRANSITION
    // =========================================================

    /**
     * Determines whether update is a customer response.
     * @param newLead New Lead.
     * @param oldLead Old Lead.
     * @return true when response changed to Approved/Rescheduled.
     */
    public static Boolean isCustomerResponseTransition(Lead newLead, Lead oldLead) {

        if (newLead == null || oldLead == null ) {
            return false;
        }
        
        String oldStatus = normalizeStatus( oldLead.Appointment_Status__c);
        String newStatus = normalizeStatus(newLead.Appointment_Status__c);

        if (oldStatus == newStatus) {
            return false;
        }
        return newStatus == STATUS_APPROVED || newStatus == STATUS_RESCHEDULED;
    }
    // =========================================================
    // APPROVAL
    // =========================================================

    /**
     * Handles customer approval.
     *
     * @param leadRecord Lead being updated.
     */
    private static void processApproval(Lead leadRecord) {

        leadRecord.Appointment_Status__c = STATUS_APPROVED;
        leadRecord.Appointment_Completed__c = true;
        
        /*
         * Customer approved the Supervisor-selected
         * Appointment_Date__c and
         * Appointment_Time_Slots__c.
         * Clear any old reschedule values.
         */
        leadRecord.Appointment_Rescheduled_Time__c = null;
        leadRecord.Time_Slots__c = null;
    }

    // =========================================================
    // RESCHEDULE
    // =========================================================

    /**
     * Validates and prepares reschedule response.
     *
     * @param leadRecord New Lead.
     * @param oldLead Previous Lead.
     * @return true when basic validation passes.
     */
    private static Boolean prepareReschedule(Lead leadRecord, Lead oldLead ) {
        Date requestedDate = leadRecord.Appointment_Rescheduled_Time__c;
        String requestedSlot = sanitizeSlot(leadRecord.Time_Slots__c);
        // -----------------------------------------------------
        // Date required
        // -----------------------------------------------------

        if (requestedDate == null) {
            leadRecord.addError('Preferred reschedule date is required.');
            return false;
        }
        
        // -----------------------------------------------------
        // Time required
        // -----------------------------------------------------
        if(String.isBlank(requestedSlot)) {
            leadRecord.addError('Preferred time slot is required.');
            return false;
        }
        // -----------------------------------------------------
        // Past date restriction
        // -----------------------------------------------------

        if(requestedDate < Date.today()) {
            leadRecord.addError('Preferred date cannot be in the past.');
            return false;
        }
        // -----------------------------------------------------
        // Supervisor required
        // -----------------------------------------------------

        if (leadRecord.Supervisor_User__c == null) {
            
            leadRecord.addError('Supervisor is required before ' + 'rescheduling the appointment.');
            return false;
        }
        // -----------------------------------------------------
        // Validate slot against Salesforce picklist
        // -----------------------------------------------------

        if (!isValidTimeSlot(requestedSlot) ) {
            leadRecord.addError('Invalid preferred time slot.' );
            return false;
        }

        // -----------------------------------------------------
        // Same date/time restriction
        // -----------------------------------------------------

        if (oldLead.Appointment_Date__c == requestedDate && slotsEqual(oldLead.Appointment_Time_Slots__c, requestedSlot)) {
            leadRecord.addError('Please select a different date ' + 'or time slot to reschedule.');
            return false;
        }
        // -----------------------------------------------------
        // Normalize saved status
        // -----------------------------------------------------

        leadRecord.Appointment_Status__c =STATUS_RESCHEDULED;
        leadRecord.Appointment_Completed__c = true;
        
        // -----------------------------------------------------
        // Store requested new appointment
        // -----------------------------------------------------

        leadRecord.Appointment_Rescheduled_Time__c = requestedDate;
        leadRecord.Time_Slots__c = requestedSlot;
        /*
         * Preserve your existing functionality.
         *
         * Once customer requests reschedule,
         * original appointment date/time is cleared.
         */
        leadRecord.Appointment_Date__c = null;
        leadRecord.Appointment_Time_Slots__c = null;

        return true;
    }

    // =========================================================
    // RESCHEDULE AVAILABILITY
    // =========================================================

    /**
     * Validates Supervisor + Date + Slot in bulk.
     *
     * @param candidates Reschedule requests.
     */
    private static void validateRescheduleAvailability(List<Lead> candidates) {

        Set<Id> supervisorIds = new Set<Id>();
        Set<Date> requestedDates = new Set<Date>();
        Set<Id> candidateIds = new Set<Id>();

        Map<String, List<Lead>> candidatesBySlot = new Map<String, List<Lead>>();
        
        for (Lead candidate : candidates) {
            supervisorIds.add(candidate.Supervisor_User__c);
            requestedDates.add(candidate.Appointment_Rescheduled_Time__c);
            candidateIds.add(candidate.Id);

            String key =buildSlotKey(candidate.Supervisor_User__c,candidate.Appointment_Rescheduled_Time__c,
                    candidate.Time_Slots__c);
                
            if(!candidatesBySlot.containsKey(key)) {
                candidatesBySlot.put(key,new List<Lead>());
            }
            candidatesBySlot.get(key).add(candidate);
        }
        // =====================================================
        // DUPLICATES INSIDE SAME TRANSACTION
        // =====================================================

        for (String key : candidatesBySlot.keySet()) {

            List<Lead> sameSlotLeads = candidatesBySlot.get(key);
            
            if (sameSlotLeads.size() <= 1 ) {
                continue;
            }
            for (Lead duplicateLead : sameSlotLeads ) {
                duplicateLead.addError('That time slot is already being '+ 'used by another appointment.');
            }
        }
        Set<String> occupiedSlots = new Set<String>();
        // =====================================================
        // EXISTING ORIGINAL APPOINTMENTS
        // =====================================================

        for (Lead existingLead : [SELECT Id, Supervisor_User__c, Appointment_Status__c,
                    Appointment_Date__c, Appointment_Time_Slots__c FROM Lead WHERE Id NOT IN :candidateIds
                    AND Supervisor_User__c IN :supervisorIds AND Appointment_Date__c IN :requestedDates
                    AND Appointment_Time_Slots__c != null AND Appointment_Status__c IN :INITIAL_SLOT_BLOCKING_STATUSES])
        {
            occupiedSlots.add(buildSlotKey(existingLead.Supervisor_User__c,
                    existingLead.Appointment_Date__c,existingLead.Appointment_Time_Slots__c));
        }

        // =====================================================
        // EXISTING RESCHEDULED APPOINTMENTS
        // =====================================================

        for (Lead existingLead : [SELECT Id,Supervisor_User__c,Appointment_Status__c,Appointment_Rescheduled_Time__c,
                Time_Slots__c FROM Lead WHERE Id NOT IN :candidateIds AND Supervisor_User__c IN :supervisorIds
                AND Appointment_Rescheduled_Time__c IN :requestedDates AND Time_Slots__c != null
                AND Appointment_Status__c IN :RESCHEDULE_SLOT_BLOCKING_STATUSES])
            {
            occupiedSlots.add(buildSlotKey(existingLead.Supervisor_User__c,
                    existingLead.Appointment_Rescheduled_Time__c,existingLead.Time_Slots__c));
        }

        // =====================================================
        // FINAL CHECK
        // =====================================================

        for (Lead candidate : candidates) {
            String requestedKey = buildSlotKey(candidate.Supervisor_User__c,
                    candidate.Appointment_Rescheduled_Time__c,candidate.Time_Slots__c);

            if (occupiedSlots.contains(requestedKey)) {
                candidate.addError(
                    'That time slot is already booked '
                    + 'for the selected date. '
                    + 'Please choose another.'
                );
            }
        }
    }

    // =========================================================
    // EMAIL NOTIFICATIONS
    // =========================================================

    /**
     * Sends Supervisor and Customer notifications.
     *
     * @param leadIds Lead IDs.
     */
    private static void sendNotifications( Set<Id> leadIds ) {
        if (
            leadIds == null || leadIds.isEmpty() ) {
            return;
        }
        List<Lead> leads = [SELECT Id,FirstName,LastName,Email,Appointment_Status__c,Appointment_Date__c,
                Appointment_Time_Slots__c,Appointment_Rescheduled_Time__c,Time_Slots__c,Supervisor_User__c,
                Supervisor_User__r.Email FROM Lead WHERE Id IN :leadIds];

        Map<String, Id> templateMap = loadEmailTemplates();
        Id orgWideEmailAddressId = getDefaultOrgWideEmailAddressId();

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();

        for (Lead leadRecord : leads) {

            Boolean isApproved =leadRecord.Appointment_Status__c ==STATUS_APPROVED;
            String supervisorTemplateName =isApproved? SUPERVISOR_APPROVED_TEMPLATE: SUPERVISOR_RESCHEDULED_TEMPLATE;

            String customerTemplateName = isApproved? CUSTOMER_APPROVED_TEMPLATE: CUSTOMER_RESCHEDULED_TEMPLATE;
            
            // =================================================
            // SUPERVISOR EMAIL
            // =================================================

            if (leadRecord.Supervisor_User__r != null &&
                String.isNotBlank(leadRecord.Supervisor_User__r.Email)) {

                Id supervisorTemplateId =templateMap.get(supervisorTemplateName);
                
                if (supervisorTemplateId != null) {
                    Messaging.SingleEmailMessage supervisorEmail = new Messaging.SingleEmailMessage();
                    supervisorEmail.setToAddresses(new List<String>{leadRecord.Supervisor_User__r.Email});
                    
                    /*
                     * Lead is used for template merge fields.
                     * Supervisor email address is the actual
                     * recipient.
                     */
                    supervisorEmail.setTargetObjectId(leadRecord.Id);
                    supervisorEmail.setTreatTargetObjectAsRecipient(false);
                    supervisorEmail.setTemplateId(supervisorTemplateId);
                    supervisorEmail.setSaveAsActivity(true);
                    if (orgWideEmailAddressId != null) {
                        supervisorEmail.setOrgWideEmailAddressId(orgWideEmailAddressId);
                    }
                    messages.add(supervisorEmail);
                }
            }
            // =================================================
            // CUSTOMER EMAIL
            // =================================================

            if (String.isNotBlank(leadRecord.Email)) {

                Id customerTemplateId = templateMap.get(customerTemplateName);
                if (customerTemplateId != null) {
                    Messaging.SingleEmailMessage customerEmail = new Messaging.SingleEmailMessage();

                    /*
                     * Lead itself is customer recipient.
                     */
                    customerEmail.setTargetObjectId(leadRecord.Id);
                    customerEmail.setTreatTargetObjectAsRecipient(true);
                    customerEmail.setTemplateId(customerTemplateId);
                    customerEmail.setSaveAsActivity(true);
                    
                    if (orgWideEmailAddressId != null) {
                        customerEmail.setOrgWideEmailAddressId(orgWideEmailAddressId);
                    }
                    messages.add(customerEmail);
                }
            }
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages,false);
        }
    }

    // =========================================================
    // EMAIL TEMPLATES
    // =========================================================

    /**
     * Loads required Email Templates.
     *
     * @return DeveloperName -> EmailTemplate Id map.
     */
    private static Map<String, Id> loadEmailTemplates() {

        Set<String> templateNames = new Set<String>();
        
        addTemplateName(templateNames,SUPERVISOR_APPROVED_TEMPLATE );
        addTemplateName(templateNames,SUPERVISOR_RESCHEDULED_TEMPLATE);
        addTemplateName(templateNames,CUSTOMER_APPROVED_TEMPLATE);
        addTemplateName(templateNames,CUSTOMER_RESCHEDULED_TEMPLATE);
        
        Map<String, Id> templateMap = new Map<String, Id>();
        if (templateNames.isEmpty()) {
            return templateMap;
        }
        for (EmailTemplate templateRecord : [SELECT Id,DeveloperName FROM EmailTemplate
                       WHERE DeveloperName IN :templateNames])
        {
            templateMap.put(templateRecord.DeveloperName,templateRecord.Id);
        }
        return templateMap;
    }

    /**
     * Adds configured template name.
     * @param templateNames Template collection.
     * @param templateName Template DeveloperName.
     */
    private static void addTemplateName(Set<String> templateNames,String templateName) {

        if (String.isNotBlank(templateName)) {
            templateNames.add(templateName);
        }
    }
    
    // =========================================================
    // ORG-WIDE EMAIL ADDRESS
    // =========================================================

    /**
     * Returns configured Org-Wide Email Address.
     * @return Org-Wide Email Address Id.
     */
    private static Id getDefaultOrgWideEmailAddressId() {

        List<OrgWideEmailAddress> addresses = [SELECT Id FROM OrgWideEmailAddress
                WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1 ];

        return addresses.isEmpty() ? null: addresses[0].Id;
    }

    // =========================================================
    // APPOINTMENT EXISTS
    // =========================================================

    /**
     * Checks whether a Site Visit appointment exists.
     * @param leadRecord Lead.
     * @return true when appointment exists.
     */
    private static Boolean hasAppointment(Lead leadRecord) {

        if (leadRecord == null) {
            return false;
        }
        
        return leadRecord.Appointment_Sent_date__c != null || leadRecord.Appointment_Date__c != null ||
            String.isNotBlank( leadRecord .Appointment_Time_Slots__c);
    }

    // =========================================================
    // TIME SLOT VALIDATION
    // =========================================================
    /**
     * Validates selected slot against Time_Slots__c picklist.
     * @param requestedSlot Requested slot.
     * @return true when valid.
     */
    private static Boolean isValidTimeSlot(String requestedSlot) {
        if (String.isBlank(requestedSlot)) {
            return false;
        }
        String normalized =requestedSlot.trim();
        for (Schema.PicklistEntry entry : Lead.Time_Slots__c.getDescribe().getPicklistValues()) {
            
            if (!entry.isActive()) {
                continue;
            }
            if (normalized.equalsIgnoreCase(entry.getValue()) || normalized.equalsIgnoreCase(entry.getLabel())) {
                return true;
            }
        }
        return false;
    }


    // =========================================================
    // ALREADY RESPONDED
    // =========================================================

    /**
     * Creates user-friendly duplicate response message.
     *
     * @param appointmentStatus Existing status.
     * @return Error message.
     */
    private static String buildAlreadyRespondedMessage(String appointmentStatus) {
        if (appointmentStatus == STATUS_APPROVED) {
            return 'You have already approved ' + 'this appointment.';
        }
        if (appointmentStatus == STATUS_RESCHEDULED) {
            return 'You have already requested ' + 'a new date and time.';
        }
        
        return 'A response has already been submitted ' + 'for this appointment.';
    }

    // =========================================================
    // STATUS NORMALIZATION
    // =========================================================
    /**
     * Normalizes Appointment Status.
     * @param status Status.
     * @return Normalized status.
     */
    private static String normalizeStatus(String status) {

        if (String.isBlank(status)) {
            return status;
        }
        
        String value = status.trim();
        
        if (value.equalsIgnoreCase(STATUS_PENDING)) {
            return STATUS_PENDING;
        }

        if (value.equalsIgnoreCase(STATUS_APPROVED)) {
            return STATUS_APPROVED;
        }
        
        if (value.equalsIgnoreCase(STATUS_RESCHEDULED)) {
            return STATUS_RESCHEDULED;
        }
        
        if (value.equalsIgnoreCase(STATUS_APPOINTMENT_RESCHEDULED)) {
            return STATUS_APPOINTMENT_RESCHEDULED;
        }

        return value;
    }


    // =========================================================
    // SLOT HELPERS
    // =========================================================

    /**
     * Cleans time slot value.
     * @param slot Slot.
     * @return Cleaned slot.
     */
    private static String sanitizeSlot( String slot) {

        if (String.isBlank(slot)) {
            return null;
        }
        return slot.trim();
    }
    
    /**
     * Compares two slots.
     * @param firstSlot First slot.
     * @param secondSlot Second slot.
     * @return true when same.
     */
    private static Boolean slotsEqual(String firstSlot,String secondSlot) {

        String first = sanitizeSlot(firstSlot);
        String second = sanitizeSlot(secondSlot);
        
        if (first == null || second == null) {
            return false;
        }
        return first.equalsIgnoreCase(second);
    }

    /**
     * Builds unique Supervisor/date/slot key.
     *
     * @param supervisorId Supervisor.
     * @param appointmentDate Date.
     * @param slot Slot.
     * @return Unique key.
     */
    private static String buildSlotKey(Id supervisorId,Date appointmentDate,String slot) {
        
        String cleanSlot =sanitizeSlot(slot);

        return String.valueOf( supervisorId)  + '|' + String.valueOf( appointmentDate )
                + '|' + ( cleanSlot == null ? '' : cleanSlot.toLowerCase() );
    }
}