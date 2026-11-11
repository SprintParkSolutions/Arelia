trigger BudgetReviewClientNotificationTrigger
    on Opportunity (after update) {

    Set<Id> opportunityIdsToNotify = new Set<Id>();

    for (Opportunity newOpportunity : Trigger.new) {

        Opportunity oldOpportunity =
            Trigger.oldMap.get(newOpportunity.Id);

        if (oldOpportunity == null) {
            continue;
        }

        Boolean budgetReviewSentForApproval =
            oldOpportunity.Budget_Review_Status__c
                != 'Sent for Client Approval'
            &&
            newOpportunity.Budget_Review_Status__c
                == 'Sent for Client Approval';

        if (budgetReviewSentForApproval) {
            opportunityIdsToNotify.add(newOpportunity.Id);
        }
    }

    if (!opportunityIdsToNotify.isEmpty()) {

        System.enqueueJob(
            new BudgetReviewClientPushJob(
                opportunityIdsToNotify
            )
        );
    }
}