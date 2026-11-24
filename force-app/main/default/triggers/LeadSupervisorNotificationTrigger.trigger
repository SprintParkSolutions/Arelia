trigger LeadSupervisorNotificationTrigger on Lead (after update) {
    Set<Id> leadIdsToNotify = new Set<Id>();

    for (Lead newLead : Trigger.new) {
        Lead oldLead = Trigger.oldMap.get(newLead.Id);

        if (
            newLead.Supervisor_User__c != null &&
            newLead.Supervisor_User__c != oldLead.Supervisor_User__c
        ) {
            leadIdsToNotify.add(newLead.Id);
        }
    }

    if (!leadIdsToNotify.isEmpty()) {
        System.enqueueJob(
            new LeadSupervisorAssignedPushJob(
                leadIdsToNotify
            )
        );
    }
}