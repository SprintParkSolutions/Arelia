trigger TaskTrigger on Task (after insert, after update, after delete) {
    
    Set<Id> vendorAssignmentIds = new Set<Id>();
    
    // Determine which list to iterate: new records (insert/update) or old records (delete)
    List<Task> tasksToProcess = Trigger.isDelete ? Trigger.old : Trigger.new;
    
    // Collect all related Vendor_Assignment__c IDs
    for (Task t : tasksToProcess) {
        if (t.WhatId != null
            && t.WhatId.getSObjectType() == Vendor_Assignment__c.SObjectType) {
            vendorAssignmentIds.add(t.WhatId);
        }
    }
    
    // On update, also include the previous WhatId in case the parent changed
    if (Trigger.isUpdate) {
        for (Task tOld : Trigger.old) {
            if (tOld.WhatId != null
                && tOld.WhatId.getSObjectType() == Vendor_Assignment__c.SObjectType) {
                vendorAssignmentIds.add(tOld.WhatId);
            }
        }
    }
    
    if (!vendorAssignmentIds.isEmpty()) {
        TaskHelper.updateCompletionForAssignments(vendorAssignmentIds);
    }
}