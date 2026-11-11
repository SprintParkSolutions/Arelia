public without sharing class AreliaFileUploadNotificationHandler {

    public static void handleAfterInsert(
        List<ContentDocumentLink> newLinks
    ) {

        System.debug(
            'FILE UPLOAD NOTIFICATION HANDLER STARTED'
        );

        if (newLinks == null || newLinks.isEmpty()) {
            return;
        }

        Set<Id> projectIds = new Set<Id>();
        Set<Id> documentIds = new Set<Id>();

        // =====================================================
        // 1. IDENTIFY DOCUMENTS LINKED TO PROJECTS
        // =====================================================

        for (ContentDocumentLink linkRec : newLinks) {

            if (
                linkRec.LinkedEntityId == null ||
                linkRec.ContentDocumentId == null
            ) {
                continue;
            }

            if (
                linkRec.LinkedEntityId.getSObjectType()
                    == Project__c.SObjectType
            ) {
                projectIds.add(linkRec.LinkedEntityId);
                documentIds.add(linkRec.ContentDocumentId);
            }
        }

        if (projectIds.isEmpty()) {

            System.debug(
                'FILE UPLOAD: No Project file links found.'
            );

            return;
        }

        // =====================================================
        // 2. FETCH PROJECTS WITH STATUS
        // =====================================================

        Map<Id, Project__c> projectMap =
            new Map<Id, Project__c>([
                SELECT
                    Id,
                    Name,
                    Client__c,
                    Project_Name__c,
                    Status__c
                FROM Project__c
                WHERE Id IN :projectIds
                AND Client__c != null
            ]);

        if (projectMap.isEmpty()) {

            System.debug(
                'FILE UPLOAD: No eligible Projects found.'
            );

            return;
        }

        // =====================================================
        // 3. RETRIEVE DOCUMENT DETAILS
        // =====================================================

        Map<Id, ContentDocument> documentMap =
            new Map<Id, ContentDocument>([
                SELECT
                    Id,
                    Title,
                    LatestPublishedVersionId
                FROM ContentDocument
                WHERE Id IN :documentIds
            ]);

        // Avoid duplicate notifications for the same
        // document and Project within this trigger execution.

        Set<String> queuedKeys = new Set<String>();

        // =====================================================
        // 4. VALIDATE STATUS AND SEND NOTIFICATIONS
        // =====================================================

        for (ContentDocumentLink linkRec : newLinks) {

            if (
                linkRec.LinkedEntityId == null ||
                linkRec.ContentDocumentId == null
            ) {
                continue;
            }

            Project__c projectRec =
                projectMap.get(linkRec.LinkedEntityId);

            if (projectRec == null) {
                continue;
            }

            // =================================================
            // NEW REQUIREMENT:
            // SEND ONLY WHEN PROJECT STATUS IS IN PROGRESS
            // =================================================

            String currentStatus =
                projectRec.Status__c == null
                    ? ''
                    : projectRec.Status__c.trim();

            if (
                !currentStatus.equalsIgnoreCase('In Progress')
            ) {

                System.debug(
                    LoggingLevel.INFO,
                    'FILE UPLOAD NOTIFICATION SKIPPED. ' +
                    'Project=' + projectRec.Id +
                    ', Status=' + currentStatus +
                    ', Reason=Project not In Progress'
                );

                continue;
            }

            // =================================================
            // PREVENT DUPLICATE NOTIFICATIONS
            // =================================================

            String uniqueKey =
                String.valueOf(projectRec.Id) +
                ':' +
                String.valueOf(linkRec.ContentDocumentId);

            if (queuedKeys.contains(uniqueKey)) {
                continue;
            }

            queuedKeys.add(uniqueKey);

            // =================================================
            // GET DOCUMENT NAME
            // =================================================

            String fileName = 'a new document';

            if (
                documentMap.containsKey(
                    linkRec.ContentDocumentId
                )
            ) {

                fileName =
                    documentMap.get(
                        linkRec.ContentDocumentId
                    ).Title;
            }

            // =================================================
            // PREPARE NOTIFICATION
            // =================================================

            String title =
                'New Document Uploaded';

            String messageBody =
                'A new file "' +
                fileName +
                '" has been uploaded to your project ' +
                projectRec.Name +
                '.';

            // =================================================
            // SEND PROJECT-SPECIFIC PUSH NOTIFICATION
            // =================================================

            AreliaPushNotificationService.sendToContactAsync(
                projectRec.Client__c,
                title,
                messageBody,
                'file_upload',
                String.valueOf(
                    linkRec.ContentDocumentId
                ),
                projectRec.Id
            );

            System.debug(
                LoggingLevel.INFO,
                'FILE UPLOAD NOTIFICATION QUEUED. ' +
                'Project=' + projectRec.Id +
                ', Document=' +
                linkRec.ContentDocumentId +
                ', Status=' +
                currentStatus +
                ', Contact=' +
                projectRec.Client__c
            );
        }

        System.debug(
            'FILE UPLOAD NOTIFICATION HANDLER FINISHED'
        );
    }
}