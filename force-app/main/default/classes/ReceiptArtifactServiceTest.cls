@isTest
private class ReceiptArtifactServiceTest {

    private static Payment_Term__c createTestPaymentTerm() {
        Contact payer = TestDataUtility.createContact(
            'ReceiptPayer',
            'receiptpayer' + DateTime.now().getTime() + '@example.com',
            'Test@1234'
        );
        Project__c project = TestDataUtility.createProject('Receipt Test Project', 100000, payer.Id);
        return TestDataUtility.createPaymentTerm(project.Id, 'Installment 1', 25);
    }

    private static PaymentService.PaymentTermDetail buildDetail(Payment_Term__c term) {
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.paymentTermId = term.Id;
        detail.projectName = 'Receipt Test Project';
        detail.customerName = 'Receipt Customer';
        detail.customerEmail = 'customer@example.com';
        detail.customerPhone = '9999999999';
        detail.installmentLabel = 'Installment 1';
        detail.percentage = 25;
        detail.amount = 25000;
        detail.totalAmount = 100000;
        detail.dueDate = Date.today().addDays(15).format();
        detail.status = 'Pending';
        detail.razorpayOrderId = 'order_123';
        detail.razorpayPaymentId = 'pay_456';
        detail.paymentDate = Datetime.now().format();
        return detail;
    }

    @isTest
    static void testRenderReceiptPdfReturnsBlobInTestContext() {
        Payment_Term__c term = createTestPaymentTerm();
        PaymentService.PaymentTermDetail detail = buildDetail(term);

        Blob pdfBlob = ReceiptArtifactService.renderReceiptPdf(detail, 'order_123', 'pay_456');

        System.assertNotEquals(null, pdfBlob, 'renderReceiptPdf should return a Blob during test execution');
        System.assert(pdfBlob.size() > 0, 'Rendered PDF blob must contain data');
    }

    @isTest
    static void testAttachReceiptArtifactsCreatesContentVersionNoteAndLink() {
        Payment_Term__c term = createTestPaymentTerm();
        PaymentService.PaymentTermDetail detail = buildDetail(term);
        Blob pdfBlob = Blob.valueOf('Test receipt PDF content');

        Test.startTest();
        ReceiptArtifactService.attachReceiptArtifacts(term.Id, detail, 'order_123', 'pay_456', pdfBlob);
        Test.stopTest();

        ContentVersion version = [SELECT Id, Title, PathOnClient, FirstPublishLocationId
                                  FROM ContentVersion
                                  WHERE PathOnClient = 'Receipt-pay_456.pdf'
                                  LIMIT 1];
        System.assertEquals('Receipt-pay_456.pdf', version.Title);
        System.assertEquals(term.Id, version.FirstPublishLocationId);

        ContentNote note = [SELECT Id, Title, Content
                            FROM ContentNote
                            WHERE Title = 'Payment Receipt - Installment 1'
                            LIMIT 1];
        System.assertEquals('Payment Receipt - Installment 1', note.Title);
        System.assertNotEquals(null, note.Content);

        ContentDocumentLink link = [SELECT Id, ContentDocumentId, LinkedEntityId, ShareType
                                    FROM ContentDocumentLink
                                    WHERE LinkedEntityId = :term.Id
                                      AND ContentDocumentId = :note.Id
                                    LIMIT 1];
        System.assertEquals('V', link.ShareType);
        System.assertEquals(term.Id, link.LinkedEntityId);
    }

    @isTest
    static void testAttachReceiptArtifactsUsesTermIdWhenPaymentIdIsBlank() {
        Payment_Term__c term = createTestPaymentTerm();
        PaymentService.PaymentTermDetail detail = buildDetail(term);
        Blob pdfBlob = Blob.valueOf('Alternate receipt PDF content');

        Test.startTest();
        ReceiptArtifactService.attachReceiptArtifacts(term.Id, detail, 'order_123', '', pdfBlob);
        Test.stopTest();

        String expectedFileName = 'Receipt-' + String.valueOf(term.Id) + '.pdf';
        ContentVersion version = [SELECT Id, Title, PathOnClient FROM ContentVersion WHERE PathOnClient = :expectedFileName LIMIT 1];
        System.assertEquals(expectedFileName, version.Title);
    }
}