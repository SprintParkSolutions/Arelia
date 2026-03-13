@RestResource(urlMapping='/mobile/payment-terms-by-project')
global without sharing class MobilePaymentTermsByProjectService {

    global class PaymentDTO {
        public Id     paymentId;
        public String name;
    }

    global class ResponseDTO {
        public Boolean success;
        public String  message;
        public List<PaymentDTO> payments;
    }

    @HttpPost
    global static ResponseDTO getPayments() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.payments = new List<PaymentDTO>();

        try {
            String raw = (RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();

            if (String.isBlank(raw)) {
                resp.message = 'Request body is empty';
                return resp;
            }

            Map<String, Object> input =
                (Map<String, Object>) JSON.deserializeUntyped(raw);

            String projectId = (String) input.get('projectId');

            if (String.isBlank(projectId)) {
                resp.message = 'ProjectId is required';
                return resp;
            }

            List<Payment_Term__c> terms = [
                SELECT Id, Name
                FROM Payment_Term__c
                WHERE Project__c = :projectId
                ORDER BY CreatedDate ASC
            ];

            for (Payment_Term__c pt : terms) {
                PaymentDTO dto = new PaymentDTO();
                dto.paymentId = pt.Id;
                dto.name = pt.Name;
                resp.payments.add(dto);
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