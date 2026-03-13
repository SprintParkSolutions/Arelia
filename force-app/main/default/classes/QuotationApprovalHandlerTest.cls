@IsTest
private class QuotationApprovalHandlerTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor (Alias <8 chars)
        User supervisor = TestDataUtility.createSupervisorUser('qtHndlr');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Quote Handler Opp', supervisor.Id);

        // 3. Create Quotation
        Quotation__c quote = new Quotation__c(
            Name = 'Test Quote',
            Opportunity__c = opp.Id,
            Manager_Approval__c = false // Initial State
        );
        insert quote;

        // 4. Create File (ContentVersion)
        ContentVersion cv = TestDataUtility.createContentVersion('Quote_PDF', 'Test Content');
        
        // CRITICAL FIX: Re-query the ContentVersion to get the auto-generated ContentDocumentId
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        
        // 5. Link File to Quotation
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId, // Now this is not null
            LinkedEntityId = quote.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert cdl;
    }

    @IsTest
    static void testHandleAfterUpdateSuccess() {
        // Fetch Setup Data
        Quotation__c quote = [SELECT Id, Opportunity__c, Manager_Approval__c FROM Quotation__c LIMIT 1];
        
        // Prepare Mock Trigger Context
        // OLD STATE: Approval = false
        Map<Id, Quotation__c> oldMap = new Map<Id, Quotation__c>();
        oldMap.put(quote.Id, quote); // In DB it is currently false

        // NEW STATE: Approval = true
        List<Quotation__c> newList = new List<Quotation__c>();
        Quotation__c updatedQuote = quote.clone(true, true, true, true);
        updatedQuote.Manager_Approval__c = true;
        newList.add(updatedQuote);

        Test.startTest();
        // Manually invoke the handler logic
        QuotationApprovalHandler.handleAfterUpdate(newList, oldMap);
        Test.stopTest();

        // ASSERTION
        // The file linked to the Quote should now ALSO be linked to the Opportunity
        ContentDocumentLink oppLink = [
            SELECT Id, LinkedEntityId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :quote.Opportunity__c 
            LIMIT 1
        ];

        Assert.isNotNull(oppLink, 'File should be shared with Opportunity after approval');
        Assert.areEqual(quote.Opportunity__c, oppLink.LinkedEntityId, 'Link should point to the Opportunity');
    }

    @IsTest
    static void testHandleAfterUpdateNoChange() {
        // Fetch Setup Data
        Quotation__c quote = [SELECT Id, Opportunity__c, Manager_Approval__c FROM Quotation__c LIMIT 1];
        
        // Prepare Mock Trigger Context
        // OLD STATE: Approval = false
        Map<Id, Quotation__c> oldMap = new Map<Id, Quotation__c>();
        oldMap.put(quote.Id, quote); 

        // NEW STATE: Approval = false (Just changing Name or other field)
        List<Quotation__c> newList = new List<Quotation__c>();
        Quotation__c updatedQuote = quote.clone(true, true, true, true);
        updatedQuote.Name = 'Updated Name Only';
        updatedQuote.Manager_Approval__c = false; // Remains false
        newList.add(updatedQuote);

        Test.startTest();
        QuotationApprovalHandler.handleAfterUpdate(newList, oldMap);
        Test.stopTest();

        // ASSERTION
        // File should NOT be shared with Opportunity
        List<ContentDocumentLink> oppLinks = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :quote.Opportunity__c
        ];

        Assert.isTrue(oppLinks.isEmpty(), 'File should NOT be shared if approval is not granted');
    }

    @IsTest
    static void testHandleAfterUpdateAlreadyApproved() {
        // Verify logic: Old = True, New = True (Should do nothing)
        
        Quotation__c quote = [SELECT Id, Opportunity__c FROM Quotation__c LIMIT 1];
        
        // Prepare Mock Context
        Quotation__c oldQuote = quote.clone(true, true, true, true);
        oldQuote.Manager_Approval__c = true; // Was already approved
        
        Map<Id, Quotation__c> oldMap = new Map<Id, Quotation__c>();
        oldMap.put(quote.Id, oldQuote);

        Quotation__c newQuote = quote.clone(true, true, true, true);
        newQuote.Manager_Approval__c = true; // Still approved
        
        List<Quotation__c> newList = new List<Quotation__c>{ newQuote };

        Test.startTest();
        QuotationApprovalHandler.handleAfterUpdate(newList, oldMap);
        Test.stopTest();

        // ASSERTION
        List<ContentDocumentLink> oppLinks = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :quote.Opportunity__c
        ];
        Assert.isTrue(oppLinks.isEmpty(), 'Should not re-share/process if status did not change');
    }
}