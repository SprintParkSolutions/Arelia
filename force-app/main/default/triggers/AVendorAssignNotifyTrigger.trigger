trigger AVendorAssignNotifyTrigger on Vendor_Assignment__c (after update) {
    AVendorAssignNotifyHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap
    );
}