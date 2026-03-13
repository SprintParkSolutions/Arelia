/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 12-11-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
trigger ProjectTrigger on Project__c (before insert, before update, after insert, after update) {

    // ---- BEFORE INSERT ----
    if (Trigger.isBefore && Trigger.isInsert) {
        try {
            ProjectTriggerHandler.assignProjectCodes(Trigger.new);
        } catch (Exception e) {
            System.debug('Failed during before-insert: ' + e.getMessage());
        }
    }

    // ---- BEFORE UPDATE ----
    if (Trigger.isBefore && Trigger.isUpdate) {
        try {
            ProjectTriggerHelper.validateProjectCompletion(Trigger.new, Trigger.oldMap);
        } catch (Exception e) {
            System.debug('Failed during before-update: ' + e.getMessage());
        }
    }

    //---- AFTER INSERT ----
    if (Trigger.isAfter && Trigger.isInsert) {
        try {
            // Your existing "project approved on create" emails
            ProjectTriggerHandler.sendProjectApprovedEmail(Trigger.new);

            // Link chats after create
            WhatsAppChatRelinkerOnProject.onAfterInsert(Trigger.new);
        } catch (Exception e) {
            System.debug('Failed during after-insert: ' + e.getMessage());
        }
    }

    // ---- AFTER UPDATE ----
    if (Trigger.isAfter && Trigger.isUpdate) {
        try {
            // Your existing relinker
            WhatsAppChatRelinkerOnProject.onAfterUpdate(Trigger.new, Trigger.oldMap);

            // Delegate "Completed @ 100%" transition detection to the handler
            ProjectCompletionEmailHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);

            //project completion status update send emials
            ProjectUpdateHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        } catch (Exception e) {
            System.debug('Failed during after-update: ' + e.getMessage());
        }
    }
}