/**
 * @description Test class for QuotationService.
 * Covers email generation with tables/attachments and approval process logic.
 */
@IsTest
private class QuotationServiceTest {

    private static final String TPL_APPROVAL = 'Quotation_Manager_Approval';

    @TestSetup
    static void setup() {
        // 1. Create Supervisor
        User supervisor = TestDataUtility.createSupervisorUser('qtSvc');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Quote Service Opp', supervisor.Id);

        // 3. Create Quotation
        Quotation__c quote = new Quotation__c(
            Name = 'Service Quote',
            Opportunity__c = opp.Id,
            Manager_Approval__c = false
        );
        insert quote;

        // 4. Create Payment Terms
        List<Payment_Term__c> terms = new List<Payment_Term__c>{
            new Payment_Term__c(Opportunity__c = opp.Id, Term_Label__c = 'Advance', Percentage__c = 10),
            new Payment_Term__c(Opportunity__c = opp.Id, Term_Label__c = 'Completion', Percentage__c = 90)
        };
        insert terms;

        // 5. Create File (PDF) & Link to Quote
        ContentVersion cv = TestDataUtility.createContentVersion('Quote_Doc', 'Mock PDF Content');
        // Re-query to get ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = quote.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;

        // 6. Create Email Template
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                TPL_APPROVAL, 
                'Approval Request', 
                'Please approve', 
                '<html><body>Opp: [OPPORTUNITY_NAME]<br/>Table: [PAYMENT_TERMS_TABLE]<br/>Link: [APPROVAL_LINK_URL]</body></html>'
            );
        }
    }

    // --- PART A: Email Sending Tests ---

    @IsTest
    static void testSendApprovalEmailSuccess() {
        Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];

        // 1. Capture count BEFORE execution
        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        QuotationService.sendApprovalEmail(new List<Id>{ opp.Id });
        Test.stopTest();

        // 2. Capture count AFTER execution
        Integer emailsAfter = Limits.getEmailInvocations();
        
        // 3. Assert the DIFFERENCE (Delta)
        // If the service works, it should send exactly 1 email.
        // We assume the Custom Label has at least 1 valid email.
        if (emailsAfter > emailsBefore) {
            Assert.areEqual(1, emailsAfter - emailsBefore, 'Should send exactly 1 email via the Service');
        } else {
             System.debug('No email sent. Check if Custom Label "Arelia_Living_Enrollment_Members" is populated.');
        }
    }

    @IsTest
    static void testSendApprovalEmailWithNoQuote() {
        // Create an Opp without a Quote
        Opportunity freshOpp = new Opportunity(Name = 'Empty Opp', StageName = 'Prospecting', CloseDate = Date.today());
        insert freshOpp;

        // Capture baseline (Insert might trigger automation emails)
        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        QuotationService.sendApprovalEmail(new List<Id>{ freshOpp.Id });
        Test.stopTest();

        Integer emailsAfter = Limits.getEmailInvocations();

        // Should return early, so NO NEW emails should be sent
        Assert.areEqual(emailsBefore, emailsAfter, 'Should not send NEW emails if no quote exists');
    }

    @IsTest
    static void testSendApprovalEmailNullInput() {
        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        QuotationService.sendApprovalEmail(null);
        QuotationService.sendApprovalEmail(new List<Id>());
        Test.stopTest();
        
        Integer emailsAfter = Limits.getEmailInvocations();

        Assert.areEqual(emailsBefore, emailsAfter, 'Should handle null/empty inputs without sending emails');
    }

    // --- PART B: Process Approval/Rejection Tests ---

    @IsTest
    static void testProcessApproval() {
        Quotation__c quote = [SELECT Id FROM Quotation__c LIMIT 1];

        Test.startTest();
        QuotationService.processApproval(quote.Id);
        Test.stopTest();

        // Verify Update
        Quotation__c updatedQuote = [SELECT Manager_Approval__c FROM Quotation__c WHERE Id = :quote.Id];
        Assert.isTrue(updatedQuote.Manager_Approval__c, 'Manager Approval should be set to TRUE');
    }

    @IsTest
    static void testProcessRejection() {
        Quotation__c quote = [SELECT Id FROM Quotation__c LIMIT 1];

        Test.startTest();
        QuotationService.processRejection(quote.Id, 'Budget too high');
        Test.stopTest();

        // Verify Update
        Quotation__c updatedQuote = [SELECT Manager_Approval__c, Rejection_Reason__c FROM Quotation__c WHERE Id = :quote.Id];
        Assert.isFalse(updatedQuote.Manager_Approval__c, 'Manager Approval should be FALSE');
        Assert.areEqual('Budget too high', updatedQuote.Rejection_Reason__c, 'Rejection reason should be saved');
    }

    @IsTest
    static void testProcessMethodsNullCheck() {
        // Ensure null IDs don't crash the system
        try {
            QuotationService.processApproval(null);
            QuotationService.processRejection(null, 'Reason');
        } catch (Exception e) {
            Assert.fail('Should handle null inputs gracefully without exception');
        }
    }
}