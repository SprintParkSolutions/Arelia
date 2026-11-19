@RestResource(urlMapping='/payment-terms')
global without sharing class PaymentTermRestService {
    @HttpGet
    global static List<PaymentTermDTO> getTerms() {
        String projectName = RestContext.request.params.get('projectName');
        if (String.isBlank(projectName)) return new List<PaymentTermDTO>();
        List<Payment_Term__c> terms = [
            SELECT Id, Name, Percentage__c, Due_Date__c, Payment_Received__c,
                   Transaction_Status__c, Paid_Amount__c, Term_Label__c, Project__c,
                   Project__r.Supervisor_Estimated_Budget__c
            FROM Payment_Term__c
            WHERE Project__r.Name = :projectName AND Project__r.RecordType.Name = 'Arelia'
            ORDER BY Due_Date__c ASC NULLS LAST, Id ASC
        ];
        Set<Id> projectIds = new Set<Id>();
        for (Payment_Term__c term : terms) projectIds.add(term.Project__c);
        Map<Id, Decimal> amounts = PaymentService.getProjectScheduleAmounts(projectIds);
        List<PaymentTermDTO> result = new List<PaymentTermDTO>();
        for (Payment_Term__c term : terms) result.add(new PaymentTermDTO(term, amounts.get(term.Id)));
        return result;
    }

    global class PaymentTermDTO {
        public String id;
        public String name;
        public Decimal percentage;
        public Date dueDate;
        public Boolean paymentReceived;
        public String label;
        public Decimal amount;
        public Decimal totalAmount;
        public Decimal paidAmount;

        public PaymentTermDTO(Payment_Term__c term, Decimal scheduledAmount) {
            id = term.Id;
            name = term.Name;
            percentage = term.Percentage__c;
            dueDate = term.Due_Date__c;
            paymentReceived = PaymentService.resolveStatus(term) == 'Paid';
            label = term.Term_Label__c;
            amount = scheduledAmount;
            paidAmount = paymentReceived ? term.Paid_Amount__c : null;
            totalAmount = term.Project__r.Supervisor_Estimated_Budget__c;
        }
    }
}