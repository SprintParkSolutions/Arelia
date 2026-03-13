/**
 * @name AppointmentControllerToOpp
 * @description Controls Opportunity site visit appointment approval and rescheduling from Experience
 *      Cloud by enforcing supervisor-based date and time slot availability across Pending, Approved, 
 *      and Rescheduled Opportunities and Leads, validating user input, preventing duplicate or conflicting 
 *      bookings, updating appointment fields and status in a single transaction, and sending confirmation 
 *      email notifications to supervisors and customers using configured email templates.
 * @author Arelia Living
 * @version 1.0
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class AppointmentControllerToOpp {

    // ---- Lead reschedule pair (matches your org)
    private static final String LEAD_RESCHED_DATE_FIELD = 'Appointment_Rescheduled_Time__c';
    private static final String LEAD_RESCHED_SLOT_FIELD = 'Time_Slots__c';

    // Customer templates (Label contains DeveloperName)
    private static final String CUST_TPL_APPROVED   = Label.Arelia_Living_Customer_Opportunity_Appointment_Approved_Email;
    private static final String CUST_TPL_RESCHEDULE = Label.Arelia_Living_Customer_Opportunity_Appointment_Rescheduled_Email;

    // ===== Null-safe helpers =====
    private static String toStringOrEmpty(String v) { return v == null ? '' : v; }

    // ✅ Supervisor Name Fix (FirstName + LastName)
    private static String buildUserFullName(User u) {
        if (u == null) {return '';}
        String fn = toStringOrEmpty(u.FirstName);
        String ln = toStringOrEmpty(u.LastName);
        String full = (fn + ' ' + ln).trim();
        return String.isBlank(full) ? toStringOrEmpty(u.Name) : full;
    }

    private static String formatDateMDY(Date d) {
        return d == null
            ? ''
            : DateTime.newInstance(d, Time.newInstance(0,0,0,0)).format('MM/dd/yyyy');
    }

    // ✅ ONE token builder used for BOTH emails
    private static Map<String, String> buildTokens(Opportunity opp) {
        Map<String, String> t = new Map<String, String>();

        // Customer / Recipient
        t.put('{{{Recipient.Name}}}',  toStringOrEmpty(opp.Primary_Contact__r != null ? opp.Primary_Contact__r.Name : null));
        t.put('{{{Recipient.Phone}}}', toStringOrEmpty(opp.Primary_Contact__r != null ? opp.Primary_Contact__r.Phone : null));

        // Supervisor details (First + Last)
        t.put('{{{Supervisor_User__c.Name}}}',  buildUserFullName(opp.Supervisor_User__r));
        t.put('{{{Supervisor_User__c.Email}}}', toStringOrEmpty(opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Email : null));
        t.put('{{{Supervisor_User__c.Phone}}}', toStringOrEmpty(opp.Supervisor_User__r != null ? opp.Supervisor_User__r.Phone : null));

        // Appointment details
        t.put('{{{Re_Visit_Appointment_Date__c}}}',             formatDateMDY(opp.Re_Visit_Appointment_Date__c));
        t.put('{{{Re_Visit_Appointment_Time_Slots__c}}}',       toStringOrEmpty(opp.Re_Visit_Appointment_Time_Slots__c));
        t.put('{{{Re_Visit_Appointment_Rescheduled_Date__c}}}', formatDateMDY(opp.Re_Visit_Appointment_Rescheduled_Date__c));
        t.put('{{{Re_Visit_Appointm_Rescheduled_Time_Slots__c}}}', toStringOrEmpty(opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c));

        // Picklist value (if you want label, tell me)
        t.put('{{{Re_Visit_Site_Appointment_Status__c}}}', toStringOrEmpty(opp.Re_Visit_Site_Appointment_Status__c));

        return t;
    }

    // ✅ ONE apply function
    private static String applyTokens(String input, Map<String, String> tokens) {
        if (String.isBlank(input) || tokens == null || tokens.isEmpty()) {return input;}

        String outVal = input;
        for (String k : tokens.keySet()) {
            outVal = outVal.replace(k, tokens.get(k));
        }
        return outVal;
    }

    // ===== Public: update status =====
    @AuraEnabled
    public static void updateAppointmentStatus(
        Id opportunityId,
        String status,
        String rejectionReason,
        Date rescheduleDate,
        String timeSlot
    ) {
        if (String.isBlank(opportunityId)) {
            throw new AuraHandledException('Opportunity ID is missing.');
        }
        if (String.isBlank(status)) {
            throw new AuraHandledException('Status is required.');
        }

        Opportunity opp = [SELECT Id, Name, Re_Visit_Site_Appointment_Status__c, Primary_Contact__c,
                   Primary_Contact__r.Name, Primary_Contact__r.Phone, Primary_Contact__r.Email,
                   Re_Visit_Appointment_Date__c, Re_Visit_Appointment_Time_Slots__c,
                   Re_Visit_Appointment_Rescheduled_Date__c, Re_Visit_Appointm_Rescheduled_Time_Slots__c,
                   Supervisor_User__c, Supervisor_User__r.Name, Supervisor_User__r.FirstName, Supervisor_User__r.LastName,
                   Supervisor_User__r.Phone, Supervisor_User__r.Email FROM Opportunity
            WHERE Id = :opportunityId LIMIT 1];

        // Allow responses only while still Pending or Rescheduled
        String existing = opp.Re_Visit_Site_Appointment_Status__c;
        if (String.isNotBlank(existing) && existing != 'Pending' && existing != 'Rescheduled') {
            throw new AuraHandledException('Your response was already submitted as ' + existing + '. Further changes are not allowed.');
        }

        if ('Approved'.equalsIgnoreCase(status)) {
            opp.Re_Visit_Site_Appointment_Status__c = 'Approved';
            opp.Re_Visit_Appointment_Rescheduled_Date__c = null;
            opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c = null;

        } else if ('Rescheduled'.equalsIgnoreCase(status)) {
            if (rescheduleDate == null || String.isBlank(timeSlot)) {
                throw new AuraHandledException('Please select both a date and a time slot.');
            }

            if (!isSlotAvailableForSupervisor(opp.Supervisor_User__c, rescheduleDate, timeSlot, opp.Id)) {
                throw new AuraHandledException('That time slot is already booked for the selected date. Please choose another.');
            }

            opp.Re_Visit_Site_Appointment_Status__c = 'Rescheduled';
            opp.Re_Visit_Appointment_Date__c = null;
            opp.Re_Visit_Appointment_Time_Slots__c = null;
            opp.Re_Visit_Appointment_Rescheduled_Date__c = rescheduleDate;
            opp.Re_Visit_Appointm_Rescheduled_Time_Slots__c = timeSlot;

        } else {
            throw new AuraHandledException('Unsupported status: ' + status);
        }

        update opp;

        // ✅ Existing call kept
        sendConfirmationEmail(opp, opp.Re_Visit_Site_Appointment_Status__c);
    }

    // ===== Public: available slots (excludes Lead + Opp booked slots in Pending/Approved/Rescheduled) =====
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableTimeSlots(Date forDate, Id currentOpportunityId) {
        if (forDate == null) {
            throw new AuraHandledException('Please select a date first.');
        }
        if (String.isBlank(currentOpportunityId)) {
            throw new AuraHandledException('Opportunity ID is missing.');
        }

        Opportunity currentOpp = [SELECT Id, Supervisor_User__c FROM Opportunity
                                WHERE Id = :currentOpportunityId LIMIT 1];

        List<String> allSlots = getPicklistValues(Opportunity.Re_Visit_Appointm_Rescheduled_Time_Slots__c);
        if (allSlots.isEmpty()) {return allSlots;}

        Set<String> taken = collectTakenSlots(currentOpp.Supervisor_User__c, forDate, currentOpportunityId);

        List<String> available = new List<String>();
        for (String s : allSlots) {
            String key = s == null ? null : s.trim();
            if (String.isBlank(key)) {continue;}
            if (!taken.contains(key)) {
                available.add(s);
            }
        }
        return available;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTimeSlotsPicklistValues() {
        return getPicklistValues(Opportunity.Re_Visit_Appointm_Rescheduled_Time_Slots__c);
    }

    // ===== Private: universal availability (Lead + Opp, Pending/Approved/Rescheduled) =====
    private static Boolean isSlotAvailableForSupervisor(Id supervisorUserId, Date onDate, String slotLabel, Id excludeOpportunityId) {
        if (supervisorUserId == null || onDate == null || String.isBlank(slotLabel)) {return false;}
        Set<String> taken = collectTakenSlots(supervisorUserId, onDate, excludeOpportunityId);
        return !taken.contains(slotLabel.trim());
    }

    private static Set<String> collectTakenSlots(Id supervisorId, Date forDate, Id excludeOpportunityId) {
        Set<String> taken = new Set<String>();

        for (AggregateResult ar : [SELECT Re_Visit_Appointm_Rescheduled_Time_Slots__c slot FROM Opportunity
            WHERE Supervisor_User__c = :supervisorId
              AND Re_Visit_Site_Appointment_Status__c IN ('Pending','Approved','Rescheduled')
              AND Re_Visit_Appointment_Rescheduled_Date__c = :forDate
              AND Re_Visit_Appointm_Rescheduled_Time_Slots__c != null
              AND Id != :excludeOpportunityId GROUP BY Re_Visit_Appointm_Rescheduled_Time_Slots__c])
        {
            taken.add(((String) ar.get('slot'))?.trim());
        }

        for (AggregateResult ar2 : [SELECT Re_Visit_Appointment_Time_Slots__c slot FROM Opportunity
            WHERE Supervisor_User__c = :supervisorId
              AND Re_Visit_Site_Appointment_Status__c IN ('Pending','Approved','Rescheduled')
              AND Re_Visit_Appointment_Date__c = :forDate AND Re_Visit_Appointment_Time_Slots__c != null
              AND Id != :excludeOpportunityId GROUP BY Re_Visit_Appointment_Time_Slots__c])
        {
            taken.add(((String) ar2.get('slot'))?.trim());
        }

        String soqlLeadRes =
            'SELECT ' + LEAD_RESCHED_SLOT_FIELD + ' slot ' +
            'FROM Lead ' +
            'WHERE Supervisor_User__c = :supervisorId ' +
            'AND Appointment_Status__c IN (\'Pending\',\'Approved\',\'Rescheduled\') ' +
            'AND ' + LEAD_RESCHED_DATE_FIELD + ' = :forDate ' +
            'AND ' + LEAD_RESCHED_SLOT_FIELD + ' != null ' +
            'GROUP BY ' + LEAD_RESCHED_SLOT_FIELD;

        for (AggregateResult ar3 : Database.query(soqlLeadRes)) {
            taken.add(((String) ar3.get('slot'))?.trim());
        }

        for (AggregateResult ar4 : [SELECT Appointment_Time_Slots__c slot FROM Lead
                WHERE Supervisor_User__c = :supervisorId AND Appointment_Status__c IN ('Pending','Approved','Rescheduled')
                AND Appointment_Date__c = :forDate AND Appointment_Time_Slots__c != null GROUP BY Appointment_Time_Slots__c])
        {
            taken.add(((String) ar4.get('slot'))?.trim());
        }

        taken.remove('');
        return taken;
    }

    private static List<String> getPicklistValues(Schema.sObjectField field) {
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry pe : field.getDescribe().getPicklistValues()) {
            vals.add(pe.getLabel());
        }
        return vals;
    }

    /**
     * Sends email to Supervisor (existing logic) AND Customer (new templates).
     * ✅ Best practice: query templates once + apply tokens once.
     */
    private static void sendConfirmationEmail(Opportunity opp, String status) {
        if (opp == null) {return;}

        // Decide template DeveloperNames
        final String supervisorTemplateName = 'Approved'.equalsIgnoreCase(status)
            ? Label.Arelia_Living_Opportunity_Appointment_Approved_Email
            : Label.Arelia_Living_Opportunity_Appointment_Rescheduled_Email;

        final String customerTemplateName = 'Approved'.equalsIgnoreCase(status)
            ? CUST_TPL_APPROVED
            : CUST_TPL_RESCHEDULE;

        // ✅ Query both templates once
        Map<String, EmailTemplate> tplByDevName = new Map<String, EmailTemplate>();
        for (EmailTemplate t : [SELECT Id, DeveloperName, HtmlValue, Subject FROM EmailTemplate
                    WHERE DeveloperName IN :new Set<String>{ supervisorTemplateName, customerTemplateName }
        ]) {
            tplByDevName.put(t.DeveloperName, t);
        }

        Map<String, String> tokens = buildTokens(opp);
        Id owd = getDefaultOrgWideEmailAddressId();

        // 1) Supervisor email
        if (opp.Supervisor_User__c != null && opp.Supervisor_User__r != null && !String.isBlank(opp.Supervisor_User__r.Email)) {
            EmailTemplate supTpl = tplByDevName.get(supervisorTemplateName);
            if (supTpl != null && !String.isBlank(supTpl.Subject) && !String.isBlank(supTpl.HtmlValue)) {
                Messaging.SingleEmailMessage supMsg = new Messaging.SingleEmailMessage();
                supMsg.setSubject(applyTokens(supTpl.Subject, tokens));
                supMsg.setHtmlBody(applyTokens(supTpl.HtmlValue, tokens));
                supMsg.setTargetObjectId(opp.Supervisor_User__c);
                supMsg.setTreatTargetObjectAsRecipient(true);
                if (owd != null) {supMsg.setOrgWideEmailAddressId(owd);}
                supMsg.setSaveAsActivity(false);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ supMsg });
            }
        }

        // 2) Customer email
        if (opp.Primary_Contact__r != null && !String.isBlank(opp.Primary_Contact__r.Email)) {
            EmailTemplate custTpl = tplByDevName.get(customerTemplateName);
            if (custTpl != null && !String.isBlank(custTpl.Subject) && !String.isBlank(custTpl.HtmlValue)) {
                Messaging.SingleEmailMessage custMsg = new Messaging.SingleEmailMessage();
                custMsg.setSubject(applyTokens(custTpl.Subject, tokens));
                custMsg.setHtmlBody(applyTokens(custTpl.HtmlValue, tokens));
                custMsg.setToAddresses(new List<String>{ opp.Primary_Contact__r.Email });
                if (owd != null) {custMsg.setOrgWideEmailAddressId(owd);}
                custMsg.setSaveAsActivity(false);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ custMsg });
            }
        }
    }

    /** Fetch Org-Wide Email Address by label from Custom Label Arelia_OWD. */
    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }
}