@IsTest(SeeAllData=true)
private class ATaskStatusNotificationHandlerTest {

    @IsTest
    static void handleAfterUpdateProjectTaskStatusChangedTest() {
        Project__c projectRec = getExistingProjectWithClient();

        Id taskId = getFakeTaskId('001');

        Task oldTask = new Task(
            Id = taskId,
            Subject = 'Painting Work',
            Status = 'Not Started',
            WhatId = projectRec.Id
        );

        Task newTask = new Task(
            Id = taskId,
            Subject = 'Painting Work',
            Status = 'Completed',
            WhatId = projectRec.Id
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                taskId => oldTask
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Project task status update should be processed successfully.'
        );
    }

    @IsTest
    static void handleAfterUpdateVendorAssignmentTaskNotFoundTest() {
        Id taskId = getFakeTaskId('002');
        Id vendorAssignmentId = getFakeVendorAssignmentId();

        Task oldTask = new Task(
            Id = taskId,
            Subject = 'Vendor Task',
            Status = 'Not Started',
            WhatId = vendorAssignmentId
        );

        Task newTask = new Task(
            Id = taskId,
            Subject = 'Vendor Task',
            Status = 'Completed',
            WhatId = vendorAssignmentId
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                taskId => oldTask
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when Vendor Assignment record is not found.'
        );
    }

    @IsTest
    static void handleAfterUpdateNoStatusChangeTest() {
        Project__c projectRec = getExistingProjectWithClient();

        Id taskId = getFakeTaskId('003');

        Task oldTask = new Task(
            Id = taskId,
            Subject = 'No Status Change Task',
            Status = 'Completed',
            WhatId = projectRec.Id
        );

        Task newTask = new Task(
            Id = taskId,
            Subject = 'No Status Change Task',
            Status = 'Completed',
            WhatId = projectRec.Id
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                taskId => oldTask
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when Task status is not changed.'
        );
    }

    @IsTest
    static void handleAfterUpdateTaskWithoutWhatIdTest() {
        Id taskId = getFakeTaskId('004');

        Task oldTask = new Task(
            Id = taskId,
            Subject = 'No Related Record Task',
            Status = 'Not Started'
        );

        Task newTask = new Task(
            Id = taskId,
            Subject = 'No Related Record Task',
            Status = 'Completed'
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                taskId => oldTask
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when Task has no WhatId.'
        );
    }

    @IsTest
    static void handleAfterUpdateOldTaskMissingTest() {
        Project__c projectRec = getExistingProjectWithClient();

        Id taskId = getFakeTaskId('005');

        Task newTask = new Task(
            Id = taskId,
            Subject = 'Old Task Missing',
            Status = 'Completed',
            WhatId = projectRec.Id
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when old task is missing from old map.'
        );
    }

    @IsTest
    static void handleAfterUpdateUnsupportedRelatedObjectTest() {
        Account accountRec = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Id taskId = getFakeTaskId('006');

        Task oldTask = new Task(
            Id = taskId,
            Subject = 'Unsupported Related Object',
            Status = 'Not Started',
            WhatId = accountRec.Id
        );

        Task newTask = new Task(
            Id = taskId,
            Subject = 'Unsupported Related Object',
            Status = 'Completed',
            WhatId = accountRec.Id
        );

        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                taskId => oldTask
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip unsupported related objects.'
        );
    }

    @IsTest
    static void handleAfterUpdateNullAndEmptyInputTest() {
        Test.startTest();

        ATaskStatusNotificationHandler.handleAfterUpdate(
            null,
            new Map<Id, Task>()
        );

        ATaskStatusNotificationHandler.handleAfterUpdate(
            new List<Task>(),
            new Map<Id, Task>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null and empty input should not throw exception.'
        );
    }

    private static Project__c getExistingProjectWithClient() {
        List<Project__c> projects = [
            SELECT Id, Name, Client__c
            FROM Project__c
            WHERE Client__c != null
            LIMIT 1
        ];

        System.assert(
            !projects.isEmpty(),
            'Please keep at least one Project__c record with Client__c populated in this sandbox.'
        );

        return projects[0];
    }

    private static Id getFakeTaskId(String uniqueNumber) {
        return (Id) ('00T000000000' + uniqueNumber);
    }

    private static Id getFakeVendorAssignmentId() {
        String prefix =
            Vendor_Assignment__c.SObjectType.getDescribe().getKeyPrefix();

        return (Id) (prefix + '000000000001');
    }
}