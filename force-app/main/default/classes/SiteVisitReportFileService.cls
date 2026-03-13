public with sharing class SiteVisitReportFileService {

    public static void attachFilesToLead(Id siteVisitReportId) {

        // Step 1: Fetch Site Visit Report with RecordType
        Site_Visit_Report__c siteVisitReportObj = [
            SELECT Id, Lead__c, Opportunity__c, RecordType.DeveloperName
            FROM Site_Visit_Report__c
            WHERE Id = :siteVisitReportId
            LIMIT 1
        ];

        if (siteVisitReportObj == null) {
            throw new AuraHandledException('No Site Visit Report found for the given Id.');
        }

        String recordTypeDevName = siteVisitReportObj.RecordType.DeveloperName;

        // Step 2: Get files linked to Site Visit Report
        Set<Id> siteReportDocIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :siteVisitReportId
        ]) {
            siteReportDocIds.add(link.ContentDocumentId);
        }

        if (siteReportDocIds.isEmpty()) {
            return;
        }

        // ===============================
        // ✅ Existing Logic: Attach to Lead
        // ===============================
        if (recordTypeDevName == 'Lead_Site_Visit_Report') {

            if (siteVisitReportObj.Lead__c == null) {
                throw new AuraHandledException('No related Lead found for the Site Visit Report.');
            }

            Id leadId = siteVisitReportObj.Lead__c;

            // Get files already linked to the Lead
            Set<Id> alreadyLinkedDocIds = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :leadId
                AND ContentDocumentId IN :siteReportDocIds
            ]) {
                alreadyLinkedDocIds.add(link.ContentDocumentId);
            }

            // Link only missing files
            List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
            for (Id docId : siteReportDocIds) {
                if (!alreadyLinkedDocIds.contains(docId)) {
                    newLinks.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = leadId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }

            if (!newLinks.isEmpty()) {
                insert newLinks;
            }
        }

        // ===========================================
        // ✨ New Logic: Attach to Opportunity (existing)
        // ===========================================
        if (recordTypeDevName == 'Opportunity_Site_Visit_Report') {

            if (siteVisitReportObj.Opportunity__c == null) {
                throw new AuraHandledException('No related Opportunity found for the Site Visit Report.');
            }

            Id oppId = siteVisitReportObj.Opportunity__c;

            // Get files already linked to the Opportunity
            Set<Id> alreadyLinkedDocIdsOpp = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :oppId
                AND ContentDocumentId IN :siteReportDocIds
            ]) {
                alreadyLinkedDocIdsOpp.add(link.ContentDocumentId);
            }

            // Link only missing files
            List<ContentDocumentLink> newLinksOpp = new List<ContentDocumentLink>();
            for (Id docId : siteReportDocIds) {
                if (!alreadyLinkedDocIdsOpp.contains(docId)) {
                    newLinksOpp.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = oppId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }

            if (!newLinksOpp.isEmpty()) {
                insert newLinksOpp;
            }
        }
    }
}