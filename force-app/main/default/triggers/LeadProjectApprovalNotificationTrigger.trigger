trigger LeadProjectApprovalNotificationTrigger on Lead (after update) {

    Set<Id> approvedLeadIds = new Set<Id>();

    for (Lead newLead : Trigger.new) {

        Lead oldLead = Trigger.oldMap.get(newLead.Id);

        if (
            oldLead.Approval_Status__c == 'Pending' &&
            newLead.Approval_Status__c == 'Approved'
        ) {
            approvedLeadIds.add(newLead.Id);
        }
    }

    if (!approvedLeadIds.isEmpty()) {

        System.enqueueJob(
            new LeadProjectApprovalPushJob(approvedLeadIds)
        );
    }
}