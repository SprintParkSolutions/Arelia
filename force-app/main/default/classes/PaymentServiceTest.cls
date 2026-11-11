/**
 * @description Unit tests for PaymentService's payment schedule, ownership,
 *              order snapshots, payment lifecycle, history and receipts.
 */
@IsTest(SeeAllData=false)
@SuppressWarnings('PMD.TooManyMethods')
private class PaymentServiceTest {
    private static final String PAYER_EMAIL = 'payer@example.com';
    private static final String PROJECT_NAME = 'Test Project';
    private static final String TERM_NAME = 'Installment 1';
    private static final String ORDER_ID = 'order_abc';
    private static final String PAYMENT_ID = 'pay_abc';
    private static final String SIGNATURE = 'sig_abc';
    private static final String OFFLINE_DESCRIPTION = 'Will pay by cheque at the site office.';
    private static final Decimal PROJECT_BUDGET = 1000000;
    private static final Decimal TERM_PERCENTAGE = 25;

    private class TestRecords {
        public Contact contactRecord;
        public Project__c projectRecord;
        public Payment_Term__c termRecord;
    }

    /** @description Creates independent test data for one test method.
     *  @return Test records. */
    private static TestRecords createRecords() {
        TestRecords records = new TestRecords();
        records.contactRecord = TestDataUtility.createContact(
            'Payer', PAYER_EMAIL, 'Test@1234'
        );
        records.projectRecord = TestDataUtility.createProject(
            PROJECT_NAME, PROJECT_BUDGET, records.contactRecord.Id
        );
        records.termRecord = TestDataUtility.createPaymentTerm(
            records.projectRecord.Id, TERM_NAME, TERM_PERCENTAGE
        );
        return records;
    }

    /** @description Returns a fresh Payment Term with payment fields.
     *  @param termId Payment Term Id.
     *  @return Persisted term. */
    private static Payment_Term__c queryTerm(Id termId) {
        return [
            SELECT Id, Transaction_Status__c, Payment_Received__c,
                   Paid_Amount__c, Order_Amount__c, Payment_Date__c,
                   Razorpay_Order_Id__c, Razorpay_Payment_Id__c,
                   Razorpay_Signature__c, Description__c,
                   Payment_Mode__c, Offline_Payment_Description__c
            FROM Payment_Term__c
            WHERE Id = :termId
            LIMIT 1
        ];
    }

    /** @description Records the order amount allocated by PaymentService.
     *  @param termId Payment Term Id.
     *  @param contactId Owner Contact Id.
     *  @param orderId Order Id.
     *  @return Recorded order amount. */
    private static Decimal prepareOrder(Id termId, Id contactId, String orderId) {
        PaymentService.PaymentTermDetail detail =
            PaymentService.getPayableTerm(termId, contactId);
        PaymentService.assertPending(detail);
        PaymentService.recordPaymentOrder(termId, orderId, detail.amount);
        return detail.amount;
    }

    /** @description Pays the recorded order with matching identifiers.
     *  @param termId Payment Term Id.
     *  @param contactId Contact Id.
     *  @return Payment amount recorded for the order. */
    private static Decimal completePayment(Id termId, Id contactId) {
        Decimal amount = prepareOrder(termId, contactId, ORDER_ID);
        Boolean newlyPaid = PaymentService.markPaymentSuccess(
            termId, ORDER_ID, PAYMENT_ID, SIGNATURE, amount
        );
        System.assertEquals(true, newlyPaid, 'The initial payment must settle.');
        return amount;
    }

    /** @description Asserts an error message is present.
     *  @param message Error message. */
    private static void assertErrorMessage(String message) {
        System.assert(String.isNotBlank(message), 'A payment error must be provided.');
    }

    @IsTest
    static void testGetPayableTermReturnsCorrectDetail() {
        TestRecords records = createRecords();
        Test.startTest();
        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(
            records.termRecord.Id, records.contactRecord.Id
        );
        Test.stopTest();
        System.assertEquals(records.projectRecord.Name, detail.projectName);
        System.assertEquals(PROJECT_BUDGET, detail.amount,
            'A single scheduled term receives the project-wide allocation.');
        System.assertEquals(PROJECT_BUDGET, detail.totalAmount);
        System.assertEquals('Pending', detail.status);
        System.assertEquals(records.termRecord.Id, detail.paymentTermId);
        System.assertEquals(TERM_PERCENTAGE, detail.percentage);
    }

    @IsTest
    static void testGetPayableTermNullIdThrows() {
        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(null, null);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals('A payment term is required.', exceptionRecord.getMessage());
        }
        System.assertEquals(true, caught, 'Null Payment Term Id must be rejected.');
    }

    @IsTest
    static void testGetPayableTermNotFoundThrows() {
        TestRecords records = createRecords();
        Id deletedId = records.termRecord.Id;
        delete records.termRecord;
        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(deletedId, records.contactRecord.Id);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals('Payment term not found.', exceptionRecord.getMessage());
        }
        System.assertEquals(true, caught, 'Deleted terms must not be returned.');
    }

    @IsTest
    static void testGetPayableTermUnauthorizedContactThrows() {
        TestRecords records = createRecords();
        Contact otherContact = TestDataUtility.createContact(
            'Other', 'other@example.com', 'Test@1234'
        );
        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(records.termRecord.Id, otherContact.Id);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'You are not authorized to view this payment term.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Unrelated contacts must not access terms.');
    }

    @IsTest
    static void testAssertPendingWithValidDetailDoesNotThrow() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Pending';
        detail.amount = 100;
        PaymentService.assertPending(detail);
        System.assertEquals('Pending', detail.status);
    }

    @IsTest
    static void testAssertPendingAlreadyPaidThrows() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Paid';
        detail.amount = 100;
        Boolean caught = false;
        try {
            PaymentService.assertPending(detail);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'This installment has already been paid or is not currently payable.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Paid terms must be rejected.');
    }

    @IsTest
    static void testAssertPendingNullAmountThrows() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Pending';
        detail.amount = null;
        Boolean caught = false;
        try {
            PaymentService.assertPending(detail);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'The payment amount could not be determined. Please contact support to reconcile the payment schedule.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Missing amounts must be rejected.');
    }

    @IsTest
    static void testMarkPaymentSuccessUpdatesRecord() {
        TestRecords records = createRecords();
        Decimal capturedAmount = prepareOrder(
            records.termRecord.Id, records.contactRecord.Id, ORDER_ID
        );
        Test.startTest();
        Boolean newlyPaid = PaymentService.markPaymentSuccess(
            records.termRecord.Id, ORDER_ID, PAYMENT_ID, SIGNATURE, capturedAmount
        );
        Test.stopTest();
        Payment_Term__c updated = queryTerm(records.termRecord.Id);
        System.assertEquals(true, newlyPaid);
        System.assertEquals('Paid', updated.Transaction_Status__c);
        System.assertEquals(true, updated.Payment_Received__c);
        System.assertEquals(capturedAmount, updated.Paid_Amount__c);
        System.assertEquals(capturedAmount, updated.Order_Amount__c);
        System.assertEquals(ORDER_ID, updated.Razorpay_Order_Id__c);
        System.assertEquals(PAYMENT_ID, updated.Razorpay_Payment_Id__c);
        System.assertEquals(SIGNATURE, updated.Razorpay_Signature__c);
        System.assertNotEquals(null, updated.Payment_Date__c);
        System.assert(updated.Description__c.contains(PAYMENT_ID));
    }

    @IsTest
    static void testMarkPaymentSuccessAlreadyPaidIsNoOp() {
        TestRecords records = createRecords();
        Decimal capturedAmount = completePayment(
            records.termRecord.Id, records.contactRecord.Id
        );
        Test.startTest();
        Boolean newlyPaid = PaymentService.markPaymentSuccess(
            records.termRecord.Id, ORDER_ID, PAYMENT_ID, SIGNATURE, capturedAmount
        );
        Test.stopTest();
        Payment_Term__c updated = queryTerm(records.termRecord.Id);
        System.assertEquals(false, newlyPaid, 'Identical retries must be idempotent.');
        System.assertEquals(ORDER_ID, updated.Razorpay_Order_Id__c);
        System.assertEquals(PAYMENT_ID, updated.Razorpay_Payment_Id__c);
        System.assertEquals(capturedAmount, updated.Paid_Amount__c);
    }

    @IsTest
    static void testMarkPaymentSuccessDifferentPaymentThrows() {
        TestRecords records = createRecords();
        Decimal capturedAmount = completePayment(
            records.termRecord.Id, records.contactRecord.Id
        );
        Boolean caught = false;
        try {
            PaymentService.markPaymentSuccess(
                records.termRecord.Id, ORDER_ID, 'pay_different', SIGNATURE, capturedAmount
            );
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'A different payment has already settled this installment.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Different payment IDs must be rejected.');
    }

    @IsTest
    static void testMarkPaymentSuccessNotFoundThrows() {
        TestRecords records = createRecords();
        Id deletedId = records.termRecord.Id;
        delete records.termRecord;
        Boolean caught = false;
        try {
            PaymentService.markPaymentSuccess(deletedId, ORDER_ID, PAYMENT_ID, SIGNATURE, 100);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals('Payment term not found.', exceptionRecord.getMessage());
        }
        System.assertEquals(true, caught, 'Missing terms must not be settled.');
    }

    @IsTest
    static void testSaveOfflinePaymentDetailsUpdatesRecord() {
        TestRecords records = createRecords();
        Test.startTest();
        PaymentService.saveOfflinePaymentDetails(
            records.termRecord.Id, records.contactRecord.Id, OFFLINE_DESCRIPTION
        );
        Test.stopTest();
        Payment_Term__c updated = queryTerm(records.termRecord.Id);
        System.assertEquals('Offline', updated.Payment_Mode__c);
        System.assertEquals(OFFLINE_DESCRIPTION, updated.Offline_Payment_Description__c);
        System.assertNotEquals('Paid', updated.Transaction_Status__c);
    }

    @IsTest
    static void testSaveOfflinePaymentDetailsBlankDescriptionThrows() {
        TestRecords records = createRecords();
        Boolean caught = false;
        try {
            PaymentService.saveOfflinePaymentDetails(
                records.termRecord.Id, records.contactRecord.Id, '   '
            );
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'Please describe how you will complete this payment offline.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Blank descriptions must be rejected.');
    }

    @IsTest
    static void testSaveOfflinePaymentDetailsAlreadyPaidThrows() {
        TestRecords records = createRecords();
        completePayment(records.termRecord.Id, records.contactRecord.Id);
        Boolean caught = false;
        try {
            PaymentService.saveOfflinePaymentDetails(
                records.termRecord.Id, records.contactRecord.Id, 'Cash payment planned.'
            );
        } catch (PaymentException exceptionRecord) {
            caught = true;
            assertErrorMessage(exceptionRecord.getMessage());
        }
        System.assertEquals(true, caught, 'Paid installments cannot change to offline.');
    }

    @IsTest
    static void testMarkPaymentFailedUpdatesStatus() {
        TestRecords records = createRecords();
        prepareOrder(records.termRecord.Id, records.contactRecord.Id, ORDER_ID);
        Test.startTest();
        PaymentService.markPaymentFailed(records.termRecord.Id, ORDER_ID);
        Test.stopTest();
        Payment_Term__c updated = queryTerm(records.termRecord.Id);
        System.assertEquals('Failed', updated.Transaction_Status__c);
        System.assertEquals(ORDER_ID, updated.Razorpay_Order_Id__c);
    }

    @IsTest
    static void testMarkPaymentFailedDoesNotOverwritePaid() {
        TestRecords records = createRecords();
        completePayment(records.termRecord.Id, records.contactRecord.Id);
        PaymentService.markPaymentFailed(records.termRecord.Id, ORDER_ID);
        System.assertEquals('Paid', queryTerm(records.termRecord.Id).Transaction_Status__c);
    }

    @IsTest
    static void testMarkPaymentFailedWrongOrderIsNoOp() {
        TestRecords records = createRecords();
        prepareOrder(records.termRecord.Id, records.contactRecord.Id, ORDER_ID);
        PaymentService.markPaymentFailed(records.termRecord.Id, 'order_wrong');
        Payment_Term__c updated = queryTerm(records.termRecord.Id);
        System.assertNotEquals('Failed', updated.Transaction_Status__c);
        System.assertEquals(ORDER_ID, updated.Razorpay_Order_Id__c);
    }

    @IsTest
    static void testMarkPaymentRefundedUpdatesStatus() {
        TestRecords records = createRecords();
        completePayment(records.termRecord.Id, records.contactRecord.Id);
        Test.startTest();
        PaymentService.markPaymentRefunded(ORDER_ID);
        Test.stopTest();
        System.assertEquals(
            'Refunded', queryTerm(records.termRecord.Id).Transaction_Status__c
        );
    }

    @IsTest
    static void testMarkPaymentRefundedNoMatchIsNoOp() {
        TestRecords records = createRecords();
        Test.startTest();
        PaymentService.markPaymentRefunded('nonexistent_order_id');
        Test.stopTest();
        System.assertNotEquals(
            'Refunded', queryTerm(records.termRecord.Id).Transaction_Status__c
        );
    }

    @IsTest
    static void testGetPaymentHistoryNullContactThrows() {
        Boolean caught = false;
        try {
            PaymentService.getPaymentHistory(null);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals('A contact is required.', exceptionRecord.getMessage());
        }
        System.assertEquals(true, caught, 'Null Contact Id must be rejected.');
    }

    @IsTest
    static void testGetPaymentHistoryReturnsItemsOrderedByDueDate() {
        TestRecords records = createRecords();
        Payment_Term__c secondTerm = TestDataUtility.createPaymentTerm(
            records.projectRecord.Id, 'Installment 2', TERM_PERCENTAGE
        );
        secondTerm.Due_Date__c = records.termRecord.Due_Date__c.addDays(30);
        update secondTerm;
        Test.startTest();
        List<PaymentService.PaymentHistoryItem> history =
            PaymentService.getPaymentHistory(records.contactRecord.Id);
        Test.stopTest();
        System.assertEquals(2, history.size());
        System.assertEquals(records.termRecord.Id, history[0].paymentTermId);
        System.assertEquals(secondTerm.Id, history[1].paymentTermId);
        System.assertEquals(PROJECT_BUDGET, history[0].amount + history[1].amount,
            'Schedule allocations should add up to the project budget.');
    }

    @IsTest
    static void testGetPayableTermUsesLegacyPaymentReceivedFallback() {
        TestRecords records = createRecords();
        // The legacy status fallback applies only when Transaction_Status__c is blank.
        update new Payment_Term__c(
            Id = records.termRecord.Id,
            Transaction_Status__c = null,
            Payment_Received__c = true,
            Paid_Amount__c = PROJECT_BUDGET
        );
        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(
            records.termRecord.Id, records.contactRecord.Id
        );
        System.assertEquals('Paid', detail.status);
    }

    @IsTest
    static void testGetReceiptReturnsDataForPaidTerm() {
        TestRecords records = createRecords();
        Decimal paidAmount = completePayment(
            records.termRecord.Id, records.contactRecord.Id
        );
        Test.startTest();
        PaymentService.ReceiptData receipt = PaymentService.getReceipt(
            records.termRecord.Id, records.contactRecord.Id
        );
        Test.stopTest();
        System.assertEquals(PAYMENT_ID, receipt.receiptNumber);
        System.assertEquals('Paid', receipt.status);
        System.assertEquals('INR', receipt.currencyCode);
        System.assertEquals(paidAmount, receipt.amount);
        System.assertEquals(ORDER_ID, receipt.razorpayOrderId);
        System.assertEquals(PAYMENT_ID, receipt.razorpayPaymentId);
    }

    @IsTest
    static void testGetReceiptNotPaidThrows() {
        TestRecords records = createRecords();
        Boolean caught = false;
        try {
            PaymentService.getReceipt(records.termRecord.Id, records.contactRecord.Id);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'No receipt is available until this installment is paid.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Pending terms must not have receipts.');
    }

    @IsTest
    static void testRecordPaymentOrderStoresOriginalAmount() {
        TestRecords records = createRecords();
        Decimal allocatedAmount = prepareOrder(
            records.termRecord.Id, records.contactRecord.Id, ORDER_ID
        );
        Payment_Term__c stored = queryTerm(records.termRecord.Id);
        System.assertEquals(ORDER_ID, stored.Razorpay_Order_Id__c);
        System.assertEquals(allocatedAmount, stored.Order_Amount__c);
        PaymentService.PaymentTermDetail detail =
            PaymentService.getPaymentVerificationDetail(
                records.termRecord.Id, records.contactRecord.Id, ORDER_ID
            );
        System.assertEquals(allocatedAmount, detail.amount,
            'Verification uses the stored order amount.');
    }

    @IsTest
    static void testRecordPaymentOrderDifferentOrderThrows() {
        TestRecords records = createRecords();
        Decimal amount = prepareOrder(
            records.termRecord.Id, records.contactRecord.Id, ORDER_ID
        );
        Boolean caught = false;
        try {
            PaymentService.recordPaymentOrder(records.termRecord.Id, 'order_other', amount);
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'Another payment order already exists for this installment. Please try again.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'A different open order must be rejected.');
    }

    @IsTest
    static void testGetPaymentVerificationDetailWrongOrderThrows() {
        TestRecords records = createRecords();
        prepareOrder(records.termRecord.Id, records.contactRecord.Id, ORDER_ID);
        Boolean caught = false;
        try {
            PaymentService.getPaymentVerificationDetail(
                records.termRecord.Id, records.contactRecord.Id, 'order_wrong'
            );
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'The original payment order amount is unavailable. Please contact support to reconcile this payment.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Unknown orders must not be verified.');
    }

    @IsTest
    static void testPaymentVerificationUsesOriginalAmountAfterBudgetChange() {
        TestRecords records = createRecords();
        Decimal originalAmount = prepareOrder(
            records.termRecord.Id, records.contactRecord.Id, ORDER_ID
        );
        update new Project__c(
            Id = records.projectRecord.Id,
            Supervisor_Estimated_Budget__c = PROJECT_BUDGET + 50000
        );
        PaymentService.PaymentTermDetail detail =
            PaymentService.getPaymentVerificationDetail(
                records.termRecord.Id, records.contactRecord.Id, ORDER_ID
            );
        System.assertEquals(originalAmount, detail.amount,
            'Verification must use the recorded amount, not the changed budget.');
    }

    @IsTest
    static void testMarkPaymentSuccessRequiresOriginalOrder() {
        TestRecords records = createRecords();
        Boolean caught = false;
        try {
            PaymentService.markPaymentSuccess(
                records.termRecord.Id, ORDER_ID, PAYMENT_ID, SIGNATURE, PROJECT_BUDGET
            );
        } catch (PaymentException exceptionRecord) {
            caught = true;
            System.assertEquals(
                'The original payment order amount is unavailable. Please contact support to reconcile this payment.',
                exceptionRecord.getMessage()
            );
        }
        System.assertEquals(true, caught, 'Successful payment requires a stored order.');
    }
}