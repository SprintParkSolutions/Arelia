/**
 * Generates and attaches receipt artifacts to Payment_Term__c: a rendered
 * PDF (via the PaymentReceiptPdf Visualforce page) saved as a File on the
 * record, and a Note summarizing the payment.
 *
 * Split into two calls (renderReceiptPdf, then attachReceiptArtifacts) that
 * the caller must run either side of PaymentService.markPaymentSuccess:
 * PageReference.getContentAsPDF() cannot be called once there's uncommitted
 * DML pending in the transaction, so the PDF has to be rendered from
 * in-memory data *before* the success DML runs, not after. It also cannot be
 * called from @future or Queueable contexts at all, so this must run inline
 * in the same synchronous request as the rest of the verify/webhook flow.
 */
public without sharing class ReceiptArtifactService {

    public static Blob renderReceiptPdf(PaymentService.PaymentTermDetail detail, String razorpayOrderId, String razorpayPaymentId) {
        if (Test.isRunningTest()) {
            return Blob.valueOf('Test receipt PDF content');
        }

        PageReference pdfPage = Page.PaymentReceiptPdf;
        Map<String, String> params = pdfPage.getParameters();
        params.put('project', detail.projectName);
        params.put('customer', detail.customerName);
        params.put('installment', detail.installmentLabel);
        params.put('amount', detail.amount != null ? String.valueOf(detail.amount) : '');
        params.put('currency', 'INR');
        params.put('paymentDate', Datetime.now().format());
        params.put('status', 'Paid');
        params.put('orderId', razorpayOrderId);
        params.put('paymentId', razorpayPaymentId);
        return pdfPage.getContentAsPDF();
    }

    public static void attachReceiptArtifacts(
        Id paymentTermId,
        PaymentService.PaymentTermDetail detail,
        String razorpayOrderId,
        String razorpayPaymentId,
        Blob pdfBlob
    ) {
        try {
            String receiptNumber = String.isNotBlank(razorpayPaymentId) ? razorpayPaymentId : String.valueOf(paymentTermId);
            String fileName = 'Receipt-' + receiptNumber + '.pdf';

            ContentVersion cv = new ContentVersion(
                Title = fileName,
                PathOnClient = fileName,
                VersionData = pdfBlob,
                FirstPublishLocationId = paymentTermId
            );
            insert cv;

            ContentNote note = new ContentNote(
                Title = 'Payment Receipt - ' + detail.installmentLabel,
                Content = Blob.valueOf(buildNoteBody(detail, receiptNumber, razorpayOrderId, razorpayPaymentId))
            );
            insert note;

            // A ContentNote's own Id doubles as its ContentDocument Id.
            insert new ContentDocumentLink(
                ContentDocumentId = note.Id,
                LinkedEntityId = paymentTermId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not attach receipt artifacts for ' + paymentTermId + ': ' + ex.getMessage());
        }
    }

    private static String buildNoteBody(PaymentService.PaymentTermDetail detail, String receiptNumber, String razorpayOrderId, String razorpayPaymentId) {
        return '<p><strong>Payment Receipt</strong></p><p>' +
            'Receipt / Transaction ID: ' + receiptNumber + '<br/>' +
            'Project: ' + detail.projectName + '<br/>' +
            'Customer: ' + detail.customerName + '<br/>' +
            'Installment: ' + detail.installmentLabel + '<br/>' +
            'Amount Paid: INR ' + detail.amount + '<br/>' +
            'Payment Date: ' + Datetime.now().format() + '<br/>' +
            'Razorpay Order ID: ' + razorpayOrderId + '<br/>' +
            'Razorpay Payment ID: ' + razorpayPaymentId + '<br/>' +
            'Status: Paid' +
            '</p>';
    }
}