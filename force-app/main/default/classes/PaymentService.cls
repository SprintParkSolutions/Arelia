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
/**
 * Payment amounts are supplied by one project-wide allocation.
 * Paid_Amount__c is the immutable amount actually received.
 * Order_Amount__c is the server-side amount used to create a Razorpay order.
 * Existing guest-facing access conventions are retained.
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
        public Decimal orderAmount;
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

    private static final String TERM_FIELDS =
        'Id, Name, Term_Label__c, Percentage__c, Due_Date__c, Transaction_Status__c, ' +
        'Paid_Amount__c, Order_Amount__c, Payment_Received__c, Payment_Date__c, ' +
        'Razorpay_Order_Id__c, Razorpay_Payment_Id__c, Project__c, Project__r.Name, ' +
        'Project__r.Supervisor_Estimated_Budget__c, Project__r.Client__c, ' +
        'Project__r.Client__r.Name, Project__r.Client__r.Email, Project__r.Client__r.Phone';

    private static Payment_Term__c readTerm(Id paymentTermId, Id contactId) {
        if (paymentTermId == null) throw new PaymentException('A payment term is required.');
        List<Payment_Term__c> terms = Database.query(
            'SELECT ' + TERM_FIELDS + ' FROM Payment_Term__c WHERE Id = :paymentTermId LIMIT 1'
        );
        if (terms.isEmpty()) throw new PaymentException('Payment term not found.');
        Payment_Term__c term = terms[0];
        if (contactId != null && term.Project__r != null && term.Project__r.Client__c != contactId) {
            throw new PaymentException('You are not authorized to view this payment term.');
        }
        return term;
    }

    public static PaymentTermDetail getPayableTerm(Id paymentTermId, Id contactId) {
        Payment_Term__c term = readTerm(paymentTermId, contactId);
        return toDetail(term, getProjectScheduleAmounts(new Set<Id>{term.Project__c}).get(term.Id));
    }

    // Queries all siblings, even when a caller needs only a single installment
    // or a contact's history spans more than one project.
    public static Map<Id, Decimal> getProjectScheduleAmounts(Set<Id> projectIds) {
        projectIds = new Set<Id>(projectIds);
        projectIds.remove(null);
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        if (projectIds.isEmpty()) return result;
        List<Payment_Term__c> terms = Database.query(
            'SELECT ' + TERM_FIELDS + ' FROM Payment_Term__c WHERE Project__c IN :projectIds ' +
            'ORDER BY Due_Date__c ASC NULLS LAST, Id ASC'
        );
        Map<Id, List<PaymentScheduleCalculator.Line>> groups = new Map<Id, List<PaymentScheduleCalculator.Line>>();
        Map<Id, Decimal> budgets = new Map<Id, Decimal>();
        for (Payment_Term__c term : terms) {
            if (!groups.containsKey(term.Project__c)) {
                groups.put(term.Project__c, new List<PaymentScheduleCalculator.Line>());
                budgets.put(term.Project__c, term.Project__r.Supervisor_Estimated_Budget__c);
            }
            groups.get(term.Project__c).add(new PaymentScheduleCalculator.Line(
                term.Id, term.Percentage__c, resolveStatus(term) == STATUS_PAID, term.Paid_Amount__c
            ));
        }
        for (Id projectId : groups.keySet()) {
            result.putAll(PaymentScheduleCalculator.allocate(budgets.get(projectId), groups.get(projectId)));
        }
        return result;
    }

    public static void assertPending(PaymentTermDetail detail) {
        if (detail == null || detail.status != STATUS_PENDING) {
            throw new PaymentException('This installment has already been paid or is not currently payable.');
        }
        if (detail.amount == null || detail.amount <= 0) {
            throw new PaymentException('The payment amount could not be determined. Please contact support to reconcile the payment schedule.');
        }
    }

    public static void recordPaymentOrder(Id paymentTermId, String orderId, Decimal amount) {
        if (String.isBlank(orderId) || amount == null || amount <= 0) {
            throw new PaymentException('A valid payment order and amount are required.');
        }
        Payment_Term__c term = [
            SELECT Id, Transaction_Status__c, Payment_Received__c, Razorpay_Order_Id__c, Order_Amount__c
            FROM Payment_Term__c WHERE Id = :paymentTermId LIMIT 1 FOR UPDATE
        ];
        if (resolveStatus(term) != STATUS_PENDING) throw new PaymentException('This installment is no longer payable.');
        if (term.Order_Amount__c != null && String.isNotBlank(term.Razorpay_Order_Id__c) &&
            term.Razorpay_Order_Id__c != orderId) {
            throw new PaymentException('Another payment order already exists for this installment. Please try again.');
        }
        term.Razorpay_Order_Id__c = orderId;
        term.Order_Amount__c = amount.setScale(2, RoundingMode.HALF_UP);
        update term;
    }

    @TestVisible private static Decimal getRecordedOrderAmount(Payment_Term__c term, String orderId) {
        if (String.isBlank(orderId) || term.Razorpay_Order_Id__c != orderId ||
            term.Order_Amount__c == null || term.Order_Amount__c <= 0) {
            throw new PaymentException('The original payment order amount is unavailable. Please contact support to reconcile this payment.');
        }
        return term.Order_Amount__c;
    }

    // Verification and PDF/email generation must use the order's original
    // amount, even if the budget changed after that order was created.
    public static PaymentTermDetail getPaymentVerificationDetail(Id paymentTermId, Id contactId, String orderId) {
        Payment_Term__c term = readTerm(paymentTermId, contactId);
        if (resolveStatus(term) == STATUS_PAID) {
            if (term.Razorpay_Order_Id__c != orderId || term.Paid_Amount__c == null) {
                throw new PaymentException('This payment does not match the recorded installment.');
            }
            return toDetail(term, term.Paid_Amount__c);
        }
        if (resolveStatus(term) == STATUS_REFUNDED) throw new PaymentException('This installment has been refunded.');
        return toDetail(term, getRecordedOrderAmount(term, orderId));
    }

    public static Boolean markPaymentSuccess(Id paymentTermId, String orderId, String paymentId, String signature, Decimal amountPaid) {
        List<Payment_Term__c> terms = [
            SELECT Id, Transaction_Status__c, Payment_Received__c, Description__c,
                   Paid_Amount__c, Order_Amount__c, Razorpay_Order_Id__c, Razorpay_Payment_Id__c
            FROM Payment_Term__c WHERE Id = :paymentTermId LIMIT 1 FOR UPDATE
        ];
        if (terms.isEmpty()) throw new PaymentException('Payment term not found.');
        Payment_Term__c term = terms[0];
        if (resolveStatus(term) == STATUS_PAID) {
            if (term.Razorpay_Order_Id__c != orderId || term.Razorpay_Payment_Id__c != paymentId) {
                throw new PaymentException('A different payment has already settled this installment.');
            }
            return false;
        }
        // Never accept a recomputed budget percentage as proof of how much
        // Razorpay charged. The amount was captured server-side at order creation.
        if (resolveStatus(term) == STATUS_REFUNDED) throw new PaymentException('This installment has been refunded.');
        Decimal capturedAmount = getRecordedOrderAmount(term, orderId);
        if (String.isBlank(paymentId)) throw new PaymentException('A payment identifier is required.');
        Datetime paymentDate = Datetime.now();
        term.Transaction_Status__c = STATUS_PAID;
        term.Payment_Received__c = true;
        term.Paid_Amount__c = capturedAmount;
        term.Payment_Date__c = paymentDate;
        term.Razorpay_Order_Id__c = orderId;
        term.Razorpay_Payment_Id__c = paymentId;
        term.Razorpay_Signature__c = signature;
        term.Description__c = appendPaymentDescription(term.Description__c, paymentDate, capturedAmount, paymentId);
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

    public static void saveOfflinePaymentDetails(Id paymentTermId, Id contactId, String description) {
        PaymentTermDetail detail = getPayableTerm(paymentTermId, contactId);
        assertPending(detail);
        if (String.isBlank(description)) throw new PaymentException('Please describe how you will complete this payment offline.');
        update new Payment_Term__c(Id = paymentTermId, Payment_Mode__c = 'Offline', Offline_Payment_Description__c = description);
    }

    public static void markPaymentFailed(Id paymentTermId, String orderId) {
        List<Payment_Term__c> terms = [
            SELECT Id, Transaction_Status__c, Payment_Received__c, Razorpay_Order_Id__c
            FROM Payment_Term__c WHERE Id = :paymentTermId LIMIT 1 FOR UPDATE
        ];
        if (terms.isEmpty()) return;
        Payment_Term__c term = terms[0];
        // A late failure must never overwrite a successful payment.
        if (resolveStatus(term) == STATUS_PAID || term.Razorpay_Order_Id__c != orderId) return;
        term.Transaction_Status__c = STATUS_FAILED;
        update term;
    }

    public static void markPaymentRefunded(String razorpayOrderId) {
        List<Payment_Term__c> terms = [
            SELECT Id, Transaction_Status__c FROM Payment_Term__c
            WHERE Razorpay_Order_Id__c = :razorpayOrderId LIMIT 1
        ];
        if (terms.isEmpty()) return;
        terms[0].Transaction_Status__c = STATUS_REFUNDED;
        update terms[0];
    }

    public static List<PaymentHistoryItem> getPaymentHistory(Id contactId) {
        if (contactId == null) throw new PaymentException('A contact is required.');
        List<Payment_Term__c> terms = Database.query(
            'SELECT ' + TERM_FIELDS + ' FROM Payment_Term__c WHERE Project__r.Client__c = :contactId ' +
            'ORDER BY Due_Date__c ASC NULLS LAST, Id ASC'
        );
        Set<Id> projectIds = new Set<Id>();
        for (Payment_Term__c term : terms) projectIds.add(term.Project__c);
        Map<Id, Decimal> amounts = getProjectScheduleAmounts(projectIds);
        List<PaymentHistoryItem> history = new List<PaymentHistoryItem>();
        for (Payment_Term__c term : terms) {
            PaymentHistoryItem item = new PaymentHistoryItem();
            item.paymentTermId = term.Id;
            item.projectName = term.Project__r != null ? term.Project__r.Name : null;
            item.installmentLabel = String.isNotBlank(term.Term_Label__c) ? term.Term_Label__c : term.Name;
            item.amount = amounts.get(term.Id);
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
        if (detail.status != STATUS_PAID) throw new PaymentException('No receipt is available until this installment is paid.');
        if (detail.amount == null) throw new PaymentException('The original paid amount must be reconciled before a receipt can be issued.');
        ReceiptData receipt = new ReceiptData();
        receipt.receiptNumber = String.isNotBlank(detail.razorpayPaymentId) ? detail.razorpayPaymentId : String.valueOf(detail.paymentTermId);
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

    public static String resolveStatus(Payment_Term__c term) {
        if (String.isNotBlank(term.Transaction_Status__c)) return term.Transaction_Status__c;
        return term.Payment_Received__c == true ? STATUS_PAID : STATUS_PENDING;
    }

    private static PaymentTermDetail toDetail(Payment_Term__c term, Decimal amount) {
        PaymentTermDetail detail = new PaymentTermDetail();
        detail.paymentTermId = term.Id;
        detail.projectName = term.Project__r != null ? term.Project__r.Name : null;
        detail.customerName = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Name : null;
        detail.customerEmail = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Email : null;
        detail.customerPhone = term.Project__r != null && term.Project__r.Client__r != null ? term.Project__r.Client__r.Phone : null;
        detail.installmentLabel = String.isNotBlank(term.Term_Label__c) ? term.Term_Label__c : term.Name;
        detail.percentage = term.Percentage__c;
        detail.amount = amount;
        detail.totalAmount = term.Project__r != null ? term.Project__r.Supervisor_Estimated_Budget__c : null;
        detail.dueDate = term.Due_Date__c != null ? term.Due_Date__c.format() : null;
        detail.status = resolveStatus(term);
        detail.razorpayOrderId = term.Razorpay_Order_Id__c;
        detail.razorpayPaymentId = term.Razorpay_Payment_Id__c;
        detail.paymentDate = term.Payment_Date__c != null ? term.Payment_Date__c.format() : null;
        detail.orderAmount = term.Order_Amount__c;
        return detail;
    }
}