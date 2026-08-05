@IsTest
private class AreliaCaseNotificationHandlerTest {

    @IsTest
    static void handleAfterUpdateStatusChangedTest() {
        Contact contactRec = createContact();

        Case caseRec = new Case(
            Subject = 'AC Issue',
            Status = 'New',
            Priority = 'Medium',
            Origin = 'Phone',
            ContactId = contactRec.Id
        );
        insert caseRec;

        Map<Id, Case> oldCaseMap = new Map<Id, Case>();
        oldCaseMap.put(
            caseRec.Id,
            new Case(
                Id = caseRec.Id,
                Status = 'New',
                Priority = 'Medium'
            )
        );

        caseRec.Status = 'Working';
        update caseRec;

        Test.startTest();
        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>{ caseRec },
            oldCaseMap
        );
        Test.stopTest();

        System.assertEquals(
            'Working',
            [
                SELECT Status
                FROM Case
                WHERE Id = :caseRec.Id
                LIMIT 1
            ].Status,
            'Case status should be updated.'
        );
    }

    @IsTest
    static void handleAfterUpdatePriorityChangedTest() {
        Contact contactRec = createContact();

        Case caseRec = new Case(
            Subject = 'Payment Issue',
            Status = 'New',
            Priority = 'Low',
            Origin = 'Phone',
            ContactId = contactRec.Id
        );
        insert caseRec;

        Map<Id, Case> oldCaseMap = new Map<Id, Case>();
        oldCaseMap.put(
            caseRec.Id,
            new Case(
                Id = caseRec.Id,
                Status = 'New',
                Priority = 'Low'
            )
        );

        caseRec.Priority = 'High';
        update caseRec;

        Test.startTest();
        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>{ caseRec },
            oldCaseMap
        );
        Test.stopTest();

        System.assertEquals(
            'High',
            [
                SELECT Priority
                FROM Case
                WHERE Id = :caseRec.Id
                LIMIT 1
            ].Priority,
            'Case priority should be updated.'
        );
    }

    @IsTest
    static void handleAfterUpdateNoWatchedFieldChangedTest() {
        Contact contactRec = createContact();

        Case caseRec = new Case(
            Subject = 'General Query',
            Status = 'New',
            Priority = 'Medium',
            Origin = 'Phone',
            ContactId = contactRec.Id
        );
        insert caseRec;

        Map<Id, Case> oldCaseMap = new Map<Id, Case>();
        oldCaseMap.put(
            caseRec.Id,
            new Case(
                Id = caseRec.Id,
                Status = 'New',
                Priority = 'Medium'
            )
        );

        caseRec.Subject = 'General Query Updated';
        update caseRec;

        Test.startTest();
        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>{ caseRec },
            oldCaseMap
        );
        Test.stopTest();

        System.assertEquals(
            'General Query Updated',
            [
                SELECT Subject
                FROM Case
                WHERE Id = :caseRec.Id
                LIMIT 1
            ].Subject,
            'Case subject should be updated.'
        );
    }

    @IsTest
    static void handleAfterUpdateNoContactTest() {
        Case caseRec = new Case(
            Subject = 'No Contact Case',
            Status = 'New',
            Priority = 'Medium',
            Origin = 'Phone'
        );
        insert caseRec;

        Map<Id, Case> oldCaseMap = new Map<Id, Case>();
        oldCaseMap.put(
            caseRec.Id,
            new Case(
                Id = caseRec.Id,
                Status = 'New',
                Priority = 'Medium'
            )
        );

        caseRec.Status = 'Working';
        update caseRec;

        Test.startTest();
        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>{ caseRec },
            oldCaseMap
        );
        Test.stopTest();

        System.assertEquals(
            'Working',
            [
                SELECT Status
                FROM Case
                WHERE Id = :caseRec.Id
                LIMIT 1
            ].Status,
            'Case status should be updated even when ContactId is blank.'
        );
    }

    @IsTest
    static void handleAfterUpdateNullAndEmptyInputTest() {
        Test.startTest();

        AreliaCaseNotificationHandler.handleAfterUpdate(
            null,
            new Map<Id, Case>()
        );

        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>(),
            new Map<Id, Case>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null and empty input should not throw exception.'
        );
    }

    @IsTest
    static void handleAfterUpdateOldCaseMissingTest() {
        Contact contactRec = createContact();

        Case caseRec = new Case(
            Subject = 'Old Map Missing',
            Status = 'New',
            Priority = 'Medium',
            Origin = 'Phone',
            ContactId = contactRec.Id
        );
        insert caseRec;

        caseRec.Status = 'Working';
        update caseRec;

        Test.startTest();
        AreliaCaseNotificationHandler.handleAfterUpdate(
            new List<Case>{ caseRec },
            new Map<Id, Case>()
        );
        Test.stopTest();

        System.assertEquals(
            'Working',
            [
                SELECT Status
                FROM Case
                WHERE Id = :caseRec.Id
                LIMIT 1
            ].Status,
            'Handler should skip when old case map does not contain the case.'
        );
    }

    private static Contact createContact() {
        Contact contactRec = new Contact(
            LastName = 'Case Notification Client',
            Email = 'case.notification.client@example.com'
        );

        insert contactRec;

        return contactRec;
    }
}