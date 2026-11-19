trigger PaymentTermsClientNotificationTrigger
    on Opportunity (after update) {

    Set<Id> opportunityIdsToNotify = new Set<Id>();

    for (Opportunity newOpp : Trigger.new) {

        Opportunity oldOpp = Trigger.oldMap.get(newOpp.Id);

        if (oldOpp == null) {continue;}

        Boolean sentForClientApproval = oldOpp.Payment_Terms_Status__c !='Sent for Manager Approval' && newOpp.Payment_Terms_Status__c =='Sent for Client Approval';
		Boolean approvedDateJustPopulated = newOpp.Payment_Terms_Approved_Date__c  != null && oldOpp.Payment_Terms_Approved_Date__c  == null;
        Boolean approvalReady = newOpp.Payment_Terms_Status__c == 'Sent for Client Approval' && newOpp.Payment_Terms_Approved_Date__c  != null;
        
        if (approvalReady && (sentForClientApproval || approvedDateJustPopulated)) {
            opportunityIdsToNotify.add(newOpp.Id);
        }
    }

    if (!opportunityIdsToNotify.isEmpty()) {

        System.enqueueJob( new PaymentTermsClientPushJob( opportunityIdsToNotify )
        );
    }
}