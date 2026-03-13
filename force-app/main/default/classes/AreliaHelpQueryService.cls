@RestResource(urlMapping='/AreliaHelpQuery/*')
global with sharing class AreliaHelpQueryService {

    // Incoming JSON from Android
    global class HelpRequestDTO {
        public String name;
        public String email;
        public String message;
    }

    // Response JSON back to Android
    global class HelpResponseDTO {
        public Boolean success;
        public String errorMessage;
    }

    @HttpPost
    global static HelpResponseDTO submit() {
        RestRequest req = RestContext.request;
        HelpResponseDTO resp = new HelpResponseDTO();
        resp.success = false;

        try {
            // Parse JSON
            HelpRequestDTO input = (HelpRequestDTO) JSON.deserialize(
                req.requestBody.toString(),
                HelpRequestDTO.class
            );

            if (String.isBlank(input.name) ||
                String.isBlank(input.email) ||
                String.isBlank(input.message)) {
                resp.errorMessage = 'Missing required fields';
                return resp;
            }

            // Build email
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { 'monikag@sprintpark.com' }); // 👈 your email
            mail.setSubject('Arelia Living App - Customer Query from ' + input.name);

            String body =
                'You received a new Help / Support query from the Arelia Living mobile app.' + '\n\n' +
                'Name: ' + input.name + '\n' +
                'Email: ' + input.email + '\n\n' +
                'Message:' + '\n' +
                input.message;

            mail.setPlainTextBody(body);

            // Send email
            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[] { mail }
            );

            if (results != null &&
                !results.isEmpty() &&
                results[0].isSuccess()) {
                resp.success = true;
                resp.errorMessage = null;
            } else {
                String err = 'Unknown error sending email';
                if (results != null &&
                    !results.isEmpty() &&
                    results[0].getErrors().size() > 0) {
                    err = results[0].getErrors()[0].getMessage();
                }
                resp.errorMessage = err;
            }

        } catch (Exception e) {
            resp.success = false;
            resp.errorMessage = e.getMessage();
        }

        return resp;
    }
}