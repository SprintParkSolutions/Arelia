@RestResource(urlMapping='/payment-terms')
global without sharing class PaymentTermRestService {

    @HttpGet
    global static List<PaymentTermDTO> getTerms() {

        String projectName = RestContext.request.params.get('projectName');

        if (String.isBlank(projectName)) {
            return new List<PaymentTermDTO>();
        }

        List<Payment_Term__c> terms = [
            SELECT Name,
                   Percentage__c,
                   Due_Date__c,
                   Payment_Received__c,
                   Term_Label__c
            FROM Payment_Term__c
            WHERE Project__r.Name = :projectName
            ORDER BY Due_Date__c
        ];

        List<PaymentTermDTO> result = new List<PaymentTermDTO>();
        for (Payment_Term__c t : terms) {
            result.add(new PaymentTermDTO(t));
        }
        return result;
    }

    global class PaymentTermDTO {
        public String name;
        public Decimal percentage;
        public Date dueDate;
        public Boolean paymentReceived;
        public String label;

        public PaymentTermDTO(Payment_Term__c t) {
            name = t.Name;
            percentage = t.Percentage__c;
            dueDate = t.Due_Date__c;
            paymentReceived = t.Payment_Received__c;
            label = t.Term_Label__c;
        }
    }
}