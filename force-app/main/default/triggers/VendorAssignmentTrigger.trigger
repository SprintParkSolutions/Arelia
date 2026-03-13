trigger VendorAssignmentTrigger on Vendor_Assignment__c (
    before insert, before update,
    after insert, after update, after delete) 
{
    // BEFORE: Calculate and set Vendor_Efficiency__c when eligible
    if (Trigger.isBefore && Trigger.isUpdate) {
        VendorAssignmentHandler.calculateEfficiency(Trigger.new);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            VendorAssignmentHandler.updateVendorAverageEfficiency(null, Trigger.new);
        }
        if (Trigger.isUpdate) {
            VendorAssignmentHandler.updateVendorAverageEfficiency(Trigger.old, Trigger.new);
        }
        if (Trigger.isDelete) {
            VendorAssignmentHandler.updateVendorAverageEfficiency(Trigger.old, null);
        }
    }

    // AFTER: Project rollup logic and email sending
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isDelete) {
            Set<Id> projectIds = new Set<Id>();

            // Collect Project Ids from inserted or updated records
            if (Trigger.isInsert || Trigger.isUpdate) {
                for (Vendor_Assignment__c va : Trigger.new) {
                    if (va.Project__c != null) {
                        projectIds.add(va.Project__c);
                    }
                }
            }

            // Collect Project Ids from deleted records
            if (Trigger.isDelete) {
                for (Vendor_Assignment__c va : Trigger.old) {
                    if (va.Project__c != null) {
                        projectIds.add(va.Project__c);
                    }
                }
            }

            // Call handler method to update project completion percentage
            VendorAssignmentHandler.updateProjectCompletion(projectIds);
        }

        // if (Trigger.isInsert) {
        //     vendorAssignmentController.sendVendorAssignmentEmail(Trigger.new);
        // }
    }
}