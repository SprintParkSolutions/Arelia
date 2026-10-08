/**
 * @description Architecture Design global trigger.
 *
 * Responsibilities:
 *
 * 1. Secure Token Generation
 *    - Automatically generates Secure_Token__c during record creation
 *    - Applies to Mobile, API, Flow, Apex, LWC, and other insertion sources
 *    - Does not overwrite an existing token
 *
 * 2. ArchitectureDesignNotificationHandler
 *    - Sent -> Customer Email
 *    - Approved -> Supervisor Email
 *    - Changes Requested -> Supervisor Email
 *
 * 3. ArchitectureDesignTriggerHandler
 *    - Existing Manager Approval functionality
 *
 * 4. FileVisibilityHandler
 *    - Existing Architecture Design file visibility functionality
 */
trigger ArchitectureDesignTrigger
    on Architecture_Design__c (
        before insert,
        after update
    ) {

    // ================================================================
    // GLOBAL SECURE TOKEN GENERATION
    // ================================================================
    if (
        Trigger.isBefore &&
        Trigger.isInsert
    ) {
        for (Architecture_Design__c design : Trigger.new) {
            if (String.isBlank(design.Secure_Token__c)) {
                design.Secure_Token__c =
                    UUID.randomUUID().toString();
            }
        }
    }

    if (
        Trigger.isAfter &&
        Trigger.isUpdate
    ) {
        // ============================================================
        // GLOBAL ARCHITECTURE DESIGN NOTIFICATIONS
        // ============================================================
        ArchitectureDesignNotificationHandler.onAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );

        // ============================================================
        // EXISTING MANAGER APPROVAL LOGIC
        // ============================================================
        ArchitectureDesignTriggerHandler.onAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );

        // ============================================================
        // EXISTING FILE VISIBILITY LOGIC
        // ============================================================
        FileVisibilityHandler.handleArchitectureDesign(
            Trigger.new,
            Trigger.oldMap
        );
    }
}