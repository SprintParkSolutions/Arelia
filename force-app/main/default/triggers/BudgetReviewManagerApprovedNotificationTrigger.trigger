trigger BudgetReviewManagerApprovedNotificationTrigger on Opportunity (after update) {

    Set<Id> opportunityIdsToNotify = new Set<Id>();

    for (Opportunity newOpp : Trigger.new) {
        Opportunity oldOpp = Trigger.oldMap.get(newOpp.Id);
        if (oldOpp == null) { continue; }

        Boolean managerJustApproved = newOpp.Budget_Review_Status__c == 'Manager Approved' && oldOpp.Budget_Review_Status__c != 'Manager Approved';
        Boolean approvedDateJustPopulated = newOpp.Budget_Review_Approved_Date__c != null && oldOpp.Budget_Review_Approved_Date__c == null;
        Boolean approvalReady = newOpp.Budget_Review_Status__c == 'Manager Approved' && newOpp.Budget_Review_Approved_Date__c != null;

        if (approvalReady && (managerJustApproved || approvedDateJustPopulated)) {
            opportunityIdsToNotify.add(newOpp.Id);
        }
    }

    if (!opportunityIdsToNotify.isEmpty()) {
        System.enqueueJob( new BudgetReviewManagerApprovedPushJob( opportunityIdsToNotify ) );
    }
}