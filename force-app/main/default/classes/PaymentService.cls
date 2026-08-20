/**
 * Business logic and SOQL for the Razorpay payment flow: reading a payable
 * Payment_Term__c, enforcing the Pending-only / no-double-payment rule, and
 * applying the record updates once a payment is verified or fails.
 *
 * without sharing, and no Security.stripInaccessible on the read paths --
 * this matches the established pattern of every other guest-facing Apex
 * class in this org (e.g. PaymentTermRestService): the guest site user is
 * never granted object CRUD/FLS on any custom object, so all guest REST
 * endpoints run in plain system mode. The real security boundary is the
 * explicit contactId ownership check below, not object permissions.
 */
public without sharing class PaymentService {

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_PAID = 'Paid';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_REFUNDED = 'Refunded';

    public class PaymentTermDetail {
        public Id paymentTermId;
        public String projectName;
        public String customerName;
        public String customerEmail;
        public String customerPhone;
        public String installmentLabel;
        public Decimal percentage;
        public Decimal amount;
        public Decimal totalAmount;
        public String dueDate;
        public String status;
        public String razorpayOrderId;
        public String razorpayPaymentId;
        public String paymentDate;
    }

    public class PaymentHistoryItem {
        public Id paymentTermId;
        public String projectName;
        public String installmentLabel;
        public Decimal amount;
        public Decimal percentage;
        public String status;
        public String dueDate;
        public String paymentDate;
        public String razorpayPaymentId;
    }

    public class ReceiptData {
        public String receiptNumber;
        public String projectName;
        public String customerName;
        public String customerEmail;
        public String installmentLabel;
        public Decimal percentage;
        public Decimal amount;
        public String currencyCode;
        public String paymentDate;
        public String razorpayOrderId;
        public String razorpayPaymentId;
        public String status;
    }

    // Payment_Term__c has no Amount__c field -- the installment amount is
    // derived from the parent Project__c's Supervisor_Estimated_Budget__c
    // ("Project Final Approval Budget", the finalized contract value) times
    // this term's Percentage__c.
    private static final String TERM_FIELDS =
        'Id, Name, Percentage__c, Due_Date__c, Transaction_Status__c, ' +
        'Payment_Received__c, Payment_Date__c, Razorpay_Order_Id__c, Razorpay_Payment_Id__c, ' +
        'Project__c, Project__r.Name, Project__r.Supervisor_Estimated_Budget__c, Project__r.Client__c, ' +
        'Project__r.Client__r.Name, Project__r.Client__r.Email, Project__r.Client__r.Phone';

    public static PaymentTermDetail getPayableTerm(Id paymentTermId, Id contactId) {
        if (paymentTermId == null) {
            throw new PaymentException('A payment term is required.');
        }

        List<Payment_Term__c> terms = Database.query(
            'SELECT ' + TERM_FIELDS + ' FROM Payment_Term__c WHERE Id = :paymentTermId LIMIT 1'
        );

        if (terms.isEmpty()) {
            throw new PaymentException('Payment term not found.');
        }

        Payment_Term__c term = terms[0];

        if (contactId != null && term.Project__r != null && term.Project__r.Client__c != contactId) {
            throw new PaymentException('You are not authorized to view this payment term.');
        }

        return toDetail(term);
    }

    public static void assertPending(PaymentTermDetail detail) {
        if (detail == null || detail.status != STATUS_PENDING) {
            throw new PaymentException('This installment has already been paid or is not currently payable.');
        }
        // Amount is derived from Project__r.Supervisor_Estimated_Budget__c -- if that's not set
        // on the parent project, fail fast with a clear message rather than
        // silently sending Razorpay a 0-amount order (which it rejects with
        // a confusing "less than minimum amount" error).
        if (detail.amount == null || detail.amount <= 0) {
            throw new PaymentException('The payment amount for this installment could not be determined. Please contact support.');
        }
    }

    // Returns true if this call transitioned the term to Paid, false if it was
    // already Paid (e.g. the webhook and the client-side /verify call both
    // fired for the same payment) -- callers use this to avoid sending the
    // payment-success email twice for one payment.
    public static Boolean markPaymentSuccess(Id paymentTermId, String orderId, String paymentId, String signature, Decimal amountPaid) {
        List<Payment_Term__c> terms = [
            SELECT Id, Transaction_Status__c, Description__c
            FROM Payment_Term__c
            WHERE Id = :paymentTermId
            LIMIT 1
            FOR UPDATE
        ];

        if (terms.isEmpty()) {
            throw new PaymentException('Payment term not found.');
        }

        Payment_Term__c term = terms[0];
        if (term.Transaction_Status__c == STATUS_PAID) {
            return false;
        }

        Datetime paymentDate = Datetime.now();

        term.Transaction_Status__c = STATUS_PAID;
        term.Payment_Received__c = true;
        term.Payment_Date__c = paymentDate;
        term.Razorpay_Order_Id__c = orderId;
        term.Razorpay_Payment_Id__c = paymentId;
        term.Razorpay_Signature__c = signature;
        term.Description__c = appendPaymentDescription(term.Description__c, paymentDate, amountPaid, paymentId);

        // Guest users can only ever be granted Read/Create at the object
        // permission level (Salesforce platform restriction) -- they can
        // never have Update. So this write intentionally runs as a plain
        // system-mode DML rather than through Security.stripInaccessible,
        // which would otherwise strip every field being written (since the
        // object itself is never "updatable" for the guest user) and turn
        // this into a silent no-op. The curated, reviewed logic in this
        // method is the security boundary here, not object-level CRUD.
        update term;
        return true;
    }

    private static String appendPaymentDescription(String existingDescription, Datetime paymentDate, Decimal amountPaid, String paymentId) {
        String entry = 'Payment Received\n' +
            'Date: ' + paymentDate.format('dd MMM yyyy, hh:mm a') + '\n' +
            'Amount: ' + PaymentUtil.formatIndianCurrency(amountPaid) + ' (' + PaymentUtil.amountToWords(amountPaid) + ')\n' +
            'Razorpay Payment ID: ' + paymentId;

        return String.isNotBlank(existingDescription) ? existingDescription + '\n\n' + entry : entry;
    }

    // Records the customer's choice to pay this installment outside Razorpay.
    // Transaction_Status__c is deliberately left untouched (still Pending) --
    // this is not a payment confirmation, just a note for the supervisor who
    // must follow up and record the payment once it's actually received.
    public static void saveOfflinePaymentDetails(Id paymentTermId, Id contactId, String description) {
        PaymentTermDetail detail = getPayableTerm(paymentTermId, contactId);
        assertPending(detail);

        if (String.isBlank(description)) {
            throw new PaymentException('Please describe how you will complete this payment offline.');
        }

        Payment_Term__c term = new Payment_Term__c(
            Id = paymentTermId,
            Payment_Mode__c = 'Offline',
            Offline_Payment_Description__c = description
        );
        update term;
    }

    public static void markPaymentFailed(Id paymentTermId, String orderId) {
        Payment_Term__c term = new Payment_Term__c(
            Id = paymentTermId,
            Transaction_Status__c = STATUS_FAILED,
            Razorpay_Order_Id__c = orderId
        );
        update term;
    }

    public static void markPaymentRefunded(String razorpayOrderId) {
        List<Payment_Term__c> terms = [
            SELECT Id, Transaction_Status__c
            FROM Payment_Term__c
            WHERE Razorpay_Order_Id__c = :razorpayOrderId
            LIMIT 1
        ];

        if (terms.isEmpty()) {
            return;
        }

        Payment_Term__c term = terms[0];
        term.Transaction_Status__c = STATUS_REFUNDED;

        update term;
    }

    public static List<PaymentHistoryItem> getPaymentHistory(Id contactId) {
        if (contactId == null) {
            throw new PaymentException('A contact is required.');
        }

        List<Payment_Term__c> terms = Database.query(
            'SELECT ' + TERM_FIELDS + ' FROM Payment_Term__c ' +
            'WHERE Project__r.Client__c = :contactId ' +
            'ORDER BY Due_Date__c ASC NULLS LAST'
        );

        List<PaymentHistoryItem> history = new List<PaymentHistoryItem>();
        for (Payment_Term__c term : terms) {
            PaymentHistoryItem item = new PaymentHistoryItem();
            item.paymentTermId = term.Id;
            item.projectName = term.Project__r != null ? term.Project__r.Name : null;
            item.installmentLabel = term.Name;
            item.amount = calculateAmount(term);
            item.percentage = term.Percentage__c;
            item.status = resolveStatus(term);
            item.dueDate = term.Due_Date__c != null ? term.Due_Date__c.format() : null;
            item.paymentDate = term.Payment_Date__c != null ? term.Payment_Date__c.format() : null;
            item.razorpayPaymentId = term.Razorpay_Payment_Id__c;
            history.add(item);
        }
        return history;
    }

    public static ReceiptData getReceipt(Id paymentTermId, Id contactId) {
        PaymentTermDetail detail = getPayableTerm(paymentTermId, contactId);

        if (detail.status != STATUS_PAID) {
            throw new PaymentException('No receipt is available until this installment is paid.');
        }

        ReceiptData receipt = new ReceiptData();
        receipt.receiptNumber = detail.razorpayPaymentId;
        receipt.projectName = detail.projectName;
        receipt.customerName = detail.customerName;
        receipt.customerEmail = detail.customerEmail;
        receipt.installmentLabel = detail.installmentLabel;
        receipt.percentage = detail.percentage;
        receipt.amount = detail.amount;
        receipt.currencyCode = 'INR';
        receipt.paymentDate = detail.paymentDate;
        receipt.razorpayOrderId = detail.razorpayOrderId;
        receipt.razorpayPaymentId = detail.razorpayPaymentId;
        receipt.status = detail.status;
        return receipt;
    }

    // Transaction_Status__c was added for this Razorpay flow and was never
    // backfilled on pre-existing Payment_Term__c records -- it's blank on
    // every legacy record, which otherwise tracked paid/pending purely via
    // the Payment_Received__c checkbox. Fall back to that so legacy records
    // are still payable instead of being permanently stuck as "unknown".
    private static String resolveStatus(Payment_Term__c term) {
        if (String.isNotBlank(term.Transaction_Status__c)) {
            return term.Transaction_Status__c;
        }
        return term.Payment_Received__c == true ? STATUS_PAID : STATUS_PENDING;
    }

    private static Decimal calculateAmount(Payment_Term__c term) {
        Decimal budget = term.Project__r != null ? term.Project__r.Supervisor_Estimated_Budget__c : null;
        if (budget == null || term.Percentage__c == null) {
            return null;
        }
        return (budget * term.Percentage__c) / 100;
    }

    private static PaymentTermDetail toDetail(Payment_Term__c term) {
        PaymentTermDetail detail = new PaymentTermDetail();
        detail.paymentTermId = term.Id;
        detail.projectName = term.Project__r != null ? term.Project__r.Name : null;
        detail.customerName = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Name : null;
        detail.customerEmail = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Email : null;
        detail.customerPhone = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Phone : null;
        detail.installmentLabel = term.Name;
        detail.percentage = term.Percentage__c;
        detail.amount = calculateAmount(term);
        detail.totalAmount = term.Project__r != null ? term.Project__r.Supervisor_Estimated_Budget__c : null;
        detail.dueDate = term.Due_Date__c != null ? term.Due_Date__c.format() : null;
        detail.status = resolveStatus(term);
        detail.razorpayOrderId = term.Razorpay_Order_Id__c;
        detail.razorpayPaymentId = term.Razorpay_Payment_Id__c;
        detail.paymentDate = term.Payment_Date__c != null ? term.Payment_Date__c.format() : null;
        return detail;
    }
}