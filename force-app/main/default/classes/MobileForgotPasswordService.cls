@RestResource(urlMapping='/mobileForgotPassword/*')
global without sharing class MobileForgotPasswordService {

    global class ResponseDTO {
        public Boolean success;
        public String  message;
    }

    @HttpPost
    global static ResponseDTO handleRequest() {
        RestRequest req = RestContext.request;
        ResponseDTO resp = new ResponseDTO();
        resp.success = false;

        Map<String, Object> input;
        try {
            String raw = req.requestBody == null ? null : req.requestBody.toString();
            input = (raw == null || raw.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            resp.message = 'Invalid request body.';
            return resp;
        }

        String path = req.requestURI;

        try {
            if (path.endsWith('/sendOtp')) {
                return sendOtp(input);
            }

            if (path.endsWith('/verifyOtp')) {
                return verifyOtp(input);
            }

            if (path.endsWith('/reset')) {
                return resetPassword(input);
            }
        } catch (Exception e) {
            resp.success = false;
            resp.message = 'Something went wrong. Please try again.';
            return resp;
        }

        resp.message = 'Unknown action.';
        return resp;
    }

    private static ResponseDTO sendOtp(Map<String, Object> input) {
        ResponseDTO resp = new ResponseDTO();

        String email = input.get('email') == null
            ? null
            : String.valueOf(input.get('email')).trim();

        if (String.isBlank(email)) {
            resp.success = false;
            resp.message = 'Please provide your email address.';
            return resp;
        }

        // Always return the same generic message, whether or not the email
        // is on file, so this endpoint can't be used to discover which
        // emails belong to registered clients.
        resp.success = true;
        resp.message = 'If that email is on file, a verification code has been sent.';

        List<Contact> matches = [
            SELECT Id, Email
            FROM Contact
            WHERE Email = :email
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            return resp;
        }

        String otp = generateOtp();

        Contact c = matches[0];
        c.Reset_OTP__c = otp;
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(10);
        update c;

        // Reuse the proven send path from the registration flow — it already
        // handles the Guest User org-wide address and verification template.
        RegistrationFormController.sendVerificationEmail(email, otp);

        return resp;
    }

    private static ResponseDTO verifyOtp(Map<String, Object> input) {
        ResponseDTO resp = new ResponseDTO();
        resp.success = false;

        String email = input.get('email') == null
            ? null
            : String.valueOf(input.get('email')).trim();

        String otp = input.get('otp') == null
            ? null
            : String.valueOf(input.get('otp')).trim();

        if (String.isBlank(email) || String.isBlank(otp)) {
            resp.message = 'Please enter the verification code.';
            return resp;
        }

        List<Contact> matches = [
            SELECT Id, Email, Reset_OTP__c, Reset_OTP_Expiry__c
            FROM Contact
            WHERE Email = :email
            LIMIT 1
        ];

        if (matches.isEmpty()) {
            resp.message = 'That code is invalid or has expired.';
            return resp;
        }

        Contact c = matches[0];

        if (
            String.isBlank(c.Reset_OTP__c) ||
            c.Reset_OTP__c != otp ||
            c.Reset_OTP_Expiry__c == null ||
            c.Reset_OTP_Expiry__c < Datetime.now()
        ) {
            resp.message = 'That code is invalid or has expired.';
            return resp;
        }

        resp.success = true;
        resp.message = 'OTP verified successfully.';
        return resp;
    }

    private static ResponseDTO resetPassword(Map<String, Object> input) {
        ResponseDTO resp = new ResponseDTO();
        resp.success = false;

        String email = input.get('email') == null
            ? null
            : String.valueOf(input.get('email')).trim();

        String otp = input.get('otp') == null
            ? null
            : String.valueOf(input.get('otp')).trim();

        String newPassword = input.get('newPassword') == null
            ? null
            : String.valueOf(input.get('newPassword'));

        if (String.isBlank(email) || String.isBlank(otp) || String.isBlank(newPassword)) {
            resp.message = 'Missing required information.';
            return resp;
        }

        if (newPassword.length() < 8) {
            resp.message = 'Password must be at least 8 characters.';
            return resp;
        }

        List<Contact> matches = [
            SELECT Id, Email, Reset_OTP__c, Reset_OTP_Expiry__c
            FROM Contact
            WHERE Email = :email
            LIMIT 1
        ];

        if (
            matches.isEmpty() ||
            String.isBlank(matches[0].Reset_OTP__c) ||
            matches[0].Reset_OTP__c != otp
        ) {
            resp.message = 'That code is invalid or has expired.';
            return resp;
        }

        Contact c = matches[0];

        if (c.Reset_OTP_Expiry__c == null || c.Reset_OTP_Expiry__c < Datetime.now()) {
            resp.message = 'That code is invalid or has expired.';
            return resp;
        }

        c.Password__c = newPassword;
        c.User_Password__c = newPassword;
        c.Reset_OTP__c = null;
        c.Reset_OTP_Expiry__c = null;
        update c;

        resp.success = true;
        resp.message = 'Your password has been updated. You can now log in.';
        return resp;
    }

    private static String generateOtp() {
        Integer code = 100000 + Math.mod(Math.abs(Crypto.getRandomInteger()), 900000);
        return String.valueOf(code);
    }
}