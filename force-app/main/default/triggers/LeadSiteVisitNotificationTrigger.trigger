trigger LeadSiteVisitNotificationTrigger on Lead (after update) {

    Set<Id> scheduledLeadIds = new Set<Id>();

    for (Lead newLead : Trigger.new) {

        Lead oldLead = Trigger.oldMap.get(newLead.Id);

        Boolean dateChanged =
            newLead.Appointment_Date__c !=
            oldLead.Appointment_Date__c;

        Boolean timeChanged =
            newLead.Appointment_Time_Slots__c !=
            oldLead.Appointment_Time_Slots__c;

        Boolean hasValidAppointment =
            newLead.Appointment_Date__c != null &&
            String.isNotBlank(
                newLead.Appointment_Time_Slots__c
            );

        if (
            hasValidAppointment &&
            (dateChanged || timeChanged)
        ) {
            scheduledLeadIds.add(newLead.Id);
        }
    }

    if (!scheduledLeadIds.isEmpty()) {
        System.enqueueJob(
            new LeadSiteVisitPushJob(scheduledLeadIds)
        );
    }
}