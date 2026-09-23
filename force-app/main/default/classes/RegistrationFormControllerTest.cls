@IsTest
private class RegistrationFormControllerTest {

    @TestSetup
    static void setupData() {
        Id folderId = UserInfo.getUserId();

        String verificationDevName = System.Label.Registration_Verification_Template_DevName;
        if (String.isBlank(verificationDevName)) {
            verificationDevName = 'Test_Registration_Verification_Template';
        }

        List<EmailTemplate> existingTemplates = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :verificationDevName
        ];

        if (existingTemplates.isEmpty()) {
            EmailTemplate verificationTpl = new EmailTemplate(
                Name = 'Test Verification Template',
                DeveloperName = verificationDevName,
                FolderId = folderId,
                TemplateType = 'text',
                Subject = 'Your verification code: {{{VerificationCode}}}',
                Body = 'Your OTP is {{{VerificationCode}}}',
                IsActive = true
            );
            insert verificationTpl;
        }
    }

    @IsTest
    static void testRegisterLeadSuccess() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => ' John ',
            'lastName' => ' Doe ',
            'email' => ' john.doe@example.com ',
            'phone' => '+91 9999999999',
            'companyName' => ' Test Company '
        };

        Test.startTest();
        Id leadId = RegistrationFormController.registerLead(payload);
        Test.stopTest();

        System.assertNotEquals(null, leadId);

        Lead createdLead = [
            SELECT Id, FirstName, LastName, Email, Phone, Company
            FROM Lead
            WHERE Id = :leadId
        ];

        System.assertEquals('John', createdLead.FirstName);
        System.assertEquals('Doe', createdLead.LastName);
        System.assertEquals('john.doe@example.com', createdLead.Email);
        System.assertEquals('+91 9999999999', createdLead.Phone);
        System.assertEquals('Test Company', createdLead.Company);
    }

    @IsTest
    static void testRegisterLeadSuccessWithDefaultCompany() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'Naresh',
            'lastName' => 'Punagani',
            'email' => 'naresh@example.com',
            'phone' => '9999999999',
            'companyName' => ''
        };

        Test.startTest();
        Id leadId = RegistrationFormController.registerLead(payload);
        Test.stopTest();

        Lead createdLead = [
            SELECT Id, Company
            FROM Lead
            WHERE Id = :leadId
        ];

        System.assertEquals('Self-Naresh Punagani', createdLead.Company);
    }

    @IsTest
    static void testRegisterLeadDmlFailure() {
        String longLastName = '';
        for (Integer i = 0; i < 100; i++) {
            longLastName += 'A';
        }

        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => longLastName,
            'email' => 'john.dmlfailure@example.com',
            'phone' => '9999999999',
            'companyName' => 'Test Company'
        };

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            RegistrationFormController.registerLead(payload);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadNullPayload() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadEmptyPayload() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(new Map<String, Object>());
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadMissingFirstName() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => '',
            'lastName' => 'Doe',
            'email' => 'john@example.com',
            'phone' => '9999999999'
        };

        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(payload);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadMissingLastName() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => '',
            'email' => 'john@example.com',
            'phone' => '9999999999'
        };

        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(payload);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadBlankEmail() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => 'Doe',
            'email' => '   ',
            'phone' => '9999999999'
        };

        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(payload);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testRegisterLeadInvalidEmail() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => 'Doe',
            'email' => 'invalid-email',
            'phone' => '9999999999'
        };

        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.registerLead(payload);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSendVerificationEmailSuccess() {
        Boolean failed = false;

        Test.startTest();
        try {
            RegistrationFormController.sendVerificationEmail('verify.user@example.com', '123456');
        } catch (Exception e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(false, failed);
    }

    @IsTest
    static void testSendVerificationEmailSuccessWithTrimmedEmail() {
        Boolean failed = false;

        Test.startTest();
        try {
            RegistrationFormController.sendVerificationEmail('  verify.trim@example.com  ', '654321');
        } catch (Exception e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(false, failed);
    }

    @IsTest
    static void testSendVerificationEmailBlankCode() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.sendVerificationEmail('user@example.com', '');
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSendVerificationEmailNullCode() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.sendVerificationEmail('user@example.com', null);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSendVerificationEmailBlankEmail() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.sendVerificationEmail('   ', '123456');
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }

    @IsTest
    static void testSendVerificationEmailInvalidEmail() {
        Boolean exceptionThrown = false;

        try {
            RegistrationFormController.sendVerificationEmail('invalid-email', '123456');
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }
}