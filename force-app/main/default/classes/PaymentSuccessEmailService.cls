public without sharing class PaymentSuccessEmailService {

    // Match these to the Developer Name of each Email Template you create in Setup.
    private static final String CLIENT_TEMPLATE_DEV_NAME = 'Payment_Success_Client';
    private static final String SUPERVISOR_TEMPLATE_DEV_NAME = 'Payment_Success_Supervisor';

    // Call this only when PaymentService.markPaymentSuccess just returned true for this
    // payment (see RazorpayController.handleVerify / RazorpayWebhook.handleWebhook).
    // detail is the PaymentTermDetail the caller already fetched before marking the term
    // paid -- it carries the correct amount/percentage/labels since those are derived from
    // Project__r.Supervisor_Estimated_Budget__c and never stored on Payment_Term__c itself.
    // razorpayPaymentId/paymentDateLabel are passed separately since detail was fetched
    // before those fields were set on the record. receiptPdf is the same Blob the caller
    // just rendered and passed to ReceiptArtifactService.attachReceiptArtifacts -- reused
    // here instead of re-querying the ContentVersion just saved on the record.
    public static void sendPaymentSuccessEmails(PaymentService.PaymentTermDetail detail, String razorpayPaymentId, String paymentDateLabel, Id contactId, Blob receiptPdf) {
        if (detail == null || detail.paymentTermId == null) {
            return;
        }

        Messaging.EmailFileAttachment receiptAttachment;
        if (receiptPdf != null) {
            String receiptNumber = String.isNotBlank(razorpayPaymentId) ? razorpayPaymentId : String.valueOf(detail.paymentTermId);
            receiptAttachment = new Messaging.EmailFileAttachment();
            receiptAttachment.setFileName('Receipt-' + receiptNumber + '.pdf');
            receiptAttachment.setBody(receiptPdf);
        }

        String supervisorEmail;
        String supervisorName;
        try {
            Payment_Term__c term = [
                SELECT Project__r.Supervisor_Email_Text_c__c,
                       Project__r.Supervisor_User__r.FirstName,
                       Project__r.Supervisor_User__r.LastName
                FROM Payment_Term__c
                WHERE Id = :detail.paymentTermId
                LIMIT 1
            ];
            if (term.Project__r != null) {
                supervisorEmail = term.Project__r.Supervisor_Email_Text_c__c;
                supervisorName = buildFullName(
                    term.Project__r.Supervisor_User__r != null ? term.Project__r.Supervisor_User__r.FirstName : null,
                    term.Project__r.Supervisor_User__r != null ? term.Project__r.Supervisor_User__r.LastName : null
                );
            }
        } catch (QueryException qe) {
            System.debug(LoggingLevel.ERROR, 'PaymentSuccessEmailService: Payment_Term__c not found - ' + qe.getMessage());
            return;
        }

        Map<String, EmailTemplate> templateByDevName = new Map<String, EmailTemplate>();
        for (EmailTemplate et : [
            SELECT Id, DeveloperName, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName IN (:CLIENT_TEMPLATE_DEV_NAME, :SUPERVISOR_TEMPLATE_DEV_NAME)
        ]) {
            templateByDevName.put(et.DeveloperName, et);
        }

        // Tokens available in both templates -- use these in the template's HTML body
        // in Setup, e.g. "Amount Paid: {AmountPaid}".
        Map<String, String> mergeValues = new Map<String, String>{
            '{ClientName}' => String.isNotBlank(detail.customerName) ? detail.customerName : 'Customer',
            '{SupervisorName}' => String.isNotBlank(supervisorName) ? supervisorName : 'Supervisor',
            '{ProjectName}' => detail.projectName,
            '{InstallmentLabel}' => detail.installmentLabel,
            '{Percentage}' => detail.percentage != null ? String.valueOf(detail.percentage) + '%' : '',
            '{AmountPaid}' => PaymentUtil.formatIndianCurrency(detail.amount),
            '{PaymentDate}' => paymentDateLabel,
            '{RazorpayPaymentId}' => razorpayPaymentId
        };

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        // 1. Email to client
        EmailTemplate clientTpl = templateByDevName.get(CLIENT_TEMPLATE_DEV_NAME);
        if (contactId != null && clientTpl != null && String.isNotBlank(detail.customerEmail)) {
            Messaging.SingleEmailMessage clientEmail = new Messaging.SingleEmailMessage();
            clientEmail.setToAddresses(new List<String>{ detail.customerEmail });
            clientEmail.setSubject(mergeTokens(clientTpl.Subject, mergeValues));
            clientEmail.setHtmlBody(mergeTokens(clientTpl.HtmlValue, mergeValues));
            clientEmail.setWhatId(detail.paymentTermId);
            clientEmail.setSaveAsActivity(false);
            AreliaUtility.setOrgWideEmailAddress(clientEmail, System.Label.Arelia_OWD);
            if (receiptAttachment != null) {
                clientEmail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ receiptAttachment });
            }
            emailsToSend.add(clientEmail);
        }

        // 2. Email to supervisor (stored as a plain email formula field on Project, not a Contact/User)
        EmailTemplate supervisorTpl = templateByDevName.get(SUPERVISOR_TEMPLATE_DEV_NAME);
        if (String.isNotBlank(supervisorEmail) && supervisorTpl != null) {
            Messaging.SingleEmailMessage supervisorEmailMsg = new Messaging.SingleEmailMessage();
            supervisorEmailMsg.setToAddresses(new List<String>{ supervisorEmail });
            supervisorEmailMsg.setSubject(mergeTokens(supervisorTpl.Subject, mergeValues));
            supervisorEmailMsg.setHtmlBody(mergeTokens(supervisorTpl.HtmlValue, mergeValues));
            supervisorEmailMsg.setWhatId(detail.paymentTermId);
            supervisorEmailMsg.setSaveAsActivity(false);
            AreliaUtility.setOrgWideEmailAddress(supervisorEmailMsg, System.Label.Arelia_OWD);
            if (receiptAttachment != null) {
                supervisorEmailMsg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ receiptAttachment });
            }
            emailsToSend.add(supervisorEmailMsg);
        }

        if (!emailsToSend.isEmpty()) {
            try {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emailsToSend, false);
                for (Messaging.SendEmailResult result : results) {
                    if (!result.isSuccess()) {
                        for (Messaging.SendEmailError err : result.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'PaymentSuccessEmailService: Email send failed - ' + err.getStatusCode() + ': ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'PaymentSuccessEmailService: Failed to send payment success emails - ' + ex.getMessage());
            }
        }
    }

    private static String buildFullName(String firstName, String lastName) {
        String fullName = '';
        if (String.isNotBlank(firstName)) {
            fullName += firstName + ' ';
        }
        if (String.isNotBlank(lastName)) {
            fullName += lastName;
        }
        return fullName.trim();
    }

    private static String mergeTokens(String text, Map<String, String> mergeValues) {
        if (String.isBlank(text)) {
            return text;
        }
        String result = text;
        for (String token : mergeValues.keySet()) {
            String value = mergeValues.get(token);
            result = result.replace(token, value != null ? value : '');
        }
        return result;
    }
}