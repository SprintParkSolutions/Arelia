/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger ProformaInvoiceTrigger on Proforma_Invoice__c (after update) {
    Map<Id, Id> invoiceToOppMap = new Map<Id, Id>();

    for (Proforma_Invoice__c pi : Trigger.new) {
        Proforma_Invoice__c oldPi = Trigger.oldMap.get(pi.Id);
        
        if (pi.Manager_Approval__c && !oldPi.Manager_Approval__c && pi.Opportunity__c != null) {
            invoiceToOppMap.put(pi.Id, pi.Opportunity__c);
        }
    }

    if (!invoiceToOppMap.isEmpty()) {
        FileVisibilityHandler.shareFilesWithOpportunity(invoiceToOppMap);
    }
}