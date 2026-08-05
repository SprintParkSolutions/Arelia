/**
 * REST surface for the Razorpay payment flow, mirroring the existing guest-
 * accessible /services/apexrest/payment-terms convention used elsewhere in
 * this portal: no session/bearer auth, callers pass paymentTermId/contactId
 * explicitly and PaymentService enforces record-level ownership.
 *
 * Endpoints (dispatched off the request path suffix):
 *   GET  /services/apexrest/payment/details?paymentTermId=&contactId=
 *   GET  /services/apexrest/payment/history?contactId=
 *   GET  /services/apexrest/payment/receipt?paymentTermId=&contactId=
 *   POST /services/apexrest/payment/createOrder   { paymentTermId, contactId }
 *   POST /services/apexrest/payment/verify         { paymentTermId, razorpayOrderId,
 *                                                     razorpayPaymentId, razorpaySignature, contactId }
 *   POST /services/apexrest/payment/offline        { paymentTermId, contactId, description }
 */
@RestResource(urlMapping='/payment/*')
global without sharing class RazorpayController {

    global class CreateOrderRequest {
        public String paymentTermId;
        public String contactId;
    }

    global class VerifyRequest {
        public String paymentTermId;
        public String razorpayOrderId;
        public String razorpayPaymentId;
        public String razorpaySignature;
        public String contactId;
    }

    global class OfflinePaymentRequest {
        public String paymentTermId;
        public String contactId;
        public String description;
    }

    @HttpGet
    global static void handleGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String path = req.requestURI;

        try {
            if (path.endsWith('/details')) {
                handleDetails(req, res);
            } else if (path.endsWith('/history')) {
                handleHistory(req, res);
            } else if (path.endsWith('/receipt')) {
                handleReceipt(req, res);
            } else {
                writeError(res, 404, 'Unknown endpoint.');
            }
        } catch (PaymentException pe) {
            writeError(res, 400, pe.getMessage());
        } catch (Exception ex) {
            writeError(res, 500, 'Unexpected error: ' + ex.getMessage());
        }
    }

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String path = req.requestURI;

        try {
            if (path.endsWith('/createOrder')) {
                handleCreateOrder(req, res);
            } else if (path.endsWith('/verify')) {
                handleVerify(req, res);
            } else if (path.endsWith('/offline')) {
                handleOfflinePayment(req, res);
            } else {
                writeError(res, 404, 'Unknown endpoint.');
            }
        } catch (PaymentException pe) {
            writeError(res, 409, pe.getMessage());
        } catch (Exception ex) {
            writeError(res, 500, 'Unexpected error: ' + ex.getMessage());
        }
    }

    private static void handleDetails(RestRequest req, RestResponse res) {
        Id paymentTermId = getParamId(req, 'paymentTermId');
        Id contactId = getParamId(req, 'contactId');

        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(paymentTermId, contactId);

        writeSuccess(res, 200, new Map<String, Object>{
            'success' => true,
            'paymentTermId' => detail.paymentTermId,
            'projectName' => detail.projectName,
            'customerName' => detail.customerName,
            'customerEmail' => detail.customerEmail,
            'customerPhone' => detail.customerPhone,
            'installmentLabel' => detail.installmentLabel,
            'percentage' => detail.percentage,
            'amount' => detail.amount,
            'totalAmount' => detail.totalAmount,
            'dueDate' => detail.dueDate,
            'status' => detail.status
        });
    }

    private static void handleCreateOrder(RestRequest req, RestResponse res) {
        CreateOrderRequest payload = (CreateOrderRequest) JSON.deserialize(
            req.requestBody.toString(), CreateOrderRequest.class
        );
        Id paymentTermId = normalizeId(payload.paymentTermId);
        Id contactId = normalizeId(payload.contactId);

        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(paymentTermId, contactId);
        PaymentService.assertPending(detail);

        RazorpayService.RazorpayOrderResult orderResult = RazorpayService.createOrder(
            detail.amount, detail.paymentTermId, 'INR'
        );

        if (!orderResult.success) {
            writeError(res, 500, orderResult.errorMessage);
            return;
        }

        writeSuccess(res, 200, new Map<String, Object>{
            'success' => true,
            'orderId' => orderResult.orderId,
            'amount' => PaymentUtil.toPaise(detail.amount),
            'currency' => 'INR',
            'keyId' => PaymentUtil.getPublicKeyId()
        });
    }

    private static void handleVerify(RestRequest req, RestResponse res) {
        VerifyRequest payload = (VerifyRequest) JSON.deserialize(
            req.requestBody.toString(), VerifyRequest.class
        );
        Id paymentTermId = normalizeId(payload.paymentTermId);
        Id contactId = normalizeId(payload.contactId);

        Boolean signatureValid = PaymentUtil.verifyPaymentSignature(
            payload.razorpayOrderId, payload.razorpayPaymentId, payload.razorpaySignature
        );

        if (!signatureValid) {
            PaymentService.markPaymentFailed(paymentTermId, payload.razorpayOrderId);
            writeError(res, 400, 'Payment verification failed. Please contact support if the amount was debited.');
            return;
        }

        // Re-validate ownership before writing, using the same rule as /details.
        PaymentService.PaymentTermDetail detail = PaymentService.getPayableTerm(paymentTermId, contactId);

        // Must render the PDF before any DML in this transaction --
        // getContentAsPDF cannot run once there's uncommitted work pending.
        Blob receiptPdf;
        try {
            receiptPdf = ReceiptArtifactService.renderReceiptPdf(detail, payload.razorpayOrderId, payload.razorpayPaymentId);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not render receipt PDF: ' + ex.getMessage());
        }

        Boolean newlyPaid = PaymentService.markPaymentSuccess(
            paymentTermId, payload.razorpayOrderId, payload.razorpayPaymentId, payload.razorpaySignature, detail.amount
        );

        if (receiptPdf != null) {
            ReceiptArtifactService.attachReceiptArtifacts(paymentTermId, detail, payload.razorpayOrderId, payload.razorpayPaymentId, receiptPdf);
        }

        // Only email on the call that actually marked the term Paid -- the
        // Razorpay webhook may have already done so for this same payment,
        // and we don't want to send it twice.
        if (newlyPaid) {
            String paymentDateLabel = Datetime.now().format('dd MMM yyyy, hh:mm a');
            PaymentSuccessEmailService.sendPaymentSuccessEmails(detail, payload.razorpayPaymentId, paymentDateLabel, contactId, receiptPdf);
        }

        writeSuccess(res, 200, new Map<String, Object>{
            'success' => true,
            'message' => 'Payment verified successfully.',
            'transactionStatus' => 'Paid',
            'paymentDate' => Datetime.now().format()
        });
    }

    private static void handleOfflinePayment(RestRequest req, RestResponse res) {
        OfflinePaymentRequest payload = (OfflinePaymentRequest) JSON.deserialize(
            req.requestBody.toString(), OfflinePaymentRequest.class
        );
        Id paymentTermId = normalizeId(payload.paymentTermId);
        Id contactId = normalizeId(payload.contactId);

        PaymentService.saveOfflinePaymentDetails(paymentTermId, contactId, payload.description);

        writeSuccess(res, 200, new Map<String, Object>{
            'success' => true,
            'message' => 'Your offline payment details have been recorded. Please contact your supervisor to complete the payment.'
        });
    }

    private static void handleHistory(RestRequest req, RestResponse res) {
        Id contactId = getParamId(req, 'contactId');
        List<PaymentService.PaymentHistoryItem> history = PaymentService.getPaymentHistory(contactId);

        List<Map<String, Object>> payments = new List<Map<String, Object>>();
        for (PaymentService.PaymentHistoryItem item : history) {
            payments.add(new Map<String, Object>{
                'paymentTermId' => item.paymentTermId,
                'projectName' => item.projectName,
                'installmentLabel' => item.installmentLabel,
                'amount' => item.amount,
                'percentage' => item.percentage,
                'status' => item.status,
                'dueDate' => item.dueDate,
                'paymentDate' => item.paymentDate,
                'razorpayPaymentId' => item.razorpayPaymentId
            });
        }

        writeSuccess(res, 200, new Map<String, Object>{ 'success' => true, 'payments' => payments });
    }

    private static void handleReceipt(RestRequest req, RestResponse res) {
        Id paymentTermId = getParamId(req, 'paymentTermId');
        Id contactId = getParamId(req, 'contactId');

        PaymentService.ReceiptData receipt = PaymentService.getReceipt(paymentTermId, contactId);

        writeSuccess(res, 200, new Map<String, Object>{
            'success' => true,
            'receipt' => new Map<String, Object>{
                'receiptNumber' => receipt.receiptNumber,
                'projectName' => receipt.projectName,
                'customerName' => receipt.customerName,
                'customerEmail' => receipt.customerEmail,
                'installmentLabel' => receipt.installmentLabel,
                'percentage' => receipt.percentage,
                'amount' => receipt.amount,
                'currency' => receipt.currencyCode,
                'paymentDate' => receipt.paymentDate,
                'razorpayOrderId' => receipt.razorpayOrderId,
                'razorpayPaymentId' => receipt.razorpayPaymentId,
                'status' => receipt.status
            }
        });
    }

    private static Id getParamId(RestRequest req, String paramName) {
        return normalizeId(req.params.get(paramName));
    }

    private static Id normalizeId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        try {
            return Id.valueOf(rawValue);
        } catch (Exception ex) {
            throw new PaymentException('Invalid identifier supplied.');
        }
    }

    private static void writeSuccess(RestResponse res, Integer statusCode, Map<String, Object> body) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    private static void writeError(RestResponse res, Integer statusCode, String message) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'success' => false, 'message' => message }));
    }
}