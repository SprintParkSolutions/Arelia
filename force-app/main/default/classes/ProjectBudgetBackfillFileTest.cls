/**
 * @description Covers backfillPendingRequestIfNeeded's file-attachment lookup
 * (findRecentlyLinkedFileIds), exercised via the mobile app's raw REST bypass pattern
 * (PATCHing Additional_Request_Status__c directly instead of going through
 * ProjectAdditionalBudgetController.submitRequest).
 */
@IsTest
private class ProjectBudgetBackfillFileTest {

    private static String anyActivePicklistValue(SObjectField fieldRef) {
        for (Schema.PicklistEntry pe : fieldRef.getDescribe().getPicklistValues()) {
            if (pe.isActive()) { return pe.getValue(); }
        }
        return null;
    }

    @testSetup
    static void setupData() {
        Project__c p = new Project__c(
            Name = 'Backfill Test Project',
            Additional_Budget__c = 1000,
            Supervisor_Estimated_Budget__c = 2000
        );

        // Avoid hardcoding restricted picklists that vary by org.
        try { p.put('Status__c', anyActivePicklistValue(Project__c.Status__c)); } catch (Exception e1) {}
        try { p.put('Project_Status__c', anyActivePicklistValue(Project__c.Project_Status__c)); } catch (Exception e2) {}

        insert p;
    }

    /**
     * Reproduces the reported bug directly against the lookup method: given a file already
     * consumed by a prior request (linked before the project's last save) and a new file linked
     * for the current request (linked after that save), only the new file's ContentDocumentId
     * should come back - not both.
     */
    @IsTest
    static void testOnlyPicksUpFilesLinkedAfterThePreviousSave() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Datetime previousSaveTime = Datetime.now().addMinutes(-10);

        // Prior request's file - already consumed, linked well before the project's last save.
        ContentVersion oldFile = TestDataUtility.createContentVersion('OldRequestFile', 'old file');
        TestDataUtility.linkFileToRecord(oldFile.Id, p.Id);
        Id oldDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :oldFile.Id].ContentDocumentId;
        Test.setCreatedDate(oldDocId, previousSaveTime.addMinutes(-20));

        // Current request's own file - linked after the project's last save.
        ContentVersion newFile = TestDataUtility.createContentVersion('NewRequestFile', 'new file');
        TestDataUtility.linkFileToRecord(newFile.Id, p.Id);
        Id newDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :newFile.Id].ContentDocumentId;
        Test.setCreatedDate(newDocId, previousSaveTime.addMinutes(1));

        Test.startTest();
        List<Id> result = ProjectAdditionalBudgetController.findRecentlyLinkedFileIds(p.Id, previousSaveTime);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Only the current request\'s file should be returned.');
        System.assertEquals(newDocId, result[0], 'The returned file must be the newly linked one, not the older already-consumed file.');
    }

    /**
     * Reproduces the exact real-world timing observed in production: each file is uploaded only
     * a few SECONDS before its own request's save (not minutes), so a backward buffer of even a
     * couple of minutes still recaptures the prior request's file. There must be no backward
     * buffer at all - the window starts exactly at the previous save.
     */
    @IsTest
    static void testExcludesPriorFileUploadedSecondsBeforeItsOwnSave() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Datetime request1SaveTime = Datetime.now().addMinutes(-5);

        // Request 1's file, uploaded 4 seconds before request 1's own save.
        ContentVersion request1File = TestDataUtility.createContentVersion('Request1Blueprint', 'blueprint');
        TestDataUtility.linkFileToRecord(request1File.Id, p.Id);
        Id request1DocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :request1File.Id].ContentDocumentId;
        Test.setCreatedDate(request1DocId, request1SaveTime.addSeconds(-4));

        // Request 2's file, uploaded 3 seconds before request 2's own save, 3 minutes after request 1's save.
        Datetime request2FileTime = request1SaveTime.addMinutes(3);
        ContentVersion request2File = TestDataUtility.createContentVersion('Request2Photo', 'photo');
        TestDataUtility.linkFileToRecord(request2File.Id, p.Id);
        Id request2DocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :request2File.Id].ContentDocumentId;
        Test.setCreatedDate(request2DocId, request2FileTime);

        Test.startTest();
        // request 2's backfill anchors on request 1's save time (oldProj.LastModifiedDate).
        List<Id> result = ProjectAdditionalBudgetController.findRecentlyLinkedFileIds(p.Id, request1SaveTime);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Only the second request\'s file should be returned, even though the first request\'s file was uploaded only seconds before its own save.');
        System.assertEquals(request2DocId, result[0], 'The file uploaded seconds before the prior save must not leak into the next request.');
    }

    @IsTest
    static void testFallsBackToFifteenMinuteWindowWhenNoPreviousSave() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        ContentVersion recentFile = TestDataUtility.createContentVersion('RecentFile', 'recent file');
        TestDataUtility.linkFileToRecord(recentFile.Id, p.Id);
        Id recentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :recentFile.Id].ContentDocumentId;
        Test.setCreatedDate(recentDocId, Datetime.now().addMinutes(-5));

        Test.startTest();
        List<Id> result = ProjectAdditionalBudgetController.findRecentlyLinkedFileIds(p.Id, null);
        Test.stopTest();

        System.assert(result.contains(recentDocId), 'A file linked 5 minutes ago should be within the fallback 15-minute window.');
    }

    /**
     * Reproduces the exact real-world payload observed from the mobile app: its PATCH sends
     * Additional_Budget_ContentDocumentIds__c already containing BOTH the stale id from a prior,
     * already-processed request AND the genuinely new one, comma-joined. The stale id must be
     * dropped regardless of the client having supplied it.
     */
    @IsTest
    static void testDropsStaleClientSuppliedIdKeepingOnlyTheNewOne() {
        Project__c p = [SELECT Id, LastModifiedDate, Additional_Budget_ContentDocumentIds__c FROM Project__c LIMIT 1];

        // A file already consumed by a prior, already-processed request.
        ContentVersion oldFile = TestDataUtility.createContentVersion('OldRequestFile', 'old file');
        TestDataUtility.linkFileToRecord(oldFile.Id, p.Id);
        Id oldDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :oldFile.Id].ContentDocumentId;
        Test.setCreatedDate(oldDocId, p.LastModifiedDate.addMinutes(-20));

        // The current request's own file, uploaded after the project's last save.
        ContentVersion newFile = TestDataUtility.createContentVersion('NewRequestFile', 'new file');
        TestDataUtility.linkFileToRecord(newFile.Id, p.Id);
        Id newDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :newFile.Id].ContentDocumentId;
        Test.setCreatedDate(newDocId, p.LastModifiedDate.addMinutes(1));

        Project__c newProj = new Project__c(
            Id = p.Id,
            Additional_Budget_ContentDocumentIds__c = String.valueOf(oldDocId) + ',' + String.valueOf(newDocId)
        );

        Test.startTest();
        String result = ProjectAdditionalBudgetController.resolveAttachmentIdsForThisRequest(p.Id, newProj, p);
        Test.stopTest();

        System.assertEquals(
            String.valueOf(newDocId),
            result,
            'Only the newly linked file should survive - the stale id from the prior request must be dropped even though the client supplied it.'
        );
    }

    @IsTest
    static void testTrustsSuppliedIdsWhenNothingRecentCanBeVerified() {
        // No files linked to the project at all - can't independently verify anything, so the
        // supplied value (e.g. from a normal submitRequest() call) is trusted as-is.
        Project__c p = [SELECT Id, LastModifiedDate, Additional_Budget_ContentDocumentIds__c FROM Project__c LIMIT 1];
        String fakeCsv = '069000000000000AAA';
        Project__c newProj = new Project__c(Id = p.Id, Additional_Budget_ContentDocumentIds__c = fakeCsv);

        Test.startTest();
        String result = ProjectAdditionalBudgetController.resolveAttachmentIdsForThisRequest(p.Id, newProj, p);
        Test.stopTest();

        System.assertEquals(fakeCsv, result, 'With nothing recent to verify against, the supplied value should be trusted as-is.');
    }
}