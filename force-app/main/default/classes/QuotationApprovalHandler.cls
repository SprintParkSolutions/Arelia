public class QuotationApprovalHandler {

    public static void handleAfterUpdate(
        List<Quotation__c> newList,
        Map<Id, Quotation__c> oldMap
    ) {
        Set<Id> approvedQuotationIds = new Set<Id>();
        Map<Id, Id> quotationToOpportunity = new Map<Id, Id>();

        for (Quotation__c q : newList) {
            Quotation__c oldQ = oldMap.get(q.Id);
            if (
                oldQ != null &&
                !oldQ.Manager_Approval__c &&
                q.Manager_Approval__c &&
                q.Opportunity__c != null
            ) {
                approvedQuotationIds.add(q.Id);
                quotationToOpportunity.put(q.Id, q.Opportunity__c);
            }
        }

        if (approvedQuotationIds.isEmpty()) return;

        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :approvedQuotationIds
        ]) {
            Id oppId = quotationToOpportunity.get(cdl.LinkedEntityId);
            if (oppId == null) continue;

            newLinks.add(new ContentDocumentLink(
                ContentDocumentId = cdl.ContentDocumentId,
                LinkedEntityId = oppId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (!newLinks.isEmpty()) {
            insert newLinks;
        }
    }
}