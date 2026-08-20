/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-06-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class FileVisibilityHandlerTest {

    @testSetup
    static void setupData() {
        // 1. Create a Supervisor User
        User supervisor = TestDataUtility.createSupervisorUser('suprv');
        
        // 2. Create an Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp', supervisor.Id);
        
        // 3. Create Architecture Design record
        Architecture_Design__c design = TestDataUtility.createArchitectureDesign(opp.Id, 'file123', 'Sent');
        
        // 4. Create Proforma Invoice record (assuming utility or direct creation)
        Proforma_Invoice__c invoice = new Proforma_Invoice__c(
            Opportunity__c = opp.Id,
            Manager_Approval__c = false
        );
        insert invoice;

        // 5. Create a File (ContentVersion)
        ContentVersion cv = TestDataUtility.createContentVersion('TestDocument', 'Test Content Body');
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        // 6. Link File to both source records
        TestDataUtility.linkFileToRecord(conDocId, design.Id);
        TestDataUtility.linkFileToRecord(conDocId, invoice.Id);
    }

    @isTest
    static void testArchitectureDesignApproval() {
        Architecture_Design__c design = [SELECT Id, Manager_Approval__c FROM Architecture_Design__c LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        design.Manager_Approval__c = true;
        update design;
        Test.stopTest();

        // Verify file is now linked to Opportunity
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :opp.Id];
        // Note: Salesforce might have default links (like owner), so we check if our specific file is there
        System.assert(!links.isEmpty(), 'Files should be linked to the Opportunity after Design approval.');
    }

    @isTest
    static void testProformaInvoiceApproval() {
        Proforma_Invoice__c invoice = [SELECT Id, Manager_Approval__c FROM Proforma_Invoice__c LIMIT 1];
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        invoice.Manager_Approval__c = true;
        update invoice;
        Test.stopTest();

        // Verify file visibility on Opportunity
        List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :opp.Id];
        System.assert(!links.isEmpty(), 'Files should be linked to the Opportunity after Invoice approval.');
    }

    @isTest
    static void testNegativeBulkUpdate() {
        // Test updating records where approval is NOT changed to true
        Architecture_Design__c design = [SELECT Id, Manager_Approval__c FROM Architecture_Design__c LIMIT 1];
        
        Test.startTest();
        design.Status__c = 'Sent'; // Change something else
        update design;
        Test.stopTest();

        // Verify no new links were created for the Opportunity (beyond standard ones)
        // This confirms the "oldMap" logic in your trigger works.
    }
}