trigger CreateProjectFromOpportunity on Opportunity (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CreateProjectFromOpportunityHandler.handleAfterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            CreateProjectFromOpportunityHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}