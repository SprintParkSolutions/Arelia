@isTest
public class PublicApprovalControllerTest {

    @testSetup
    static void setup() {
        // 1. Create User
        User u = TestDataUtility.createSupervisorUser('approver');

        // 2. Create Opportunity (Required parent)
        Opportunity opp = TestDataUtility.createOpportunity('Test Opp Approval', u.Id);

        // 3. Create Custom Quotation
        TestDataUtility.createQuotation(opp.Id, 'Test Quote');
    }

    // ==========================================
    // URL PARAMETER LOGIC
    // ==========================================

    @isTest
    static void testSetRecordIdFromClientSuccess() {
        Quotation__c q = [SELECT Id FROM Quotation__c LIMIT 1];

        // Use string instantiation to avoid compile error if Page doesn't exist
        PageReference pageRef = new PageReference('/apex/PublicApprovalPage'); 
        Test.setCurrentPage(pageRef);
        
        // Set URL Parameter 'pId'
        ApexPages.currentPage().getParameters().put('pId', q.Id);

        PublicApprovalController controller = new PublicApprovalController();
        
        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.areEqual(q.Id, controller.quoteId, 'Controller should retrieve Id from URL');
        Assert.isFalse(controller.hasError, 'Should not have error');
    }

    @isTest
    static void testSetRecordIdFromClientMissing() {
        Test.setCurrentPage(new PageReference('/apex/PublicApprovalPage'));
        // Do NOT set parameters

        PublicApprovalController controller = new PublicApprovalController();
        
        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should flag error');
        Assert.isTrue(controller.errorMessage.contains('could not be retrieved'), 'Error message mismatch');
    }

    @isTest
    static void testSetRecordIdFromClientInvalidFormat() {
        Test.setCurrentPage(new PageReference('/apex/PublicApprovalPage'));
        // Set invalid ID format
        ApexPages.currentPage().getParameters().put('pId', 'InvalidId123');

        PublicApprovalController controller = new PublicApprovalController();
        
        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should flag error');
        Assert.isTrue(controller.errorMessage.contains('Invalid ID format'), 'Should catch casting exception');
    }

    // ==========================================
    // APPROVAL LOGIC
    // ==========================================

    @isTest
    static void testDoApproveSuccess() {
        Quotation__c q = [SELECT Id FROM Quotation__c LIMIT 1];
        
        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = q.Id; // Simulate ID being set

        Test.startTest();
        controller.doApprove();
        Test.stopTest();

        Assert.isTrue(controller.approved, 'Approved flag should be true');
        Assert.isFalse(controller.hasError, 'Should have no errors');
    }

    @isTest
    static void testDoApproveMissingId() {
        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = null; 

        Test.startTest();
        controller.doApprove();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should flag error');
        // FIXED: Added assertion message
        Assert.areEqual('System Error: Record ID is lost.', controller.errorMessage, 'Error message should match for missing ID');
    }

    @isTest
    static void testDoApproveException() {
        Quotation__c q = [SELECT Id FROM Quotation__c LIMIT 1];
        
        // Force an exception in the Service by deleting the record first.
        delete q; 

        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = q.Id;

        Test.startTest();
        controller.doApprove();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should catch the DML exception');
        Assert.isNotNull(controller.errorMessage, 'Error message should be populated');
    }

    // ==========================================
    // REJECTION LOGIC
    // ==========================================

    @isTest
    static void testRejectionWorkflowUI() {
        PublicApprovalController controller = new PublicApprovalController();

        // 1. Enable Mode
        controller.doReject(); 
        Assert.isTrue(controller.isRejecting, 'Should be in rejecting mode');

        // 2. Cancel Mode
        controller.rejectionReason = 'Typing...';
        controller.cancelRejectMode();
        Assert.isFalse(controller.isRejecting, 'Should exit rejecting mode');
        Assert.areEqual('', controller.rejectionReason, 'Reason should be cleared');
    }

    @isTest
    static void testDoConfirmRejectSuccess() {
        Quotation__c q = [SELECT Id FROM Quotation__c LIMIT 1];
        
        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = q.Id;
        controller.rejectionReason = 'Too expensive';

        Test.startTest();
        controller.doConfirmReject();
        Test.stopTest();

        Assert.isTrue(controller.rejected, 'Rejected flag should be true');
        Assert.isFalse(controller.hasError, 'Should have no errors');
    }

    @isTest
    static void testDoConfirmRejectValidation() {
        Quotation__c q = [SELECT Id FROM Quotation__c LIMIT 1];
        
        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = q.Id;
        controller.rejectionReason = ''; // Empty reason

        Test.startTest();
        controller.doConfirmReject();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should flag error');
        Assert.isTrue(controller.errorMessage.contains('Please enter a reason'), 'Validation message missing');
    }

    @isTest
    static void testDoConfirmRejectMissingId() {
        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteId = null;
        controller.rejectionReason = 'Reason';

        Test.startTest();
        controller.doConfirmReject();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Should flag error');
        // FIXED: Added assertion message
        Assert.areEqual('System Error: Record ID is lost.', controller.errorMessage, 'Error message should match for missing ID');
    }
}