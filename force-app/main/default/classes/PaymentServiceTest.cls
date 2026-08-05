/**
 * @description Unit tests for PaymentService, covering the Razorpay payment
 * term lifecycle: read/authorization, pending assertion, success/failed/refund
 * transitions, history, and receipt retrieval.
 */
@isTest
private class PaymentServiceTest {

    private static Contact testContact;
    private static Project__c testProject;
    private static Payment_Term__c testTerm;

    private static void setupData() {
        testContact = TestDataUtility.createContact('Payer', 'payer' + DateTime.now().getTime() + '@example.com', 'Test@1234');
        testProject = TestDataUtility.createProject('Test Project', 1000000, testContact.Id);
        testTerm = TestDataUtility.createPaymentTerm(testProject.Id, 'Installment 1', 25);
    }

    @isTest
    static void testGetPayableTermReturnsCorrectDetail() {
        setupData();

        Test.startTest();
        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(testTerm.Id, testContact.Id);
        Test.stopTest();

        System.assertEquals(testProject.Name, detail.projectName);
        System.assertEquals(250000, detail.amount);
        System.assertEquals('Pending', detail.status);
        System.assertEquals(testTerm.Id, detail.paymentTermId);
    }

    @isTest
    static void testGetPayableTermNullIdThrows() {
        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(null, null);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals('A payment term is required.', pe.getMessage());
        }
        System.assert(caught);
    }

    @isTest
    static void testGetPayableTermNotFoundThrows() {
        setupData();
        Id deletedId = testTerm.Id;
        delete testTerm;

        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(deletedId, testContact.Id);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals('Payment term not found.', pe.getMessage());
        }
        System.assert(caught);
    }

    @isTest
    static void testGetPayableTermUnauthorizedContactThrows() {
        setupData();
        Contact otherContact = TestDataUtility.createContact('Other', 'other' + DateTime.now().getTime() + '@example.com', 'Test@1234');

        Boolean caught = false;
        try {
            PaymentService.getPayableTerm(testTerm.Id, otherContact.Id);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals('You are not authorized to view this payment term.', pe.getMessage());
        }
        System.assert(caught);
    }

    @isTest
    static void testAssertPendingWithValidDetailDoesNotThrow() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Pending';
        detail.amount = 100;

        Boolean caught = false;
        try {
            PaymentService.assertPending(detail);
        } catch (PaymentException pe) {
            caught = true;
        }
        System.assertEquals(false, caught);
    }

    @isTest
    static void testAssertPendingAlreadyPaidThrows() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Paid';
        detail.amount = 100;

        Boolean caught = false;
        try {
            PaymentService.assertPending(detail);
        } catch (PaymentException pe) {
            caught = true;
        }
        System.assert(caught);
    }

    @isTest
    static void testAssertPendingNullAmountThrows() {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.status = 'Pending';
        detail.amount = null;

        Boolean caught = false;
        try {
            PaymentService.assertPending(detail);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals(
                'The payment amount for this installment could not be determined. Please contact support.',
                pe.getMessage()
            );
        }
        System.assert(caught);
    }

    @isTest
    static void testMarkPaymentSuccessUpdatesRecord() {
        setupData();

        Test.startTest();
        PaymentService.markPaymentSuccess(testTerm.Id, 'order_abc', 'pay_abc', 'sig_abc', 250000);
        Test.stopTest();

        Payment_Term__c updated = [
            SELECT Transaction_Status__c, Payment_Received__c, Razorpay_Order_Id__c, Razorpay_Payment_Id__c,
                   Razorpay_Signature__c, Payment_Date__c, Description__c
            FROM Payment_Term__c
            WHERE Id = :testTerm.Id
        ];

        System.assertEquals('Paid', updated.Transaction_Status__c);
        System.assertEquals(true, updated.Payment_Received__c);
        System.assertEquals('order_abc', updated.Razorpay_Order_Id__c);
        System.assertEquals('pay_abc', updated.Razorpay_Payment_Id__c);
        System.assertEquals('sig_abc', updated.Razorpay_Signature__c);
        System.assertNotEquals(null, updated.Payment_Date__c);
        System.assert(updated.Description__c.contains('pay_abc'));
    }

    @isTest
    static void testMarkPaymentSuccessAlreadyPaidIsNoOp() {
        setupData();
        testTerm.Transaction_Status__c = 'Paid';
        update testTerm;

        Test.startTest();
        PaymentService.markPaymentSuccess(testTerm.Id, 'order_new', 'pay_new', 'sig_new', 250000);
        Test.stopTest();

        Payment_Term__c updated = [SELECT Razorpay_Order_Id__c FROM Payment_Term__c WHERE Id = :testTerm.Id];
        System.assertEquals(null, updated.Razorpay_Order_Id__c);
    }

    @isTest
    static void testMarkPaymentSuccessNotFoundThrows() {
        setupData();
        Id deletedId = testTerm.Id;
        delete testTerm;

        Boolean caught = false;
        try {
            PaymentService.markPaymentSuccess(deletedId, 'order', 'pay', 'sig', 100);
        } catch (PaymentException pe) {
            caught = true;
        }
        System.assert(caught);
    }

    @isTest
    static void testSaveOfflinePaymentDetailsUpdatesRecord() {
        setupData();

        Test.startTest();
        PaymentService.saveOfflinePaymentDetails(testTerm.Id, testContact.Id, 'Will pay by cheque at the site office.');
        Test.stopTest();

        Payment_Term__c updated = [
            SELECT Payment_Mode__c, Offline_Payment_Description__c, Transaction_Status__c
            FROM Payment_Term__c
            WHERE Id = :testTerm.Id
        ];
        System.assertEquals('Offline', updated.Payment_Mode__c);
        System.assertEquals('Will pay by cheque at the site office.', updated.Offline_Payment_Description__c);
        System.assertNotEquals('Paid', updated.Transaction_Status__c);
    }

    @isTest
    static void testSaveOfflinePaymentDetailsBlankDescriptionThrows() {
        setupData();

        Boolean caught = false;
        try {
            PaymentService.saveOfflinePaymentDetails(testTerm.Id, testContact.Id, '   ');
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals('Please describe how you will complete this payment offline.', pe.getMessage());
        }
        System.assert(caught);
    }

    @isTest
    static void testSaveOfflinePaymentDetailsAlreadyPaidThrows() {
        setupData();
        testTerm.Transaction_Status__c = 'Paid';
        update testTerm;

        Boolean caught = false;
        try {
            PaymentService.saveOfflinePaymentDetails(testTerm.Id, testContact.Id, 'Cash payment planned.');
        } catch (PaymentException pe) {
            caught = true;
        }
        System.assert(caught);
    }

    @isTest
    static void testMarkPaymentFailedUpdatesStatus() {
        setupData();

        PaymentService.markPaymentFailed(testTerm.Id, 'order_failed');

        Payment_Term__c updated = [SELECT Transaction_Status__c, Razorpay_Order_Id__c FROM Payment_Term__c WHERE Id = :testTerm.Id];
        System.assertEquals('Failed', updated.Transaction_Status__c);
        System.assertEquals('order_failed', updated.Razorpay_Order_Id__c);
    }

    @isTest
    static void testMarkPaymentRefundedUpdatesStatus() {
        setupData();
        testTerm.Razorpay_Order_Id__c = 'order_refund';
        update testTerm;

        PaymentService.markPaymentRefunded('order_refund');

        Payment_Term__c updated = [SELECT Transaction_Status__c FROM Payment_Term__c WHERE Id = :testTerm.Id];
        System.assertEquals('Refunded', updated.Transaction_Status__c);
    }

    @isTest
    static void testMarkPaymentRefundedNoMatchIsNoOp() {
        setupData();

        Test.startTest();
        PaymentService.markPaymentRefunded('nonexistent_order_id');
        Test.stopTest();

        Payment_Term__c unchanged = [SELECT Transaction_Status__c FROM Payment_Term__c WHERE Id = :testTerm.Id];
        System.assertNotEquals('Refunded', unchanged.Transaction_Status__c);
    }

    @isTest
    static void testGetPaymentHistoryNullContactThrows() {
        Boolean caught = false;
        try {
            PaymentService.getPaymentHistory(null);
        } catch (PaymentException pe) {
            caught = true;
        }
        System.assert(caught);
    }

    @isTest
    static void testGetPaymentHistoryReturnsItemsOrderedByDueDate() {
        setupData();
        Payment_Term__c secondTerm = TestDataUtility.createPaymentTerm(testProject.Id, 'Installment 2', 25);
        secondTerm.Due_Date__c = testTerm.Due_Date__c.addDays(30);
        update secondTerm;

        List<PaymentService.PaymentHistoryItem> history = PaymentService.getPaymentHistory(testContact.Id);

        System.assertEquals(2, history.size());
        System.assertEquals(testTerm.Id, history[0].paymentTermId);
        System.assertEquals(secondTerm.Id, history[1].paymentTermId);
    }

    @isTest
    static void testGetPayableTermUsesLegacyPaymentReceivedFallback() {
        setupData();
        testTerm.Payment_Received__c = true;
        update testTerm;

        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(testTerm.Id, testContact.Id);
        System.assertEquals('Paid', detail.status);
    }

    @isTest
    static void testGetReceiptReturnsDataForPaidTerm() {
        setupData();
        PaymentService.markPaymentSuccess(testTerm.Id, 'order_receipt', 'pay_receipt', 'sig_receipt', 250000);

        PaymentService.ReceiptData receipt = PaymentService.getReceipt(testTerm.Id, testContact.Id);

        System.assertEquals('pay_receipt', receipt.receiptNumber);
        System.assertEquals('Paid', receipt.status);
        System.assertEquals('INR', receipt.currencyCode);
        System.assertEquals(250000, receipt.amount);
    }

    @isTest
    static void testGetReceiptNotPaidThrows() {
        setupData();

        Boolean caught = false;
        try {
            PaymentService.getReceipt(testTerm.Id, testContact.Id);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals('No receipt is available until this installment is paid.', pe.getMessage());
        }
        System.assert(caught);
    }
}