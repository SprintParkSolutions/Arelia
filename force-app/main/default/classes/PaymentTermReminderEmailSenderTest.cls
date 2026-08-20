@IsTest
private class PaymentTermReminderEmailSenderTest {

    // ============================================================================
    // SETUP
    // ============================================================================
    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account acc = TestDataUtility.createAccount('Payment Term Test Account');
            Contact con = TestDataUtility.createContact('Payment Term Client', 'ptclient@test.com', 'pass123');
            con.AccountId = acc.Id;
            update con;

            TestDataUtility.createProject('Payment Term Test Project', 50000, con.Id);
            // Project with no Client, used to test the missing-client skip branch.
            TestDataUtility.createProject('Clientless Test Project', 50000, null);

            TestDataUtility.createSpecificEmailTemplate('Arelia_Payment_Reminder', 'Arelia Payment Reminder', 'Payment Reminder');
            TestDataUtility.createSpecificEmailTemplate('Arelia_Payment_Overdue', 'Arelia Payment Overdue', 'Payment Overdue');
        }
    }

    private static Payment_Term__c createTerm(Id projectId, String label, Integer daysOffset, Boolean received) {
        Payment_Term__c term = TestDataUtility.createPaymentTerm(projectId, label, 10);
        term.Due_Date__c = daysOffset == null ? null : Date.today().addDays(daysOffset);
        term.Payment_Received__c = received;
        update term;
        return term;
    }

    private static PaymentTermReminderEmailSender.Request buildRequest(Id termId) {
        PaymentTermReminderEmailSender.Request req = new PaymentTermReminderEmailSender.Request();
        req.paymentTermId = termId;
        return req;
    }

    // ============================================================================
    // GUARD CLAUSE TESTS
    // ============================================================================

    @IsTest
    static void testNullAndEmptyRequestsSendNoEmail() {
        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(null);
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>());
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'Null or empty request lists should not send any email.');
    }

    @IsTest
    static void testRequestsWithNoValidTermIdsSendNoEmail() {
        List<PaymentTermReminderEmailSender.Request> requests = new List<PaymentTermReminderEmailSender.Request>{
            null,
            buildRequest(null)
        };

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(requests);
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'Requests without a valid Payment Term Id should not send any email.');
    }

    @IsTest
    static void testMissingTemplatesSendNoEmail() {
        delete [SELECT Id FROM EmailTemplate WHERE DeveloperName IN ('Arelia_Payment_Reminder', 'Arelia_Payment_Overdue')];

        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'Due Today', 0, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'When no templates are configured, no email should be sent.');
    }

    // ============================================================================
    // SKIP BRANCH TESTS
    // ============================================================================

    @IsTest
    static void testPaymentAlreadyReceivedSendsNoEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'Already Paid', 0, true);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'A term with Payment Received should not trigger an email.');
    }

    @IsTest
    static void testNoDueDateSendsNoEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'No Due Date', null, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'A term without a Due Date should not trigger an email.');
    }

    @IsTest
    static void testClientlessProjectSendsNoEmail() {
        Project__c clientlessProj = [SELECT Id FROM Project__c WHERE Name = 'Clientless Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(clientlessProj.Id, 'No Client', 0, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'A project without a Client should not trigger an email.');
    }

    @IsTest
    static void testNonMatchingDaysUntilDueSendsNoEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'Not Due Yet', 10, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails, finalEmails, 'A due date outside the reminder/overdue windows should not trigger an email.');
    }

    // ============================================================================
    // REMINDER TEMPLATE TESTS (daysUntilDue == 3 || daysUntilDue == 0)
    // ============================================================================

    @IsTest
    static void testDueInThreeDaysSendsReminderEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'Due In 3 Days', 3, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'A term due in 3 days should trigger one reminder email.');
    }

    @IsTest
    static void testDueTodaySendsReminderEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c term = createTerm(proj.Id, 'Due Today', 0, false);

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(new List<PaymentTermReminderEmailSender.Request>{ buildRequest(term.Id) });
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(initialEmails + 1, finalEmails, 'A term due today should trigger one reminder email.');
    }

    // ============================================================================
    // OVERDUE TEMPLATE TESTS (daysUntilDue == -1 || -3 || -7)
    // ============================================================================

    @IsTest
    static void testOverdueTermsSendOverdueEmail() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];
        Payment_Term__c overdueBy1 = createTerm(proj.Id, 'Overdue 1 Day', -1, false);
        Payment_Term__c overdueBy3 = createTerm(proj.Id, 'Overdue 3 Days', -3, false);
        Payment_Term__c overdueBy7 = createTerm(proj.Id, 'Overdue 7 Days', -7, false);

        List<PaymentTermReminderEmailSender.Request> requests = new List<PaymentTermReminderEmailSender.Request>{
            buildRequest(overdueBy1.Id),
            buildRequest(overdueBy3.Id),
            buildRequest(overdueBy7.Id)
        };

        Test.startTest();
        Integer initialEmails = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(requests);
        Integer finalEmails = Limits.getEmailInvocations();
        Test.stopTest();

        // All 3 qualifying terms are batched into a single Messaging.sendEmail call,
        // so getEmailInvocations() (which counts calls, not messages) only rises by 1.
        Assert.areEqual(initialEmails + 1, finalEmails, 'Terms overdue by 1, 3 and 7 days should be batched into a single sendEmail call.');
    }

    // ============================================================================
    // BULK / MIXED SCENARIO TEST
    // ============================================================================

    @IsTest
    static void testBulkMixedTermsSendOnlyQualifyingEmails() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Payment Term Test Project' LIMIT 1];

        List<PaymentTermReminderEmailSender.Request> qualifyingRequests = new List<PaymentTermReminderEmailSender.Request>{
            buildRequest(createTerm(proj.Id, 'Bulk Due In 3 Days', 3, false).Id),
            buildRequest(createTerm(proj.Id, 'Bulk Due Today', 0, false).Id),
            buildRequest(createTerm(proj.Id, 'Bulk Overdue 1 Day', -1, false).Id)
        };

        List<PaymentTermReminderEmailSender.Request> nonQualifyingRequests = new List<PaymentTermReminderEmailSender.Request>{
            buildRequest(createTerm(proj.Id, 'Bulk Not Due Yet', 20, false).Id),
            buildRequest(createTerm(proj.Id, 'Bulk Already Paid', 0, true).Id),
            buildRequest(createTerm(proj.Id, 'Bulk No Due Date', null, false).Id)
        };

        Test.startTest();
        Integer beforeNonQualifying = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(nonQualifyingRequests);
        Integer afterNonQualifying = Limits.getEmailInvocations();
        PaymentTermReminderEmailSender.sendReminderEmails(qualifyingRequests);
        Integer afterQualifying = Limits.getEmailInvocations();
        Test.stopTest();

        Assert.areEqual(beforeNonQualifying, afterNonQualifying, 'Non-qualifying terms alone should not trigger a sendEmail call.');
        Assert.areEqual(afterNonQualifying + 1, afterQualifying, 'Qualifying terms should trigger a batched sendEmail call.');
    }
}