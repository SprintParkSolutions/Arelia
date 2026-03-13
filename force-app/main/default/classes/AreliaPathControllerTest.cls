@IsTest
public class AreliaPathControllerTest {

    private static final String TEST_OPP_NAME = 'Path Test Opp';

    @TestSetup
    static void setup() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User u = new User(
            Alias = 'pthuser',
            Email = 'pathUser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'pathUser' + DateTime.now().getTime() + '@testorg.com'
        );
        insert u;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opp = TestDataUtility.createOpportunity(TEST_OPP_NAME, u.Id);

            opp.Architect_Name__c = null;
            opp.Architecture_Client_Approval_Sent__c = false;
            opp.Architecture_Manager_Approval__c = false;
            opp.Catalogue_Link_Sent__c = false;
            opp.Client_Agreement_Sent__c = false;
            opp.Client_Agreement_Signed__c = false;
            opp.All_Vendors_Agreement_Completed__c = false;
            opp.Budget_Review_Status__c = null;
            opp.Payment_Terms_Status__c = null;
            update opp;
        }
    }

    private static Opportunity getTestOpp() {
        return [SELECT Id,Name, StageName,Architect_Name__c,Architecture_Client_Approval_Sent__c,
                    Architecture_Manager_Approval__c,Catalogue_Link_Sent__c,Client_Agreement_Sent__c,
                    Client_Agreement_Signed__c,All_Vendors_Agreement_Completed__c,Budget_Review_Status__c,
                    Payment_Terms_Status__c FROM Opportunity
                WHERE Name = :TEST_OPP_NAME LIMIT 1];
    }

    // ==========================================
    // 1. Test Metadata (Steps List)
    // ==========================================
    @IsTest
    static void testGetAllStages() {
        Test.startTest();
        List<Map<String, String>> stages = AreliaPathController.getAllStages();
        Test.stopTest();

        Assert.areEqual(24, stages.size(), 'Should return all 24 defined stages from the metadata list');

        Boolean foundNewStage = false;
        for (Map<String, String> stage : stages) {
            if (stage.get('value') == 'Send Architecture Client Approval') {
                foundNewStage = true;
                break;
            }
        }
        Assert.isTrue(foundNewStage, 'The list should contain the specific stage "Send Architecture Client Approval"');
    }

    // ==========================================
    // 2. Test Priority Overrides (Resumed/Negotiation)
    // ==========================================
    @IsTest
    static void testPathStatusOverrides() {
        Opportunity opp = getTestOpp();

        opp.All_Vendors_Agreement_Completed__c = true;
        opp.StageName = 'Resumed';
        update opp;

        String status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Resumed', status, 'Status should be "Resumed" when Opportunity Stage is "Resumed"');

        opp = getTestOpp();
        opp.StageName = 'Negotiation/Review';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Negotiation/Review', status, 'Status should be "Negotiation/Review" when Opportunity Stage is "Negotiation/Review"');
    }

    // ==========================================
    // 3. Test The Current Waterfall Logic Sequence
    // ==========================================
    @IsTest
    static void testPathLogicSequence() {
        Opportunity opp = getTestOpp();
        String status;

        Test.startTest();

        // STEP 1: Initial State
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Enter Architect Data', status, 'Initial status should be "Enter Architect Data" when architect is blank');

        // STEP 2: Architect Entered
        opp.Architect_Name__c = 'Test Architect';
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Send Architecture Client Approval', status, 'Status should advance to "Send Architecture Client Approval"');

        // STEP 3: Architecture Sent
        opp = getTestOpp();
        opp.Architecture_Client_Approval_Sent__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Architecture Approval', status, 'Status should advance to "Client Architecture Approval"');

        // STEP 4: Architecture Approved
        ContentVersion cv = TestDataUtility.createContentVersion('Arch Design File', 'Content');
        TestDataUtility.createArchitectureDesign(opp.Id, cv.Id, 'Approved');

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Architecture Manager Approval', status, 'Status should advance to "Architecture Manager Approval"');

        // STEP 5: Manager Approval
        opp = getTestOpp();
        opp.Architecture_Manager_Approval__c = true;
        update opp;
        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Upload Proforma Invoice', status, 'Status should advance to "Upload Proforma Invoice"');

        // Use same proforma record and update it step by step
        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);

        // STEP 6: Proforma Sent
        pi.Status__c = 'Sent';
        pi.Manager_Approval__c = false;
        update pi;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Proforma Client Approval', status, 'Status should advance to "Proforma Client Approval"');

        // STEP 7: Proforma Approved but Manager Approval Pending
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = false;
        update pi;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Proforma Manager Approval', status, 'Status should advance to "Proforma Manager Approval"');

        // STEP 8: Proforma Fully Approved
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = true;
        update pi;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Budget Review Client Approval', status, 'Status should advance to "Budget Review Client Approval"');

        // STEP 9: Catalogue Link Sent
        opp = getTestOpp();
        opp.Catalogue_Link_Sent__c = true;
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Received', status, 'Status should advance to "Catalogue Received" after catalogue link sent');

        // STEP 10: Quotation Created (Unapproved)
        Quotation__c quote = TestDataUtility.createQuotation(opp.Id, 'Test Quote');
        quote.Manager_Approval__c = false;
        update quote;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Catalogue Manager Approval', status, 'Status should advance to "Catalogue Manager Approval"');

        // STEP 11: Quotation Approved
        quote.Manager_Approval__c = true;
        update quote;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Budget Review Client Approval', status, 'Status should move back to budget review flow after quotation approval');

        // STEP 12: Budget Client Approval Done
        opp = getTestOpp();
        opp.Budget_Review_Status__c = 'Client Approved';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Budget Review Manager Approval', status, 'Status should advance to "Budget Review Manager Approval"');

        // STEP 13: Budget Manager Approval Done
        opp = getTestOpp();
        opp.Budget_Review_Status__c = 'Manager Approved';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Payment Terms Manager Approval', status, 'Status should advance to "Payment Terms Manager Approval"');

        // STEP 14: Payment Terms Manager Approval Done
        opp = getTestOpp();
        opp.Payment_Terms_Status__c = 'Manager Approved';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Payment Terms Client Approval', status, 'Status should advance to "Payment Terms Client Approval"');

        // STEP 15: Payment Terms Client Approval Done
        opp = getTestOpp();
        opp.Payment_Terms_Status__c = 'Client Approved';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Sent', status, 'Status should advance to "Client Agreement Sent"');

        // STEP 16: Agreement Sent
        opp = getTestOpp();
        opp.Client_Agreement_Sent__c = true;
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Client Agreement Signed', status, 'Status should advance to "Client Agreement Signed"');

        // STEP 17: Agreement Signed
        opp = getTestOpp();
        opp.Client_Agreement_Signed__c = true;
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Tender Invites', status, 'Status should advance to "Tender Invites"');

        // STEP 18: Vendor Agreement Sent
        Vendor__c v = TestDataUtility.createVendor('Test Vendor', 'Electrical & Networking', 'v@test.com');
        Vendor_Opportunity__c vo = TestDataUtility.createVendorOpportunity(opp.Id, v.Id, 'Active');
        vo.Vendor_Agreement_Sent__c = true;
        update vo;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Vendor Agreement Signed', status, 'Status should advance to "Vendor Agreement Signed"');

        // STEP 19: Vendor Agreements Completed
        vo.Vendor_Agreement_Signed__c = true;
        update vo;

        opp = getTestOpp();
        opp.All_Vendors_Agreement_Completed__c = true;
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Status should advance to "Closed Won"');

        // STEP 20: Final State
        opp = getTestOpp();
        opp.StageName = 'Closed Won';
        update opp;

        status = AreliaPathController.getPathStatus(opp.Id);
        Assert.areEqual('Closed Won', status, 'Final status returned should be "Closed Won"');

        Test.stopTest();
    }

    // ==========================================
    // 4. Additional Coverage
    // ==========================================
    @IsTest
    static void testAdditionalBranches() {
        Opportunity opp = getTestOpp();

        opp.Architect_Name__c = 'Branch Architect';
        opp.Architecture_Client_Approval_Sent__c = true;
        opp.Architecture_Manager_Approval__c = true;
        opp.Catalogue_Link_Sent__c = true;
        opp.Budget_Review_Status__c = 'Manager Approved';
        opp.Payment_Terms_Status__c = 'Client Approved';
        opp.Client_Agreement_Sent__c = true;
        opp.Client_Agreement_Signed__c = true;
        update opp;

        ContentVersion cv = TestDataUtility.createContentVersion('Arch Branch File', 'Content');
        TestDataUtility.createArchitectureDesign(opp.Id, cv.Id, 'Approved');

        Proforma_Invoice__c pi = TestDataUtility.createProformaInvoice(opp.Id);
        pi.Status__c = 'Approved';
        pi.Manager_Approval__c = true;
        update pi;

        // Add approved quotation so catalogue stages are completed
        Quotation__c quote = TestDataUtility.createQuotation(opp.Id, 'Branch Quote');
        quote.Manager_Approval__c = true;
        update quote;

        Test.startTest();
        String status = AreliaPathController.getPathStatus(opp.Id);
        Test.stopTest();

        Assert.areEqual('Tender Invites', status, 'When vendor agreement is not sent, status should return Tender Invites');
    }
}