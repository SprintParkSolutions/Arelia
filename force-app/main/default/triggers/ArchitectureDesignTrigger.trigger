/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-06-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger ArchitectureDesignTrigger on Architecture_Design__c (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        ArchitectureDesignTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
        FileVisibilityHandler.handleArchitectureDesign(Trigger.new, Trigger.oldMap);
    }
}