/**
 * @description Service class that recalculates Vendor Agreement completion status
 * on parent Opportunities based on related Vendor_Opportunity__c records.
 * When all related Vendor Opportunities are signed, the parent Opportunity is
 * marked as completed. Vendor Opportunity files are not copied to Opportunity.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation')
public without sharing class VendorOpportunityAgreementService {

    /**
     * @description Recalculates All_Vendors_Agreement_Completed__c for the given
     * Opportunities. This method no longer copies Vendor Opportunity files to
     * Opportunity Files / Notes & Attachments.
     * @param opportunityIds Set of Opportunity Ids that need recalculation.
     */
    public static void recalculateAndCopyFiles(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> totalByOpp = getVendorOppCounts(opportunityIds);
        Map<Id, Integer> signedByOpp = getSignedVendorOppCounts(opportunityIds);

        Map<Id, Boolean> desiredState = computeDesiredState(
            opportunityIds,
            totalByOpp,
            signedByOpp
        );

        List<Opportunity> opportunitiesToUpdate = buildOppUpdates(
            opportunityIds,
            desiredState
        );

        performOppUpdates(opportunitiesToUpdate);
    }

    private static Map<Id, Integer> getVendorOppCounts(Set<Id> opportunityIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();

        for (AggregateResult aggregateRecord : [
            SELECT Opportunity__c oppId, COUNT(Id) cnt
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :opportunityIds
            GROUP BY Opportunity__c
        ]) {
            counts.put(
                (Id) aggregateRecord.get('oppId'),
                (Integer) aggregateRecord.get('cnt')
            );
        }

        return counts;
    }

    private static Map<Id, Integer> getSignedVendorOppCounts(
        Set<Id> opportunityIds
    ) {
        Map<Id, Integer> counts = new Map<Id, Integer>();

        for (AggregateResult aggregateRecord : [
            SELECT Opportunity__c oppId, COUNT(Id) cnt
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :opportunityIds
            AND Vendor_Agreement_Signed__c = true
            GROUP BY Opportunity__c
        ]) {
            counts.put(
                (Id) aggregateRecord.get('oppId'),
                (Integer) aggregateRecord.get('cnt')
            );
        }

        return counts;
    }

    private static Map<Id, Boolean> computeDesiredState(
        Set<Id> opportunityIds,
        Map<Id, Integer> totalByOpp,
        Map<Id, Integer> signedByOpp
    ) {
        Map<Id, Boolean> desiredStateByOpp = new Map<Id, Boolean>();

        for (Id opportunityId : opportunityIds) {
            Integer totalCount = totalByOpp.get(opportunityId);
            Integer signedCount = signedByOpp.get(opportunityId);

            Boolean allSigned = totalCount != null
                && totalCount > 0
                && signedCount != null
                && signedCount == totalCount;

            desiredStateByOpp.put(opportunityId, allSigned);
        }

        return desiredStateByOpp;
    }

    private static List<Opportunity> buildOppUpdates(
        Set<Id> opportunityIds,
        Map<Id, Boolean> desiredState
    ) {
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();

        List<Opportunity> opportunityRecords = [
            SELECT Id,
                   All_Vendors_Agreement_Completed__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        for (Opportunity opportunityRecord : opportunityRecords) {
            Boolean wantedState = desiredState.get(opportunityRecord.Id);

            if (wantedState == null) {
                wantedState = false;
            }

            if (
                opportunityRecord.All_Vendors_Agreement_Completed__c
                != wantedState
            ) {
                opportunitiesToUpdate.add(
                    new Opportunity(
                        Id = opportunityRecord.Id,
                        All_Vendors_Agreement_Completed__c = wantedState
                    )
                );
            }
        }

        return opportunitiesToUpdate;
    }

    private static void performOppUpdates(
        List<Opportunity> opportunitiesToUpdate
    ) {
        if (
            opportunitiesToUpdate == null
            || opportunitiesToUpdate.isEmpty()
        ) {
            return;
        }

        update opportunitiesToUpdate;
    }
}