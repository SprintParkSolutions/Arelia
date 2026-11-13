trigger AreliaLeadConversionNotificationTrigger
    on Lead (after update) {

    Set<Id> convertedLeadIds = new Set<Id>();

    for (Lead newLead : Trigger.new) {

        Lead oldLead = Trigger.oldMap.get(newLead.Id);

        if (
            oldLead != null &&
            oldLead.IsConverted == false &&
            newLead.IsConverted == true &&
            newLead.ConvertedOpportunityId != null &&
            newLead.ConvertedAccountId != null &&
            newLead.ConvertedContactId != null
        ) {
            convertedLeadIds.add(newLead.Id);
        }
    }

    if (!convertedLeadIds.isEmpty()) {

        System.enqueueJob(
            new AreliaLeadConversionPushJob(
                convertedLeadIds
            )
        );
    }
}