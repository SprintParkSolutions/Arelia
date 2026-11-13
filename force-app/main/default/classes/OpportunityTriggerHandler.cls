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

            if (isAreliaOpportunity(newOpp) && isQualified(newOpp, oldOpp)) {
                qualifiedOpportunities.put(newOpp.Id, newOpp);
            }
        }

        // Exit if no qualified Opportunities
        if (qualifiedOpportunities.isEmpty()) {
            return;
        }

        // Query Projects related to qualified Opportunities
        Id areliaProjectRecordTypeId = AreliaUtility.getAreliaProjectRecordTypeId();
        List<Project__c> projectsToUpdate = [
            SELECT Id, Project_Name__c
            FROM Project__c
            WHERE Project_Name__c IN :qualifiedOpportunities.keySet()
            AND RecordTypeId = :areliaProjectRecordTypeId
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
     * Sends the architect email whenever architect fields are populated/changed on an Arelia Opportunity,
     * regardless of what updated the record. Delegates the qualification check and sending to
     * ArchitectInfoController so there is a single implementation shared by every update source.
     *
     * @param newOpps List of updated Opportunities
     * @param oldMap Map of old Opportunity records
     */
    public static void sendArchitectEmails(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        ArchitectInfoController.sendArchitectEmails(newOpps, oldMap);
    }

    /**
     * Sends Payment Terms notification emails whenever Payment_Terms_Status__c changes on an
     * Opportunity, regardless of what updated the record. Delegates the transition handling and
     * sending to PaymentTermController so there is a single implementation shared by every update source.
     *
     * @param newOpps List of updated Opportunities
     * @param oldMap Map of old Opportunity records
     */
    public static void sendPaymentTermEmails(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        PaymentTermController.sendPaymentTermEmails(newOpps, oldMap);
    }

    /**
     * Sends Budget Review notification emails whenever Budget_Review_Status__c changes on an
     * Opportunity, regardless of what updated the record. Delegates the transition handling and
     * sending to OpportunityBudgetReviewController so there is a single implementation shared by
     * every update source.
     *
     * @param newOpps List of updated Opportunities
     * @param oldMap Map of old Opportunity records
     */
    public static void sendBudgetReviewEmails(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        OpportunityBudgetReviewController.sendBudgetReviewEmails(newOpps, oldMap);
    }

    private static Boolean isAreliaOpportunity(Opportunity opp) {
        // AreliaUtility resolves this via a direct RecordType SOQL query rather than
        // Schema.describe().getRecordTypeInfosByName(), which only returns Record Types
        // visible to the CURRENT USER'S PROFILE - that describe-based lookup silently returned
        // null (skipping this whole trigger branch) for Guest Users and other portal/community
        // profiles that don't have "Arelia" assigned, while working fine for Admin.
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();
        return areliaOpportunityRecordTypeId != null && opp.RecordTypeId == areliaOpportunityRecordTypeId;
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