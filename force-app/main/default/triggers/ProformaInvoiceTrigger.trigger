/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger ProformaInvoiceTrigger on Proforma_Invoice__c (after update) {
    ProformaInvoiceTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}