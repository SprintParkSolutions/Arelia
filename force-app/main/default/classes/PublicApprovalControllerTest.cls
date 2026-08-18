@IsTest
private class PublicApprovalControllerTest {
    private static final String SUPERVISOR_ALIAS = 'pubApp';
    private static final String OPPORTUNITY_NAME = 'Public Approval Opp';

    private static final String AVAILABLE_QUOTE_NAME = 'Available Quote';
    private static final String APPROVED_QUOTE_NAME = 'Approved Quote';
    private static final String REJECTED_QUOTE_NAME = 'Rejected Quote';
    private static final String DELETED_QUOTE_NAME = 'Deleted Quote';

    private static final String PARAM_ID = 'id';
    private static final String PARAM_PID = 'pId';
    private static final String PARAM_RECORD_ID = 'recordId';
    private static final String PARAM_QUOTE_ID = 'quoteId';
    private static final String PARAM_C_RECORD_ID = 'c__recordId';

    private static final String REJECTION_REASON = 'Quotation amount is not approved by manager.';

    @TestSetup
    static void setupTestData() {
        User supervisorUser = TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            supervisorUser.Id
        );

        TestDataUtility.createQuotation(
            opportunityRecord.Id,
            AVAILABLE_QUOTE_NAME
        );

        Quotation__c approvedQuote = TestDataUtility.createQuotation(
            opportunityRecord.Id,
            APPROVED_QUOTE_NAME
        );
        approvedQuote.Manager_approval__c = true;

        Quotation__c rejectedQuote = TestDataUtility.createQuotation(
            opportunityRecord.Id,
            REJECTED_QUOTE_NAME
        );
        rejectedQuote.Rejection_Reason__c = REJECTION_REASON;

        update new List<Quotation__c>{
            approvedQuote,
            rejectedQuote
        };
    }

    @IsTest
    static void testConstructorInitializesWithoutUrlParameter() {
        prepareBlankPage();

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isFalse(controller.approved, 'Approved flag should be false by default.');
        Assert.isFalse(controller.rejected, 'Rejected flag should be false by default.');
        Assert.isFalse(controller.hasError, 'Error flag should be false by default.');
        Assert.isFalse(controller.pageInitialized, 'Page should not be initialized without URL parameter.');
        Assert.isFalse(controller.responseAlreadyRecorded, 'Response should not be marked as recorded.');
        Assert.areEqual('', controller.rejectionReason, 'Rejection reason should be blank by default.');
    }

    @IsTest
    static void testConstructorLoadsValidQuoteIdFromUrl() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Page should be initialized when valid quoteId is available.');
        Assert.areEqual(quotationRecord.Id, controller.quoteId, 'Controller should store the quotation Id.');
        Assert.isFalse(controller.hasError, 'Controller should not show error for valid quotation Id.');
        Assert.isFalse(controller.responseAlreadyRecorded, 'Fresh quotation should not be expired.');
    }

    @IsTest
    static void testSetRecordIdFromClientUsesQuoteIdValue() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        prepareBlankPage();

        PublicApprovalController controller = new PublicApprovalController();
        controller.quoteIdValue = String.valueOf(quotationRecord.Id);

        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Client initialization should mark page as initialized.');
        Assert.areEqual(quotationRecord.Id, controller.quoteId, 'Client quoteIdValue should be assigned.');
        Assert.isFalse(controller.hasError, 'Valid client quoteIdValue should not set error.');
    }

    @IsTest
    static void testSetRecordIdFromClientUsesDirectParameter() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        prepareBlankPage();

        PublicApprovalController controller = new PublicApprovalController();
        ApexPages.currentPage().getParameters().put(PARAM_PID, String.valueOf(quotationRecord.Id));

        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Client initialization should be completed.');
        Assert.areEqual(quotationRecord.Id, controller.quoteId, 'Controller should read quotation Id from pId.');
        Assert.isFalse(controller.hasError, 'Valid pId parameter should not set error.');
    }

    @IsTest
    static void testSetRecordIdFromClientWithoutIdShowsError() {
        prepareBlankPage();

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.setRecordIdFromClient();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Page should be initialized after client call.');
        Assert.isTrue(controller.hasError, 'Missing client Id should show error.');
        Assert.isNotNull(controller.errorMessage, 'Error message should be shown when Id is missing.');
    }

    @IsTest
    static void testConstructorWithInvalidIdShowsError() {
        preparePageWithParameter(PARAM_ID, 'invalid-quotation-id');

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Page should initialize when URL parameter is present.');
        Assert.isTrue(controller.hasError, 'Invalid Id should show error.');
        Assert.isNotNull(controller.errorMessage, 'Invalid Id should populate error message.');
    }

    @IsTest
    static void testConstructorWithWrongObjectIdShowsError() {
        Opportunity opportunityRecord = getOpportunityByName(OPPORTUNITY_NAME);
        preparePageWithParameter(PARAM_RECORD_ID, opportunityRecord.Id);

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Page should initialize for recordId parameter.');
        Assert.isTrue(controller.hasError, 'Non-quotation Id should show error.');
        Assert.isNotNull(controller.errorMessage, 'Wrong object Id should populate error message.');
    }

    @IsTest
    static void testConstructorWithDeletedQuotationShowsError() {
        Opportunity opportunityRecord = getOpportunityByName(OPPORTUNITY_NAME);
        Quotation__c quotationRecord = TestDataUtility.createQuotation(
            opportunityRecord.Id,
            DELETED_QUOTE_NAME
        );
        Id deletedQuoteId = quotationRecord.Id;
        delete quotationRecord;

        preparePageWithParameter(PARAM_C_RECORD_ID, String.valueOf(deletedQuoteId));

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isTrue(controller.pageInitialized, 'Page should initialize for deleted quotation Id.');
        Assert.isTrue(controller.hasError, 'Deleted quotation should show invalid link error.');
        Assert.isNotNull(controller.errorMessage, 'Deleted quotation should populate error message.');
    }

    @IsTest
    static void testShowAndCloseApproveConfirmation() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.showApproveConfirmation();
        controller.closeApproveConfirmation();
        Test.stopTest();

        Assert.isFalse(controller.showApproveConfirm, 'Approve confirmation should be closed.');
        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should remain closed.');
        Assert.isFalse(controller.hasError, 'Valid approve confirmation flow should not show error.');
    }

    @IsTest
    static void testDoApproveUpdatesQuotation() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.showApproveConfirmation();
        controller.doApprove();
        Test.stopTest();

        Quotation__c updatedQuote = getQuotationById(quotationRecord.Id);

        Assert.isTrue(controller.approved, 'Controller should show approved state.');
        Assert.isFalse(controller.rejected, 'Rejected flag should be false after approval.');
        Assert.isFalse(controller.showApproveConfirm, 'Approve confirmation should be closed after save.');
        Assert.areEqual(true, updatedQuote.Manager_approval__c, 'Quotation should be manager approved.');
        Assert.areEqual(null, updatedQuote.Rejection_Reason__c, 'Approval should clear rejection reason.');
    }

    @IsTest
    static void testEnableAndCancelRejectMode() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.enableRejectMode();
        controller.rejectionReason = REJECTION_REASON;
        controller.cancelRejectMode();
        Test.stopTest();

        Assert.isFalse(controller.isRejecting, 'Reject mode should be disabled after cancel.');
        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should be closed after cancel.');
        Assert.areEqual('', controller.rejectionReason, 'Rejection reason should be cleared after cancel.');
        Assert.isFalse(controller.hasError, 'Cancel reject mode should clear errors.');
    }

    @IsTest
    static void testBackwardCompatibleDoRejectEnablesRejectMode() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.doReject();
        Test.stopTest();

        Assert.isTrue(controller.isRejecting, 'doReject should enable reject mode.');
        Assert.isFalse(controller.showApproveConfirm, 'Approve confirmation should be closed.');
        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should stay closed until reason is confirmed.');
    }

    @IsTest
    static void testShowRejectConfirmationWithoutReasonShowsError() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.enableRejectMode();
        controller.showRejectConfirmation();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Blank rejection reason should show error.');
        Assert.isNotNull(controller.errorMessage, 'Blank rejection reason should populate error message.');
        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should not open without reason.');
    }

    @IsTest
    static void testShowAndCloseRejectConfirmationWithReason() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();
        controller.rejectionReason = REJECTION_REASON;

        Test.startTest();
        controller.showRejectConfirmation();
        controller.closeRejectConfirmation();
        Test.stopTest();

        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should be closed.');
        Assert.isFalse(controller.showApproveConfirm, 'Approve confirmation should remain closed.');
        Assert.isFalse(controller.hasError, 'Valid rejection reason should clear error.');
    }

    @IsTest
    static void testDoConfirmRejectWithoutReasonShowsError() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.doConfirmReject();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Confirm reject without reason should show error.');
        Assert.isNotNull(controller.errorMessage, 'Confirm reject without reason should populate error message.');
        Assert.isFalse(controller.rejected, 'Rejected flag should remain false when reason is blank.');
    }

    @IsTest
    static void testDoConfirmRejectUpdatesQuotation() {
        Quotation__c quotationRecord = getQuotationByName(AVAILABLE_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();
        controller.rejectionReason = REJECTION_REASON;

        Test.startTest();
        controller.showRejectConfirmation();
        controller.doConfirmReject();
        Test.stopTest();

        Quotation__c updatedQuote = getQuotationById(quotationRecord.Id);

        Assert.isTrue(controller.rejected, 'Controller should show rejected state.');
        Assert.isFalse(controller.approved, 'Approved flag should be false after rejection.');
        Assert.isFalse(controller.showRejectConfirm, 'Reject confirmation should close after rejection.');
        Assert.areEqual(false, updatedQuote.Manager_approval__c, 'Manager approval should be false after rejection.');
        Assert.areEqual(REJECTION_REASON, updatedQuote.Rejection_Reason__c, 'Rejection reason should be saved.');
    }

    @IsTest
    static void testExistingApprovedQuotationShowsExpiredStateOnLoad() {
        Quotation__c quotationRecord = getQuotationByName(APPROVED_QUOTE_NAME);
        preparePageWithParameter(PARAM_ID, quotationRecord.Id);

        Test.startTest();
        PublicApprovalController controller = new PublicApprovalController();
        Test.stopTest();

        Assert.isTrue(controller.responseAlreadyRecorded, 'Approved quotation link should be expired.');
        Assert.isFalse(controller.approved, 'Approved flag should not be shown for expired link.');
        Assert.isFalse(controller.rejected, 'Rejected flag should not be shown for expired link.');
        Assert.isFalse(controller.hasError, 'Expired link state should not show system error.');
    }

    @IsTest
    static void testExistingRejectedQuotationBlocksNewResponse() {
        Quotation__c quotationRecord = getQuotationByName(REJECTED_QUOTE_NAME);
        preparePageWithParameter(PARAM_QUOTE_ID, quotationRecord.Id);

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.showApproveConfirmation();
        controller.enableRejectMode();
        controller.doApprove();
        Test.stopTest();

        Assert.isTrue(controller.responseAlreadyRecorded, 'Already rejected quotation should block new response.');
        Assert.isFalse(controller.showApproveConfirm, 'Approve confirmation should remain closed for expired link.');
        Assert.isFalse(controller.isRejecting, 'Reject mode should not stay enabled for expired link.');
        Assert.isFalse(controller.hasError, 'Expired link is a state, not an error.');
    }

    @IsTest
    static void testDoApproveWithoutQuotationIdShowsError() {
        prepareBlankPage();

        PublicApprovalController controller = new PublicApprovalController();

        Test.startTest();
        controller.doApprove();
        Test.stopTest();

        Assert.isTrue(controller.hasError, 'Approval without quotation Id should show error.');
        Assert.isNotNull(controller.errorMessage, 'Missing quotation Id should populate error message.');
        Assert.isFalse(controller.approved, 'Approval should not be completed without quotation Id.');
    }

    private static void prepareBlankPage() {
        Test.setCurrentPage(new PageReference('/apex/PublicApprovalControllerTestPage'));
    }

    private static void preparePageWithParameter(String parameterName, String parameterValue) {
        prepareBlankPage();
        ApexPages.currentPage().getParameters().put(parameterName, parameterValue);
    }

    private static Opportunity getOpportunityByName(String opportunityName) {
        return [
            SELECT Id
            FROM Opportunity
            WHERE Name = :opportunityName
            LIMIT 1
        ];
    }

    private static Quotation__c getQuotationByName(String quotationName) {
        return [
            SELECT Id, Manager_approval__c, Rejection_Reason__c
            FROM Quotation__c
            WHERE Name = :quotationName
            LIMIT 1
        ];
    }

    private static Quotation__c getQuotationById(Id quotationId) {
        return [
            SELECT Id, Manager_approval__c, Rejection_Reason__c
            FROM Quotation__c
            WHERE Id = :quotationId
            LIMIT 1
        ];
    }
}