@isTest
private class AreliaProjectStatusNotificationTest {

    @isTest
    static void testHandleAfterUpdateEnqueuesPushNotification() {
        Contact contactRecord = new Contact(
            LastName = 'Arelia Test Client',
            Email = 'arelia.test.client@example.com'
        );
        insert contactRecord;

        Project__c originalProject = new Project__c(
            Name = 'Arelia Project Status Notification Test',
            Status__c = 'In Progress',
            Project_Status__c = 'Active',
            Supervisor_Estimated_Budget__c = 100000,
            Client__c = contactRecord.Id
        );
        insert originalProject;

        Project__c updatedProject = originalProject.clone(true, true, true, true);
        updatedProject.Project_Completion_Status__c = 100;

        Map<Id, Project__c> oldProjectMap = new Map<Id, Project__c>{
            originalProject.Id => originalProject
        };

        List<Project__c> newProjectList = new List<Project__c>{
            updatedProject
        };

        Test.startTest();
            AreliaProjectStatusNotificationHandler.handleAfterUpdate(
                newProjectList,
                oldProjectMap
            );
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];

        System.assertEquals(1, jobs.size(), 'A queueable push notification job should be enqueued.');
        System.assertEquals('Queueable', jobs[0].JobType);
    }
}