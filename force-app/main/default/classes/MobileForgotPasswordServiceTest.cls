@IsTest
private class MobileForgotPasswordServiceTest {

    private static MobileForgotPasswordService.ResponseDTO callService(String action, String body) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();

        req.requestURI = '/services/apexrest/mobileForgotPassword/' + action;
        req.httpMethod = 'POST';

        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }

        RestContext.request = req;
        RestContext.response = res;

        return MobileForgotPasswordService.handleRequest();
    }

    private static Contact createTestContact(String email) {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact c = new Contact(
            FirstName = 'Test',
            LastName  = 'User',
            Email     = email,
            AccountId = acc.Id
        );
        insert c;

        return c;
    }

    @IsTest
    static void testInvalidJsonBody() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('sendOtp', '{ invalid json');

        System.assertEquals(false, resp.success);
        System.assertEquals('Invalid request body.', resp.message);
    }

    @IsTest
    static void testUnknownAction() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('unknownAction', '{}');

        System.assertEquals(false, resp.success);
        System.assertEquals('Unknown action.', resp.message);
    }

    @IsTest
    static void testSendOtpBlankEmail() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('sendOtp', '{"email":""}');

        System.assertEquals(false, resp.success);
        System.assertEquals('Please provide your email address.', resp.message);
    }

    @IsTest
    static void testSendOtpEmailNotFound() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('sendOtp', '{"email":"notfound@test.com"}');

        System.assertEquals(true, resp.success);
        System.assertEquals(
            'If that email is on file, a verification code has been sent.',
            resp.message
        );
    }

    @IsTest
    static void testSendOtpExistingEmail() {
        String email = 'forgot' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        Test.startTest();
        MobileForgotPasswordService.ResponseDTO resp =
            callService('sendOtp', '{"email":"' + email + '"}');
        Test.stopTest();

        Contact updatedContact = [
            SELECT Reset_OTP__c, Reset_OTP_Expiry__c
            FROM Contact
            WHERE Id = :c.Id
        ];

        System.assertNotEquals(null, resp);
        System.assertNotEquals(null, updatedContact.Reset_OTP__c);
        System.assertEquals(6, updatedContact.Reset_OTP__c.length());
        System.assertNotEquals(null, updatedContact.Reset_OTP_Expiry__c);
    }

    @IsTest
    static void testVerifyOtpMissingValues() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('verifyOtp', '{"email":"","otp":""}');

        System.assertEquals(false, resp.success);
        System.assertEquals('Please enter the verification code.', resp.message);
    }

    @IsTest
    static void testVerifyOtpInvalidEmail() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('verifyOtp', '{"email":"wrong@test.com","otp":"123456"}');

        System.assertEquals(false, resp.success);
        System.assertEquals('That code is invalid or has expired.', resp.message);
    }

    @IsTest
    static void testVerifyOtpInvalidCode() {
        String email = 'verifyinvalid' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(10);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService('verifyOtp', '{"email":"' + email + '","otp":"999999"}');

        System.assertEquals(false, resp.success);
        System.assertEquals('That code is invalid or has expired.', resp.message);
    }

    @IsTest
    static void testVerifyOtpExpiredCode() {
        String email = 'verifyexpired' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(-5);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService('verifyOtp', '{"email":"' + email + '","otp":"123456"}');

        System.assertEquals(false, resp.success);
        System.assertEquals('That code is invalid or has expired.', resp.message);
    }

    @IsTest
    static void testVerifyOtpSuccess() {
        String email = 'verifysuccess' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(10);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService('verifyOtp', '{"email":"' + email + '","otp":"123456"}');

        System.assertEquals(true, resp.success);
        System.assertEquals('OTP verified successfully.', resp.message);
    }

    @IsTest
    static void testResetPasswordMissingValues() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService('reset', '{"email":"","otp":"","newPassword":""}');

        System.assertEquals(false, resp.success);
        System.assertEquals('Missing required information.', resp.message);
    }

    @IsTest
    static void testResetPasswordShortPassword() {
        MobileForgotPasswordService.ResponseDTO resp =
            callService(
                'reset',
                '{"email":"test@test.com","otp":"123456","newPassword":"123"}'
            );

        System.assertEquals(false, resp.success);
        System.assertEquals('Password must be at least 8 characters.', resp.message);
    }

    @IsTest
    static void testResetPasswordInvalidOtp() {
        String email = 'resetinvalid' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(10);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService(
                'reset',
                '{"email":"' + email + '","otp":"999999","newPassword":"Password@123"}'
            );

        System.assertEquals(false, resp.success);
        System.assertEquals('That code is invalid or has expired.', resp.message);
    }

    @IsTest
    static void testResetPasswordExpiredOtp() {
        String email = 'resetexpired' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(-5);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService(
                'reset',
                '{"email":"' + email + '","otp":"123456","newPassword":"Password@123"}'
            );

        System.assertEquals(false, resp.success);
        System.assertEquals('That code is invalid or has expired.', resp.message);
    }

    @IsTest
    static void testResetPasswordSuccess() {
        String email = 'resetsuccess' + System.currentTimeMillis() + '@test.com';
        Contact c = createTestContact(email);

        c.Reset_OTP__c = '123456';
        c.Reset_OTP_Expiry__c = Datetime.now().addMinutes(10);
        update c;

        MobileForgotPasswordService.ResponseDTO resp =
            callService(
                'reset',
                '{"email":"' + email + '","otp":"123456","newPassword":"Password@123"}'
            );

        System.assertEquals(true, resp.success);
        System.assertEquals(
            'Your password has been updated. You can now log in.',
            resp.message
        );

        Contact updatedContact = [
            SELECT Password__c, User_Password__c, Reset_OTP__c, Reset_OTP_Expiry__c
            FROM Contact
            WHERE Id = :c.Id
        ];

        System.assertEquals('Password@123', updatedContact.Password__c);
        System.assertEquals('Password@123', updatedContact.User_Password__c);
        System.assertEquals(null, updatedContact.Reset_OTP__c);
        System.assertEquals(null, updatedContact.Reset_OTP_Expiry__c);
    }
}