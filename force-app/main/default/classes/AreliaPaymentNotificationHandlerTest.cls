@IsTest
private class AreliaPaymentNotificationHandlerTest {

    @testSetup
    static void setupTestData() {
        Contact clientContact = TestDataUtility.createContact(
            'PaymentClient',
            'payment.client@test.com',
            'pass123'
        );

        Project__c project = TestDataUtility.createProject(
            'Payment Notification Project',
            10000,
            clientContact.Id
        );

        TestDataUtility.createPaymentTerm(
            project.Id,
            'Initial Payment',
            25.0
        );
    }

    @IsTest
    static void testHandleAfterUpdateEnqueuesPushNotification() {
        Payment_Term__c existingTerm = [
            SELECT Id,
                Project__c,
                Percentage__c,
                Due_Date__c,
                Term_Label__c,
                Payment_Received__c
            FROM Payment_Term__c
            LIMIT 1
        ];

        Payment_Term__c oldTerm = existingTerm.clone(true, false, false, false);
        existingTerm.Percentage__c = 30.0;

        Test.startTest();
            AreliaPaymentNotificationHandler.handleAfterUpdate(
                new List<Payment_Term__c>{ existingTerm },
                new Map<Id, Payment_Term__c>{ existingTerm.Id => oldTerm }
            );
        Test.stopTest();

        List<AsyncApexJob> jobs = [
            SELECT Id, JobType, Status
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];

        System.assertEquals(1, jobs.size(), 'A queueable push notification job should be enqueued.');
        System.assertEquals('Queueable', jobs[0].JobType, 'Expected a Queueable job.');
        System.assertEquals('Completed', jobs[0].Status, 'The queueable job should complete in test context.');
    }

    @IsTest
    static void testHandleAfterUpdateSkipsNotificationWhenClientMissing() {
        Contact clientContact = TestDataUtility.createContact(
            'SkipClient',
            'skip.client@test.com',
            'pass123'
        );

        Project__c projectWithoutClient = TestDataUtility.createProject(
            'Payment Notification Skip Project',
            10000,
            clientContact.Id
        );
        projectWithoutClient.Client__c = null;
        update projectWithoutClient;

        Payment_Term__c paymentTerm = TestDataUtility.createPaymentTerm(
            projectWithoutClient.Id,
            'Skip Payment',
            20.0
        );

        Payment_Term__c oldTerm = paymentTerm.clone(true, false, false, false);
        paymentTerm.Term_Label__c = 'Skip Payment Updated';

        Test.startTest();
            AreliaPaymentNotificationHandler.handleAfterUpdate(
                new List<Payment_Term__c>{ paymentTerm },
                new Map<Id, Payment_Term__c>{ paymentTerm.Id => oldTerm }
            );
        Test.stopTest();

        Integer queueableJobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];

        System.assertEquals(
            0,
            queueableJobCount,
            'No queueable job should be created when the project client is missing.'
        );
    }
}