trigger OpportunityAfterUpdate on Opportunity (after update) {
    OpportunityTriggerHandler.updateProjects(Trigger.new, Trigger.oldMap);
    OpportunityTriggerHandler.sendArchitectEmails(Trigger.new, Trigger.oldMap);
    OpportunityTriggerHandler.sendPaymentTermEmails(Trigger.new, Trigger.oldMap);
    OpportunityTriggerHandler.sendBudgetReviewEmails(Trigger.new, Trigger.oldMap);
}