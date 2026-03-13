@RestResource(urlMapping='/mobile/payment-term-auth')
global without sharing class MobilePaymentTermsAuthService {

    global class PaymentTermDTO {
        public String name;
        public Decimal percentage;
        public Date dueDate;
        public Boolean paymentReceived;
        public String label;
    }

    global class ResponseDTO {
        public Boolean success;
        public String message;
        public List<PaymentTermDTO> terms;
    }

    @HttpPost
    global static ResponseDTO getTerms() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.terms = new List<PaymentTermDTO>();

        try {
            String raw = (RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();

            Map<String, Object> input =
                (raw == null || raw.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);

            String projectId = (String) input.get('projectId');

            if (String.isBlank(projectId)) {
                resp.message = 'ProjectId is required';
                return resp;
            }

            // ✅ Query payment terms by selected project
            List<Payment_Term__c> terms = [
                SELECT Name,
                       Percentage__c,
                       Due_Date__c,
                       Payment_Received__c,
                       Term_Label__c
                FROM Payment_Term__c
                WHERE Project__c = :projectId
                ORDER BY Due_Date__c ASC
            ];

            for (Payment_Term__c t : terms) {
                PaymentTermDTO dto = new PaymentTermDTO();
                dto.name = t.Name;
                dto.percentage = t.Percentage__c != null ? t.Percentage__c : 0;
                dto.dueDate = t.Due_Date__c;
                dto.paymentReceived = (t.Payment_Received__c == true);
                dto.label = t.Term_Label__c;
                resp.terms.add(dto);
            }

            resp.success = true;
            resp.message = 'Success';
            return resp;

        } catch (Exception e) {
            resp.success = false;
            resp.message = e.getMessage();
            return resp;
        }
    }
}