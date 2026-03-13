@RestResource(urlMapping='/registration/otp')
global with sharing class RegistrationOtpRestController {

    global class OtpRequest {
        public String email;
        public String otp;
    }

    global class OtpResponse {
        public Boolean success;
        public String message;
    }

    @HttpPost
    global static OtpResponse sendOtp() {

        OtpResponse res = new OtpResponse();

        try {
            RestRequest req = RestContext.request;
            String body = req.requestBody.toString();

            OtpRequest input =
                (OtpRequest) JSON.deserialize(body, OtpRequest.class);

            RegistrationFormController.sendVerificationEmail(
                input.email,
                input.otp
            );

            res.success = true;

        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
        }

        return res;
    }
}