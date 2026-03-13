/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 03-10-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class VendorOpportunityTriggerDispatcher {

    public static void dispatch() {
        Set<Id> oppIds = new Set<Id>();
        // Normalize contexts to reduce branching complexity
        List<List<SObject>> sources = new List<List<SObject>>();
        if (Trigger.new != null)  sources.add(Trigger.new);
        if (Trigger.isDelete && Trigger.old != null) sources.add(Trigger.old);

        for (List<SObject> batch : sources) {
            oppIds.addAll(collectOppIds(batch));
        }

        if (!oppIds.isEmpty()) {
            VendorOpportunityAgreementService.recalculateAndCopyFiles(oppIds);
        }
    }

    private static Set<Id> collectOppIds(List<SObject> rows) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) return ids;
        for (SObject sob : rows) {
            Vendor_Opportunity__c r = (Vendor_Opportunity__c) sob;
            if (r.Opportunity__c != null) ids.add(r.Opportunity__c);
        }
        return ids;
    }
}