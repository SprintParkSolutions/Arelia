/**
 * Backs the PaymentReceiptPdf Visualforce page used purely as a rendering
 * target for PageReference.getContentAsPDF() -- never loaded directly by an
 * end user in a browser.
 *
 * Reads all data from URL parameters rather than querying Payment_Term__c,
 * because the caller (ReceiptArtifactService.renderReceiptPdf) must render
 * this PDF *before* the record is actually updated to Paid -- getContentAsPDF
 * cannot be called once there's uncommitted DML pending in the transaction,
 * so rendering has to happen first, using data already in memory.
 */
public without sharing class PaymentReceiptPdfController {

    public Boolean hasReceipt { get; private set; }
    public String receiptNumber { get; private set; }
    public String projectName { get; private set; }
    public String customerName { get; private set; }
    public String installmentLabel { get; private set; }
    public String paymentDate { get; private set; }
    public String status { get; private set; }
    public String currencyCode { get; private set; }
    public String amount { get; private set; }
    public String razorpayOrderId { get; private set; }
    public String razorpayPaymentId { get; private set; }

    public PaymentReceiptPdfController() {
        Map<String, String> params = ApexPages.currentPage().getParameters();

        projectName = params.get('project');
        customerName = params.get('customer');
        installmentLabel = params.get('installment');
        amount = params.get('amount');
        currencyCode = params.get('currency');
        paymentDate = params.get('paymentDate');
        status = params.get('status');
        razorpayOrderId = params.get('orderId');
        razorpayPaymentId = params.get('paymentId');
        receiptNumber = String.isNotBlank(razorpayPaymentId) ? razorpayPaymentId : params.get('id');

        hasReceipt = String.isNotBlank(installmentLabel);
    }
}