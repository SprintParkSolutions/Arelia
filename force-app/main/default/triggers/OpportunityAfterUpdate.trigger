trigger OpportunityAfterUpdate on Opportunity (after update) {
    OpportunityTriggerHandler.updateProjects(Trigger.new, Trigger.oldMap);
}