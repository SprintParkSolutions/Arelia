public with sharing class CreateJobApplicationController {
    @AuraEnabled
    public static void uploadFile(Id recordId, String documentId) {
        try {
            // Fetch the file's ContentVersion record using the documentId
            ContentVersion contentVersionObj = [SELECT Id, ContentDocumentId FROM ContentVersion 
                                                WHERE ContentDocumentId = :documentId LIMIT 1];
            // Associate the ContentDocument to the new Job Application record
            ContentDocumentLink contentDocumentLinkObj = new ContentDocumentLink();
            contentDocumentLinkObj.ContentDocumentId = contentVersionObj.ContentDocumentId;
            contentDocumentLinkObj.LinkedEntityId = recordId;
            contentDocumentLinkObj.ShareType = 'V'; // Viewer permission
            contentDocumentLinkObj.Visibility = 'AllUsers'; // Make it public
            insert contentDocumentLinkObj;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading file: ' + e.getMessage());
        }
    }
}