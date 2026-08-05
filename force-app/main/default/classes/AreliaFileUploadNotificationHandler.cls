public with sharing class AreliaFileUploadNotificationHandler {

    public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
        if (newLinks == null || newLinks.isEmpty()) {
            return;
        }

        Set<Id> projectIds = new Set<Id>();
        Set<Id> contentDocumentIds = new Set<Id>();

        for (ContentDocumentLink linkRec : newLinks) {
            if (linkRec.LinkedEntityId == null || linkRec.ContentDocumentId == null) {
                continue;
            }

            contentDocumentIds.add(linkRec.ContentDocumentId);

            // Only handle files uploaded to Project__c records
            if (linkRec.LinkedEntityId.getSObjectType() == Project__c.SObjectType) {
                projectIds.add(linkRec.LinkedEntityId);
            }
        }

        if (projectIds.isEmpty()) {
            System.debug('No Project__c file upload found. Push skipped.');
            return;
        }

        Map<Id, Project__c> projectMap = new Map<Id, Project__c>([
            SELECT Id, Name, Client__c
            FROM Project__c
            WHERE Id IN :projectIds
            AND Client__c != null
        ]);

        if (projectMap.isEmpty()) {
            System.debug('No projects with Client__c found. Push skipped.');
            return;
        }

        Map<Id, ContentDocument> documentMap = new Map<Id, ContentDocument>();

        for (ContentDocument doc : [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ]) {
            documentMap.put(doc.Id, doc);
        }

        Set<String> sentKeys = new Set<String>();

        for (ContentDocumentLink linkRec : newLinks) {
            if (!projectMap.containsKey(linkRec.LinkedEntityId)) {
                continue;
            }

            Project__c projectRec = projectMap.get(linkRec.LinkedEntityId);

            if (projectRec.Client__c == null) {
                continue;
            }

            String uniqueKey = String.valueOf(projectRec.Client__c) + '-' + String.valueOf(linkRec.ContentDocumentId);

            if (sentKeys.contains(uniqueKey)) {
                continue;
            }

            sentKeys.add(uniqueKey);

            String fileName = 'a new document';

            if (documentMap.containsKey(linkRec.ContentDocumentId)) {
                fileName = documentMap.get(linkRec.ContentDocumentId).Title;
            }

            AreliaPushNotificationService.sendToContactAsync(
                projectRec.Client__c,
                'New Document Uploaded',
                'A new file "' + fileName + '" has been uploaded to your project ' + projectRec.Name + '.',
                'file_upload',
                String.valueOf(linkRec.ContentDocumentId)
            );

            System.debug('File upload push queued for Contact: ' + projectRec.Client__c);
        }
    }
}