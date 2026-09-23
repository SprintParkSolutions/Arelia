@IsTest
private class AreliaPaymentNotificationHandlerTest {

    @TestSetup
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
            WHERE Project__c != null
            LIMIT 1
        ];

        Payment_Term__c oldTerm =
            existingTerm.clone(true, false, false, false);

        existingTerm.Percentage__c = 30.0;

        Test.startTest();

        Integer jobsBefore = Limits.getQueueableJobs();

        AreliaPaymentNotificationHandler.handleAfterUpdate(
            new List<Payment_Term__c>{ existingTerm },
            new Map<Id, Payment_Term__c>{
                existingTerm.Id => oldTerm
            }
        );

        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertEquals(
            jobsBefore + 1,
            jobsAfter,
            'A push notification Queueable job should be enqueued.'
        );

        Test.stopTest();
    }

    @IsTest
    static void testHandleAfterUpdateSkipsNotificationWhenClientMissing() {
        Project__c projectWithoutClient =
            TestDataUtility.createProject(
                'Payment Notification Skip Project',
                10000,
                null
            );

        Payment_Term__c paymentTerm =
            TestDataUtility.createPaymentTerm(
                projectWithoutClient.Id,
                'Skip Payment',
                20.0
            );

        Payment_Term__c oldTerm =
            paymentTerm.clone(true, false, false, false);

        paymentTerm.Term_Label__c =
            'Skip Payment Updated';

        Test.startTest();

        Integer jobsBefore = Limits.getQueueableJobs();

        AreliaPaymentNotificationHandler.handleAfterUpdate(
            new List<Payment_Term__c>{ paymentTerm },
            new Map<Id, Payment_Term__c>{
                paymentTerm.Id => oldTerm
            }
        );

        Integer jobsAfter = Limits.getQueueableJobs();

        System.assertEquals(
            jobsBefore,
            jobsAfter,
            'No push notification Queueable job should be enqueued '
            + 'when the project client is missing.'
        );

        Test.stopTest();
    }
}