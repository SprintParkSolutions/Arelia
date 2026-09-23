@isTest
private class PaymentReceiptPdfControllerTest {

    @isTest
    static void testControllerWithPaymentId() {
        PageReference page = Page.PaymentReceiptPdf;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('project','My Project');
        ApexPages.currentPage().getParameters().put('customer','John Doe');
        ApexPages.currentPage().getParameters().put('installment','Installment 1');
        ApexPages.currentPage().getParameters().put('amount','25000');
        ApexPages.currentPage().getParameters().put('currency','INR');
        ApexPages.currentPage().getParameters().put('paymentDate', Datetime.now().format());
        ApexPages.currentPage().getParameters().put('status','Paid');
        ApexPages.currentPage().getParameters().put('orderId','order_1');
        ApexPages.currentPage().getParameters().put('paymentId','pay_1');

        PaymentReceiptPdfController ctrl = new PaymentReceiptPdfController();

        System.assertEquals(true, ctrl.hasReceipt, 'Controller should indicate a receipt is present');
        System.assertEquals('pay_1', ctrl.receiptNumber, 'When paymentId is present it should be used as receiptNumber');
        System.assertEquals('My Project', ctrl.projectName);
        System.assertEquals('Installment 1', ctrl.installmentLabel);
        System.assertEquals('25000', ctrl.amount);
    }

    @isTest
    static void testControllerWithoutPaymentIdUsesIdParam() {
        PageReference page = Page.PaymentReceiptPdf;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('project','Proj2');
        ApexPages.currentPage().getParameters().put('customer','Jane');
        ApexPages.currentPage().getParameters().put('installment','Installment 2');
        ApexPages.currentPage().getParameters().put('amount','1000');
        ApexPages.currentPage().getParameters().put('currency','INR');
        ApexPages.currentPage().getParameters().put('paymentDate', Datetime.now().format());
        ApexPages.currentPage().getParameters().put('status','Paid');
        ApexPages.currentPage().getParameters().put('orderId','order_2');
        ApexPages.currentPage().getParameters().put('id','TERM123');

        PaymentReceiptPdfController ctrl = new PaymentReceiptPdfController();
        System.assertEquals(true, ctrl.hasReceipt);
        System.assertEquals('TERM123', ctrl.receiptNumber, 'When paymentId is blank the id param should be used');
    }

    @isTest
    static void testHasReceiptFalseWhenNoInstallment() {
        PageReference page = Page.PaymentReceiptPdf;
        Test.setCurrentPage(page);
        ApexPages.currentPage().getParameters().put('project','Proj3');
        ApexPages.currentPage().getParameters().put('customer','NoInstall');
        // no installment param provided

        PaymentReceiptPdfController ctrl = new PaymentReceiptPdfController();
        System.assertEquals(false, ctrl.hasReceipt);
    }
}