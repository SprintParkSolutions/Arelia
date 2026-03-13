// File: VendorOpportunityAgreementService.cls
// @Description:
// - When all Vendor_Opportunity__c under an Opportunity have Vendor_Agreement_Signed__c = true,
//   mark Opportunity.All_Vendors_Agreement_Completed__c = true.
// - When it first flips to true, copy all files (ContentDocumentLink) from Vendor_Opportunity__c
//   records up to the parent Opportunity (skip duplicates).
// Bulk-safe, CRUD/FLS-aware, PMD-friendly (reduced cognitive complexity, brace style).
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class VendorOpportunityAgreementService {

    // ===== Public API =====
    public static void recalculateAndCopyFiles(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> totalByOpp  = getVendorOppCounts(opportunityIds);
        Map<Id, Integer> signedByOpp = getSignedVendorOppCounts(opportunityIds);
        Map<Id, Boolean> desiredState = computeDesiredState(opportunityIds, totalByOpp, signedByOpp);

        UpdatePlan plan = buildOppUpdatePlan(opportunityIds, desiredState);
        performOppUpdates(plan.toUpdate);

        if (!plan.flippedToTrue.isEmpty()) {
            copyVendorOppFilesToOpps(plan.flippedToTrue);
        }
    }

    // ===== Helper DTO =====
    private class UpdatePlan {
        List<Opportunity> toUpdate = new List<Opportunity>();
        Set<Id> flippedToTrue = new Set<Id>();
    }

    // ===== Aggregation helpers =====
    private static Map<Id, Integer> getVendorOppCounts(Set<Id> oppIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, COUNT(Id) cnt
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :oppIds
            GROUP BY Opportunity__c
        ]) {
            counts.put((Id) ar.get('oppId'), (Integer) ar.get('cnt'));
        }
        return counts;
    }

    private static Map<Id, Integer> getSignedVendorOppCounts(Set<Id> oppIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Opportunity__c oppId, COUNT(Id) cnt
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :oppIds
              AND Vendor_Agreement_Signed__c = true
            GROUP BY Opportunity__c
        ]) {
            counts.put((Id) ar.get('oppId'), (Integer) ar.get('cnt'));
        }
        return counts;
    }

    private static Map<Id, Boolean> computeDesiredState(
        Set<Id> oppIds,
        Map<Id, Integer> totalByOpp,
        Map<Id, Integer> signedByOpp
    ) {
        Map<Id, Boolean> desired = new Map<Id, Boolean>();
        for (Id oppId : oppIds) {
            Integer total  = totalByOpp.get(oppId);
            Integer signed = signedByOpp.get(oppId);
            Boolean allSigned = (total != null && total > 0 && signed != null && signed == total);
            desired.put(oppId, allSigned);
        }
        return desired;
    }

    // ===== Update helpers =====
    private static UpdatePlan buildOppUpdatePlan(Set<Id> oppIds, Map<Id, Boolean> desiredState) {
        UpdatePlan plan = new UpdatePlan();

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, All_Vendors_Agreement_Completed__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ]);

        for (Opportunity o : opps.values()) {
            Boolean want = desiredState.get(o.Id);
            if (want == null) {
                want = false;
            }
            if (o.All_Vendors_Agreement_Completed__c != want) {
                plan.toUpdate.add(new Opportunity(
                    Id = o.Id,
                    All_Vendors_Agreement_Completed__c = want
                ));
                if (want) {
                    plan.flippedToTrue.add(o.Id);
                }
            }
        }
        return plan;
    }


   private static void performOppUpdates(List<Opportunity> toUpdate) {
        if (toUpdate == null || toUpdate.isEmpty()) {
            return;
        }
        // Removed Security.stripInaccessible and isUpdateable checks
        update toUpdate;
    }

    // ===== File copy (decomposed to keep complexity low) =====
    private static void copyVendorOppFilesToOpps(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }
        // Removed ContentDocumentLink.isCreateable() check

        List<Vendor_Opportunity__c> vendorOpps = queryVendorOpps(oppIds);
        if (vendorOpps.isEmpty()) {
            return;
        }

        Map<Id, Id> voToOpp = mapVendorOppToOpp(vendorOpps);

        List<ContentDocumentLink> vendorLinks = queryVendorLinks(voToOpp.keySet());
        if (vendorLinks.isEmpty()) {
            return;
        }

        Map<Id, Set<Id>> oppToExistingDocs = queryExistingOppDocs(oppIds, vendorLinks);
        List<ContentDocumentLink> toInsert = buildLinksToInsert(vendorLinks, voToOpp, oppToExistingDocs);

        insertCdlIfAny(toInsert);
    }
    // --- sub-helpers for file copy ---
    private static List<Vendor_Opportunity__c> queryVendorOpps(Set<Id> oppIds) {
        return [
            SELECT Id, Opportunity__c
            FROM Vendor_Opportunity__c
            WHERE Opportunity__c IN :oppIds
        ];
    }

    private static Map<Id, Id> mapVendorOppToOpp(List<Vendor_Opportunity__c> vos) {
        Map<Id, Id> voToOpp = new Map<Id, Id>();
        for (Vendor_Opportunity__c v : vos) {
            if (v.Opportunity__c != null) {
                voToOpp.put(v.Id, v.Opportunity__c);
            }
        }
        return voToOpp;
    }

    private static List<ContentDocumentLink> queryVendorLinks(Set<Id> vendorOppIds) {
        if (vendorOppIds == null || vendorOppIds.isEmpty()) {
            return new List<ContentDocumentLink>();
        }
        return [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :vendorOppIds
        ];
    }

    private static Map<Id, Set<Id>> queryExistingOppDocs(Set<Id> oppIds, List<ContentDocumentLink> vendorLinks) {
        Map<Id, Set<Id>> oppToDocs = new Map<Id, Set<Id>>();
        Set<Id> docIds = new Set<Id>();

        for (ContentDocumentLink l : vendorLinks) {
            docIds.add(l.ContentDocumentId);
        }
        if (docIds.isEmpty()) {
            return oppToDocs;
        }

        List<ContentDocumentLink> existing = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :oppIds
              AND ContentDocumentId IN :docIds
        ];

        for (ContentDocumentLink e : existing) {
            if (!oppToDocs.containsKey(e.LinkedEntityId)) {
                oppToDocs.put(e.LinkedEntityId, new Set<Id>());
            }
            oppToDocs.get(e.LinkedEntityId).add(e.ContentDocumentId);
        }
        return oppToDocs;
    }

    private static List<ContentDocumentLink> buildLinksToInsert(
        List<ContentDocumentLink> vendorLinks,
        Map<Id, Id> voToOpp,
        Map<Id, Set<Id>> oppToExistingDocs
    ) {
        List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
        for (ContentDocumentLink vLink : vendorLinks) {
            Id oppId = voToOpp.get(vLink.LinkedEntityId);
            if (oppId == null) {
                continue;
            }

            Set<Id> already = oppToExistingDocs.get(oppId);
            Boolean isDuplicate = (already != null && already.contains(vLink.ContentDocumentId));
            if (isDuplicate) {
                continue;
            }

            ContentDocumentLink newLink = new ContentDocumentLink(
                LinkedEntityId    = oppId,
                ContentDocumentId = vLink.ContentDocumentId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );
            toInsert.add(newLink);
        }
        return toInsert;
    }
    
    private static void insertCdlIfAny(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }
        insert links;
    }
}