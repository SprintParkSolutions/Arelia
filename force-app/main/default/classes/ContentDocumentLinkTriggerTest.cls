/**
 * @File Name         : ContentDocumentLinkHandlerTest.cls
 * @Description       : Unit tests for ContentDocumentLinkHandler.handleAfterInsert
 *                      Uses TestDataUtility for file creation/linking.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class ContentDocumentLinkTriggerTest {

    private static Id getContentDocumentIdFromUtility() {
        ContentVersion cv = TestDataUtility.createContentVersion('Test File', 'dummy data');
        Account tempAcc   = TestDataUtility.createAccount('Temp Link Account');

        ContentDocumentLink tempCdl = TestDataUtility.linkFileToRecord(cv.Id, tempAcc.Id);
        Id contentDocId = tempCdl.ContentDocumentId;

        delete tempCdl; // cleanup
        System.assertNotEquals(null, contentDocId, 'ContentDocumentId must not be null.');
        return contentDocId;
    }

    // ✅ CDL query helper: MUST filter by ContentDocumentId / LinkedEntityId
    private static ContentDocumentLink fetchCdl(Id linkedEntityId, Id contentDocId) {
        return [
            SELECT Id, ShareType, Visibility, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedEntityId
              AND ContentDocumentId = :contentDocId
            LIMIT 1
        ];
    }

    @IsTest
    static void test_updatesVisibilityToAllUsers_forInteriorDesign() {
        Interior_Design__c design = new Interior_Design__c(Name = 'Test Interior Design');
        insert design;

        Id contentDocId = getContentDocumentIdFromUtility();

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = design.Id,
            ContentDocumentId = contentDocId,
            ShareType         = 'I',
            Visibility        = 'InternalUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        ContentDocumentLink updated = fetchCdl(design.Id, contentDocId);

        System.assertEquals('AllUsers', updated.Visibility, 'Visibility must be updated to AllUsers.');
        System.assertEquals('V', updated.ShareType, 'ShareType should be updated to V per handler.');
        System.assertEquals(design.Id, updated.LinkedEntityId, 'LinkedEntityId must remain same.');
    }

    @IsTest
    static void test_updatesVisibilityToAllUsers_forAccount() {
        Account acc = TestDataUtility.createAccount('Test Account');
        Id contentDocId = getContentDocumentIdFromUtility();

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = acc.Id,
            ContentDocumentId = contentDocId,
            ShareType         = 'I',
            Visibility        = 'InternalUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        ContentDocumentLink updated = fetchCdl(acc.Id, contentDocId);

        System.assertEquals('AllUsers', updated.Visibility, 'Visibility must be updated to AllUsers.');
        System.assertEquals('V', updated.ShareType, 'ShareType should be updated to V per handler.');
        System.assertEquals(acc.Id, updated.LinkedEntityId, 'LinkedEntityId must remain same.');
    }

    @IsTest
    static void test_skipsWhenAlreadyAllUsers() {
        Account acc = TestDataUtility.createAccount('Already AllUsers Account');
        Id contentDocId = getContentDocumentIdFromUtility();

        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId    = acc.Id,
            ContentDocumentId = contentDocId,
            ShareType         = 'I',
            Visibility        = 'AllUsers'
        );

        Test.startTest();
        insert cdl;
        Test.stopTest();

        ContentDocumentLink afterInsert = fetchCdl(acc.Id, contentDocId);

        System.assertEquals('AllUsers', afterInsert.Visibility, 'Visibility should stay AllUsers.');
        System.assertEquals('I', afterInsert.ShareType, 'ShareType should NOT change when skipped.');
    }

    @IsTest
    static void test_bulkInsert_updatesOnlyNeeded() {
        // Create 200 Accounts
        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accs.add(new Account(Name = 'Bulk Acc ' + i));
        }
        insert accs;

        // Collect LinkedEntityIds for IN query (required by CDL restriction)
        Set<Id> accIds = new Set<Id>();
        for (Account a : accs) accIds.add(a.Id);

        Id contentDocId = getContentDocumentIdFromUtility();

        Integer needsUpdateCount = 150;
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (Integer i = 0; i < accs.size(); i++) {
            links.add(new ContentDocumentLink(
                LinkedEntityId    = accs[i].Id,
                ContentDocumentId = contentDocId,
                ShareType         = 'I',
                Visibility        = (i < needsUpdateCount ? 'InternalUsers' : 'AllUsers')
            ));
        }

        Test.startTest();
        insert links;
        Test.stopTest();

        // ✅ FIXED QUERY: filter by ContentDocumentId and LinkedEntityId IN :accIds
        List<ContentDocumentLink> reloaded = [
            SELECT Id, ShareType, Visibility, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocId
              AND LinkedEntityId IN :accIds
        ];

        System.assertEquals(200, reloaded.size(), 'Should fetch exactly 200 CDLs for this ContentDocumentId.');

        Integer allUsersCount = 0;
        Integer vCount = 0;
        Integer iCount = 0;

        for (ContentDocumentLink c : reloaded) {
            if (c.Visibility == 'AllUsers') allUsersCount++;
            if (c.ShareType == 'V') vCount++;
            if (c.ShareType == 'I') iCount++;
        }

        System.assertEquals(200, allUsersCount, 'All rows must end with Visibility=AllUsers.');
        System.assertEquals(needsUpdateCount, vCount, 'Only rows needing update should become ShareType=V.');
        System.assertEquals(200 - needsUpdateCount, iCount, 'Skipped rows should keep ShareType=I.');
    }

    @IsTest
    static void test_handleAfterInsert_nullAndEmpty_safe() {
        Test.startTest();
        ContentDocumentLinkHandler.handleAfterInsert(null);
        ContentDocumentLinkHandler.handleAfterInsert(new List<ContentDocumentLink>());
        Test.stopTest();

        System.assert(true, 'No exception expected for null/empty input.');
    }
}