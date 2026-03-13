/**
 * @description       : Test class for ExpenseSheetController
 * @author            : Salesforce Developer
 * @group             : Tests
 * @last modified on  : 02-24-2026
 **/
@isTest
private class ExpenseSheetControllerTest {

    @TestSetup
    static void setupTestData() {
        // 1. Setup Users and Contacts (Added FirstName to cover name concatenation logic)
        User supervisor = TestDataUtility.createSupervisorUser('supv');
        supervisor.FirstName = 'Super'; 
        update supervisor;

        Contact clientContact = TestDataUtility.createContact('WellnessClient', 'wellness@arelia.com', 'pass123');

        // 2. Setup Project linked to Supervisor and Client
        Project__c proj = TestDataUtility.createProject('Arelia Sanctuary', 50000, clientContact.Id);
        proj.Supervisor_User__c = supervisor.Id;
        update proj;

        // 3. Create Draft Expense Sheet
        Project_Expense_Sheet__c sheet = new Project_Expense_Sheet__c(
            Project__c = proj.Id,
            Sheet_Date__c = Date.today(),
            Status__c = 'Draft'
        );
        insert sheet;

        // 4. Create Line Item with safe picklist values
        Expense_Line_Item__c lineItem = new Expense_Line_Item__c(
            Project_Expense_Sheet__c = sheet.Id,
            Type__c = 'Material',
            Item_Name__c = 'Acoustic Panels',
            Brand__c = 'Arelia Source',
            Quantity__c = 10,
            Rate__c = 500,
            Amount__c = 5000,
            Description__c = 'Soundproofing'
        );
        insert lineItem;

        // 5. Create a dummy old 'Expense_Report' file to cover the deletion logic block
        ContentVersion oldPdf = TestDataUtility.createContentVersion('Expense_Report', 'OldData');
        TestDataUtility.linkFileToRecord(oldPdf.Id, sheet.Id);

        // 6. Create Dummy Email Templates (Bypasses missing label org errors)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                TestDataUtility.createSpecificEmailTemplate('Arelia_Expense_Template', 'Expense Submitted', 'Expense Submitted: {ProjectName}');
                TestDataUtility.createSpecificEmailTemplate('Arelia_Expense_Approved_Template', 'Expense Approved', 'Expense Approved: {ProjectName}');
            } catch (Exception e) {
                // Ignore if duplicates exist in the org during test execution
            }
        }
    }

    @isTest
    static void testSaveExpenseSheetAsDraft() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Prepare JSON payload for a New Draft
        ExpenseSheetController.SheetData dto = new ExpenseSheetController.SheetData();
        dto.projectId = proj.Id;
        dto.grandTotal = 2500;
        dto.status = 'Draft';
        dto.items = createDummyLineItems();

        Test.startTest();
        String result = ExpenseSheetController.saveExpenseSheet(JSON.serialize(dto));
        Test.stopTest();

        System.assertEquals('Success', result, 'Controller should return Success upon saving draft.');
        
        List<Project_Expense_Sheet__c> sheets = [SELECT Id, Status__c FROM Project_Expense_Sheet__c WHERE Status__c = 'Draft'];
        System.assert(sheets.size() >= 1, 'A new draft sheet should have been inserted.');
    }

    @isTest
    static void testSaveExpenseSheetAndSubmit() {
        Project_Expense_Sheet__c existingSheet = [SELECT Id, Project__c FROM Project_Expense_Sheet__c LIMIT 1];

        // Prepare JSON payload for an Existing Sheet moving to 'Submitted'
        ExpenseSheetController.SheetData dto = new ExpenseSheetController.SheetData();
        dto.sheetId = existingSheet.Id;
        dto.projectId = existingSheet.Project__c;
        dto.grandTotal = 5000;
        dto.status = 'Submitted';
        dto.items = createDummyLineItems();

        // Add dummy file attachments
        ExpenseSheetController.FileData fd = new ExpenseSheetController.FileData();
        fd.name = 'Invoice_001.pdf';
        fd.base64 = 'VGVzdERhdGE='; // Base64 for "TestData"
        dto.billFiles = new List<ExpenseSheetController.FileData>{ fd };

        Test.startTest();
        // This will insert items, files, and trigger the @Future generatePDFAndSendEmail method
        String result = ExpenseSheetController.saveExpenseSheet(JSON.serialize(dto));
        Test.stopTest(); // Forces the @Future method to execute synchronously

        System.assertEquals('Success', result, 'Controller should return Success upon submitting.');
        
        Project_Expense_Sheet__c updatedSheet = [SELECT Id, Status__c FROM Project_Expense_Sheet__c WHERE Id = :existingSheet.Id];
        System.assertEquals('Submitted', updatedSheet.Status__c, 'Sheet status should be updated to Submitted.');
        
        List<ContentVersion> files = [SELECT Id FROM ContentVersion WHERE Title = 'Invoice_001.pdf'];
        System.assertEquals(1, files.size(), 'Bill file should have been inserted and attached.');
    }

    @isTest
    static void testSaveExpenseSheetException() {
        Test.startTest();
        try {
            // Passing malformed JSON to trigger AuraHandledException
            ExpenseSheetController.saveExpenseSheet('Invalid_JSON_{}');
            System.assert(false, 'Expected an AuraHandledException to be thrown, but execution continued.');
        } catch (Exception ex) {
            System.assert(ex instanceof AuraHandledException, 'Exception should be wrapped in AuraHandledException.');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateSheetStatusApproved() {
        Project_Expense_Sheet__c existingSheet = [SELECT Id, Project__c FROM Project_Expense_Sheet__c LIMIT 1];

        Test.startTest();
        // This will update status, recalculate rollups, and trigger the supervisor email notification
        String result = ExpenseSheetController.updateSheetStatus(existingSheet.Id, 'Approved');
        Test.stopTest();

        System.assertEquals('Success', result, 'Status update should return Success.');
        
        Project_Expense_Sheet__c updatedSheet = [SELECT Id, Status__c FROM Project_Expense_Sheet__c WHERE Id = :existingSheet.Id];
        System.assertEquals('Approved', updatedSheet.Status__c, 'Status should be Approved.');

        Project__c proj = [SELECT Id, Total_Approved_Expenses__c FROM Project__c WHERE Id = :existingSheet.Project__c];
        System.assertNotEquals(null, proj.Total_Approved_Expenses__c, 'Total Approved Expenses rollup should be calculated.');
    }

    @isTest
    static void testGetMethods() {
        Project_Expense_Sheet__c sheet = [SELECT Id, Project__c FROM Project_Expense_Sheet__c LIMIT 1];

        // Create a dummy file linked to the sheet to test existingFiles payload mapping
        ContentVersion cv = TestDataUtility.createContentVersion('Site_Photos', 'ImageData');
        TestDataUtility.linkFileToRecord(cv.Id, sheet.Id);

        Test.startTest();
        
        // Test getSheetDetails
        Project_Expense_Sheet__c fetchedSheet = ExpenseSheetController.getSheetDetails(sheet.Id);
        System.assertNotEquals(null, fetchedSheet, 'Should retrieve sheet details.');
        System.assertEquals(sheet.Id, fetchedSheet.Id, 'Fetched sheet ID should match.');

        // Test getDraftDetails
        ExpenseSheetController.SheetData draftData = ExpenseSheetController.getDraftDetails(sheet.Id);
        System.assertNotEquals(null, draftData, 'Should retrieve draft wrapper payload.');
        System.assertEquals(sheet.Id, draftData.sheetId, 'Draft sheet ID should match.');
        System.assert(draftData.items.size() > 0, 'Draft should include existing line items.');
        System.assert(draftData.existingFiles.size() > 0, 'Draft should include existing non-PDF files.');

        // Test getProjectExpenses
        List<Project_Expense_Sheet__c> projectExpenses = ExpenseSheetController.getProjectExpenses(sheet.Project__c);
        System.assert(projectExpenses.size() > 0, 'Should return a list of expenses for the given project.');

        Test.stopTest();
    }

    // --- HELPER METHODS ---

    private static List<ExpenseSheetController.LineItemData> createDummyLineItems() {
        ExpenseSheetController.LineItemData item1 = new ExpenseSheetController.LineItemData();
        // Ensure these exact values match the ones that successfully inserted in @TestSetup
        item1.type = 'Material'; 
        item1.name = 'Acoustic Panels';
        item1.brand = 'Arelia Source'; 
        item1.qty = 10;
        item1.rate = 500;
        item1.amount = 5000;
        item1.description = 'Soundproofing';

        return new List<ExpenseSheetController.LineItemData>{ item1 };
    }
}