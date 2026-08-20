/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-05-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
private class OpportunityQuotePDFControllerTest {

    @TestSetup
    static void setup() {
        // 1. Create Supervisor (Required context)
        User supervisor = TestDataUtility.createSupervisorUser('pdfUser');

        // 2. Create Opportunity
        Opportunity opp = TestDataUtility.createOpportunity('Quote Opp', supervisor.Id);
        // Set fields required for the PDF Controller logic
        opp.Lead_Name__c = 'PDF Client';
        opp.Email__c = 'pdf@test.com';
        opp.Project_Request_Quotation_Type__c = 'Manual'; 
        opp.Type_of_Project__c = 'Home'; 
        update opp;

        // 3. Create Specific Products 
        Interior_Product__c prod1 = TestDataUtility.createInteriorProduct('Accent Wall', 'Dining Hall', 'Painting & Wall Finishing', 1500);
        
        // 4. Create Active Cart Items
        List<Project_Specification__c> specs = new List<Project_Specification__c>();
        for(Integer i=0; i<3; i++) {
            specs.add(new Project_Specification__c(
                Opportunity__c = opp.Id,
                Interior_Product__c = prod1.Id,
                Quantity__c = 1,
                Unit_Price__c = 1500, 
                Is_Active_Cart_Item__c = true,
                Vendor_Category__c = 'Painting & Wall Finishing' 
            ));
        }
        insert specs;
    }

    // ==========================================
    // 1. Getter Logic Coverage
    // ==========================================

    @IsTest
    static void testGettersEdgeCases() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        PageReference pageRef = Page.Opportunity_Quote_PDF;
        pageRef.getParameters().put('id', opp.Id);
        Test.setCurrentPage(pageRef);

        // --- Scenario A: Manual Quotation but Blank Project Type ---
        opp.Project_Request_Quotation_Type__c = 'Manual';
        opp.Type_of_Project__c = null; // Clear the type
        update opp;

        // Re-instantiate controller to fetch updated data
        OpportunityQuotePDFController controller = new OpportunityQuotePDFController();
        Assert.areEqual('—', controller.projectType, 'Should return dash when Manual Type is blank');

        // --- Scenario B: Unknown/Blank Quotation Type ---
        opp.Project_Request_Quotation_Type__c = 'Manual';
        update opp;
        
        controller = new OpportunityQuotePDFController();
        Assert.areEqual('Manual', controller.quotationType, 'Should return raw value');
        Assert.areEqual('—', controller.projectType, 'Should return dash for unknown quotation type logic');

        Test.stopTest();
    }

    @IsTest
    static void testAutomaticQuotationProjectTypeGetter() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Interior_Project_Type__c projectType = new Interior_Project_Type__c(Name = 'Automatic Project Type');
        insert projectType;

        opp.Interior_Project_Type__c = projectType.Id;
        update opp;
        OpportunityQuotePDFController.forceAutomaticProjectTypeForTest = true;

        Test.startTest();
        PageReference pageRef = Page.Opportunity_Quote_PDF;
        pageRef.getParameters().put('id', opp.Id);
        Test.setCurrentPage(pageRef);
        OpportunityQuotePDFController controller = new OpportunityQuotePDFController();
        Test.stopTest();

        Assert.areEqual('Automatic Project Type', controller.projectType, 'Automatic project type should use related master name.');
    }

    // ==========================================
    // 2. Visualforce Page & Constructor Tests
    // ==========================================

    @IsTest
    static void testVFPageLoadAndGetters() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        PageReference pageRef = Page.Opportunity_Quote_PDF; 
        pageRef.getParameters().put('id', opp.Id);
        Test.setCurrentPage(pageRef);

        OpportunityQuotePDFController controller = new OpportunityQuotePDFController();
        Test.stopTest();

        Assert.isNotNull(controller.Opp, 'Opportunity should be loaded');
        Assert.areEqual(3, controller.specItems.size(), 'Should load 3 active items');
        Assert.areEqual(4500, controller.grandTotal, 'Grand Total should be 4500');
        
        // Basic happy path verification
        Assert.areEqual('Manual', controller.quotationType);
    }

    @IsTest
    static void testVFPageLoadNoId() {
        Test.startTest();
        PageReference pageRef = Page.Opportunity_Quote_PDF;
        Test.setCurrentPage(pageRef);
        OpportunityQuotePDFController controller = new OpportunityQuotePDFController();
        Test.stopTest();

        Assert.isNull(controller.Opp, 'Opportunity should be null if no ID provided');
        Assert.areEqual('—', controller.projectType); 
    }

    // ==========================================
    // 3. Cart Operations Tests
    // ==========================================

    @IsTest
    static void testGetSavedCart() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<Project_Specification__c> cart = OpportunityQuotePDFController.getSavedCart(opp.Id);
        Test.stopTest();

        Assert.areEqual(3, cart.size(), 'Should return 3 active items');
    }

    @IsTest
    static void testSaveCart() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Interior_Product__c prod = TestDataUtility.createInteriorProduct('New Item', 'Dining Hall', 'Painting & Wall Finishing', 300);

        List<Project_Specification__c> newItems = new List<Project_Specification__c>();
        newItems.add(new Project_Specification__c(
            Interior_Product__c = prod.Id,
            Quantity__c = 5,
            Unit_Price__c = 300,
            Vendor_Category__c = 'Painting & Wall Finishing'
        ));

        Test.startTest();
        OpportunityQuotePDFController.saveCart(opp.Id, newItems);
        Test.stopTest();

        List<Project_Specification__c> activeItems = [
            SELECT Id, Quantity__c 
            FROM Project_Specification__c 
            WHERE Opportunity__c = :opp.Id 
            AND Is_Active_Cart_Item__c = TRUE
        ];
        Assert.areEqual(1, activeItems.size(), 'Should replace old items with 1 new active item');
        Assert.areEqual(5, activeItems[0].Quantity__c, 'Quantity should be updated to 5');
    }

    @IsTest
    static void testDeactivateCartItem() {
        Project_Specification__c item = [SELECT Id FROM Project_Specification__c LIMIT 1];

        Test.startTest();
        OpportunityQuotePDFController.deactivateCartItem(item.Id);
        Test.stopTest();

        Project_Specification__c updatedItem = [SELECT Is_Active_Cart_Item__c FROM Project_Specification__c WHERE Id = :item.Id];
        Assert.isFalse(updatedItem.Is_Active_Cart_Item__c, 'Item should be deactivated');
    }

    // ==========================================
    // 4. Quote Generation Tests
    // ==========================================

    @IsTest
    static void testGenerateQuoteAndSaveSuccess() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        String result = OpportunityQuotePDFController.generateQuoteAndSave(opp.Id);
        Test.stopTest();

        Assert.areEqual('SUCCESS', result, 'Should return SUCCESS');
        List<Quotation__c> quotes = [SELECT Id FROM Quotation__c WHERE Opportunity__c = :opp.Id];
        Assert.areEqual(1, quotes.size(), 'Quotation record should be created');
    }

    @IsTest
    static void testGenerateQuoteEmptyCart() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Project_Specification__c> allItems = [SELECT Id FROM Project_Specification__c WHERE Opportunity__c = :opp.Id];
        
        for(Project_Specification__c s : allItems) {
            s.Is_Active_Cart_Item__c = false;
        }
        update allItems;

        Test.startTest();
        try {
            OpportunityQuotePDFController.generateQuoteAndSave(opp.Id);
            Assert.fail('Should throw exception for empty cart');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should be AuraHandledException');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGenerateQuoteNullAndNormalizationBranches() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        List<Project_Specification__c> items = [
            SELECT Id, Quantity__c, Unit_Price__c, Quality__c, Vendor_Category__c
            FROM Project_Specification__c
            WHERE Opportunity__c = :opp.Id
            LIMIT 1
        ];
        items[0].Quantity__c = null;
        items[0].Unit_Price__c = null;
        items[0].Quality__c = null;
        items[0].Vendor_Category__c = null;
        update items;

        Test.startTest();
        Boolean caught = false;
        try {
            OpportunityQuotePDFController.generateQuoteAndSave(null);
        } catch (AuraHandledException e) {
            caught = true;
            Assert.isNotNull(e.getMessage(), 'Null opportunity should include an error message.');
        }
        Boolean caughtNormalizationFailure = false;
        try {
            OpportunityQuotePDFController.generateQuoteAndSave(opp.Id);
        } catch (Exception e) {
            caughtNormalizationFailure = true;
            Assert.isTrue(e.getMessage().contains('Vendor Category') || e.getTypeName().contains('DmlException'), 'Restricted picklist may reject normalized default category.');
        }
        Test.stopTest();

        Assert.isTrue(caught, 'Null opportunity should throw.');
        Assert.isTrue(caughtNormalizationFailure, 'Restricted picklist should reject the normalized default category in this org.');
    }

    @IsTest
    static void testGenerateQuotePdfFailureBranch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        OpportunityQuotePDFController.forcePdfGenerationFailureForTest = true;

        Test.startTest();
        try {
            OpportunityQuotePDFController.generateQuoteAndSave(opp.Id);
            Assert.fail('Forced PDF generation failure should throw.');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage(), 'PDF failure should return an AuraHandledException.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveCartValidation() {
        Test.startTest();
        try {
            OpportunityQuotePDFController.saveCart(null, null);
            Assert.fail('Should throw exception for null inputs');
        } catch (Exception e) {
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'), 'Should be AuraHandledException');
        }
        Test.stopTest();
    }
}