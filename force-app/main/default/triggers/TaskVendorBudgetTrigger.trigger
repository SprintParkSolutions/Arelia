trigger TaskVendorBudgetTrigger on Task (before insert, before update,
                                        after insert,  after update, after delete, after undelete) 
{
    // 1) Hard-stop if a save would exceed the vendor cap
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        TaskVendorBudgetHandler.validatePercentTotals(Trigger.new, Trigger.oldMap);
    }

    // 2) Keep Vendor_Assignment__c.Vendor_Tasks_Remaining_Percentage__c up to date
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            TaskVendorBudgetHandler.recalcRemainingFromTasks(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            TaskVendorBudgetHandler.recalcRemainingFromDeleted(Trigger.old);
        }
    }
}