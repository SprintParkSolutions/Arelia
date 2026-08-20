/**
 * @description       : 
 * @author            : 
 * @group             : 
 * @last modified on  : 
 * @last modified by  : 
**/
trigger ArchitectureDesignTrigger on Architecture_Design__c (after update) {
   if (Trigger.isAfter && Trigger.isUpdate) {
        ArchitectureDesignTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
        FileVisibilityHandler.handleArchitectureDesign(Trigger.new, Trigger.oldMap);
    }
}