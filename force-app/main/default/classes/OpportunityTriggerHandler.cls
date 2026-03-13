public with sharing class OpportunityTriggerHandler {

    /**
     * Updates related Projects when Negotiation/Review Budget field is updated in the Opportunity.
     * Bulk-safe and PMD-compliant.
     *
     * @param newOpps List of updated Opportunities
     * @param oldMap Map of old Opportunity records
     */
    public static void updateProjects(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {

        // Map to hold Opportunities that qualify for Project update
        Map<Id, Opportunity> qualifiedOpportunities = new Map<Id, Opportunity>();

        for (Opportunity newOpp : newOpps) {
            Opportunity oldOpp = oldMap.get(newOpp.Id);

            if (isQualified(newOpp, oldOpp)) {
                qualifiedOpportunities.put(newOpp.Id, newOpp);
            }
        }

        // Exit if no qualified Opportunities
        if (qualifiedOpportunities.isEmpty()) {
            return;
        }

        // Query Projects related to qualified Opportunities
        List<Project__c> projectsToUpdate = [
            SELECT Id, Project_Name__c
            FROM Project__c
            WHERE Project_Name__c IN :qualifiedOpportunities.keySet()
        ];

        // Update each Project record
        for (Project__c project : projectsToUpdate) {
            Opportunity opp = qualifiedOpportunities.get(project.Project_Name__c);
            applyProjectUpdate(project, opp);
        }

        // Bulk update all Projects
        if (!projectsToUpdate.isEmpty()) {
            update projectsToUpdate;
        }
    }

    /**
     * Determines if an Opportunity qualifies for Project update
     * 
     * @param newOpp The new Opportunity record
     * @param oldOpp The old Opportunity record
     * @return Boolean true if update is required
     */
    private static Boolean isQualified(Opportunity newOpp, Opportunity oldOpp) {
        Boolean stageIsResumed = newOpp.StageName == 'Resumed';
        Boolean budgetNotNull = newOpp.Negotiation_Review_Budget__c != null;
        Boolean stageOrBudgetChanged = oldOpp.StageName != 'Resumed'
            || oldOpp.Negotiation_Review_Budget__c != newOpp.Negotiation_Review_Budget__c;

        return stageIsResumed && budgetNotNull && stageOrBudgetChanged;
    }

    /**
     * Applies required field updates to a Project record
     *
     * @param project The Project record to update
     * @param opp The Opportunity record containing values
     */
    private static void applyProjectUpdate(Project__c project, Opportunity opp) {
        project.Supervisor_Estimated_Budget__c = opp.Negotiation_Review_Budget__c;
        project.Status__c = 'In progress';
    }
}