/**
 * @description Architecture Design global trigger.
 *
 * Responsibilities:
 *
 * 1. ArchitectureDesignNotificationHandler
 *    - Sent -> Customer Email
 *    - Approved -> Supervisor Email
 *    - Changes Requested -> Supervisor Email
 *
 * 2. ArchitectureDesignTriggerHandler
 *    - Existing Manager Approval functionality
 *
 * 3. FileVisibilityHandler
 *    - Existing Architecture Design file visibility functionality
 */
trigger ArchitectureDesignTrigger on Architecture_Design__c (after update ) {

    if (Trigger.isAfter && Trigger.isUpdate ) {
        // ================================================================
        // GLOBAL ARCHITECTURE DESIGN NOTIFICATIONS
        // ================================================================
        ArchitectureDesignNotificationHandler.onAfterUpdate( Trigger.new, Trigger.oldMap );
        
        // ================================================================
        // EXISTING MANAGER APPROVAL LOGIC
        // ================================================================
        ArchitectureDesignTriggerHandler.onAfterUpdate( Trigger.new, Trigger.oldMap );
        
        // ================================================================
        // EXISTING FILE VISIBILITY LOGIC
        // ================================================================
        FileVisibilityHandler.handleArchitectureDesign( Trigger.new, Trigger.oldMap);
    }
}