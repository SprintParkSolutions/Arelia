trigger ArchitectureClientApprovalNotificationTrigger
    on Opportunity (after update) {

    Set<Id> opportunityIdsToNotify = new Set<Id>();

    for (Opportunity newOpp : Trigger.new) {

        Opportunity oldOpp =
            Trigger.oldMap.get(newOpp.Id);

        if (oldOpp == null) {
            continue;
        }

        Boolean approvalJustSent =
            newOpp.Architecture_Client_Approval_Sent__c == true &&
            oldOpp.Architecture_Client_Approval_Sent__c != true;

        if (
            approvalJustSent &&
            newOpp.Primary_Contact__c != null
        ) {
            opportunityIdsToNotify.add(
                newOpp.Id
            );
        }
    }

    if (!opportunityIdsToNotify.isEmpty()) {
        System.enqueueJob(
            new ArchitectureClientApprovalPushJob(
                opportunityIdsToNotify
            )
        );
    }
}