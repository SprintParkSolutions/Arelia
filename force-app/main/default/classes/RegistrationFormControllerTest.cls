/**
 * @File Name      : RegistrationFormControllerTest.cls
 * @description    : Test class for RegistrationFormController
 *                   (email verification + lead registration).
 */
@IsTest
private class RegistrationFormControllerTest {

    // ----------------------------------------------------------------------
    // Test setup – create simple TEXT email templates
    // ----------------------------------------------------------------------
    @TestSetup
    private static void setupEmailTemplates() {
        // Use current user as "personal" email folder
        Id folderId = UserInfo.getUserId();

        // ---------- Welcome Template (for registerLead) ----------
        String welcomeDevName = System.Label.Registration_Welcome_Template_DevName;
        if (String.isBlank(welcomeDevName)) {
            welcomeDevName = 'Test_Registration_Welcome_Template';
        }

        if ([SELECT COUNT() FROM EmailTemplate WHERE DeveloperName = :welcomeDevName] == 0) {
            EmailTemplate welcomeTpl = new EmailTemplate(
                Name          = 'Test Welcome Template',
                DeveloperName = welcomeDevName,
                FolderId      = folderId,
                // Subject/body don’t need custom tokens for coverage
                Subject       = 'Welcome, {{{Recipient.Name}}}!',
                Body          = 'Hi {{{Recipient.Name}}}, your email is {{{Recipient.Email}}} and ' +
                                'phone is {{{Recipient.Phone}}}. Link: {{{ProjectRequestLink}}}',
                TemplateType  = 'text',   // no BrandTemplate / Letterhead needed
                IsActive      = true
            );
            insert welcomeTpl;
        }

        // ---------- Verification Template (for sendVerificationEmail) ----------
        String verificationDevName = System.Label.Registration_Verification_Template_DevName;
        if (String.isBlank(verificationDevName)) {
            verificationDevName = 'Test_Registration_Verification_Template';
        }

        if ([SELECT COUNT() FROM EmailTemplate WHERE DeveloperName = :verificationDevName] == 0) {
            EmailTemplate verificationTpl = new EmailTemplate(
                Name          = 'Test Verification Template',
                DeveloperName = verificationDevName,
                FolderId      = folderId,
                Subject       = 'Your verification code: {{{VerificationCode}}}',
                Body          = 'Your OTP is {{{VerificationCode}}}',
                TemplateType  = 'text',
                IsActive      = true
            );
            insert verificationTpl;
        }
    }

    // ----------------------------------------------------------------------
    // registerLead – positive
    // ----------------------------------------------------------------------
    @IsTest
    private static void testRegisterLeadSuccess() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => ' John ',
            'lastName'  => ' Doe ',
            'email'     => ' john.doe@example.com ',
            'phone'     => '9999999999'
        };

        Test.startTest();
        Id leadId = RegistrationFormController.registerLead(payload);
        Test.stopTest();

        System.assertNotEquals(null, leadId, 'Lead Id should not be null.');

        Lead createdLead = [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Lead
            WHERE Id = :leadId
        ];

        System.assertEquals('John', createdLead.FirstName, 'FirstName should be trimmed.');
        System.assertEquals('Doe', createdLead.LastName, 'LastName should be trimmed.');
        System.assertEquals('john.doe@example.com', createdLead.Email, 'Email should be trimmed.');
        System.assertEquals('9999999999', createdLead.Phone, 'Phone should match payload.');
    }

    // ----------------------------------------------------------------------
    // registerLead – negative cases
    // ----------------------------------------------------------------------
    @IsTest
    private static void testRegisterLeadNullPayload() {
        Boolean thrown = false;
        try {
            RegistrationFormController.registerLead(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for null payload.');
    }

    @IsTest
    private static void testRegisterLeadMissingName() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => '',
            'lastName'  => 'Doe',
            'email'     => 'test@example.com',
            'phone'     => '9999999999'
        };

        Boolean thrown = false;
        try {
            RegistrationFormController.registerLead(payload);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for missing first/last name.');
    }

    @IsTest
    private static void testRegisterLeadInvalidEmail() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName'  => 'Doe',
            'email'     => 'invalid-email-format',
            'phone'     => '9999999999'
        };

        Boolean thrown = false;
        try {
            RegistrationFormController.registerLead(payload);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for invalid email.');
    }

    // NEW: covers validateEmail() branch where email is BLANK
    @IsTest
    private static void testRegisterLeadBlankEmail() {
        Map<String, Object> payload = new Map<String, Object>{
            'firstName' => 'John',
            'lastName'  => 'Doe',
            'email'     => '   ',           // blank after trim
            'phone'     => '9999999999'
        };

        Boolean thrown = false;
        try {
            RegistrationFormController.registerLead(payload);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for blank email.');
    }

    // ----------------------------------------------------------------------
    // sendVerificationEmail – positive
    // ----------------------------------------------------------------------
    @IsTest
    private static void testSendVerificationEmailSuccess() {
        String email = 'verify.user@example.com';
        String otp   = '123456';

        Boolean failed = false;
        Test.startTest();
        try {
            RegistrationFormController.sendVerificationEmail(email, otp);
        } catch (Exception e) {
            failed = true;
        }
        Test.stopTest();

        System.assertEquals(false, failed, 'sendVerificationEmail should not throw an exception.');
    }

    // ----------------------------------------------------------------------
    // sendVerificationEmail – negative cases
    // ----------------------------------------------------------------------
    @IsTest
    private static void testSendVerificationEmailNoCode() {
        Boolean thrown = false;
        try {
            RegistrationFormController.sendVerificationEmail('user@example.com', '');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for blank verification code.');
    }

    @IsTest
    private static void testSendVerificationEmailInvalidEmail() {
        Boolean thrown = false;
        try {
            RegistrationFormController.sendVerificationEmail('invalid-email', '123456');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for invalid email.');
    }

    // NEW: explicitly covers validateEmail() BLANK branch for verification API
    @IsTest
    private static void testSendVerificationEmailBlankEmail() {
        Boolean thrown = false;
        try {
            RegistrationFormController.sendVerificationEmail('   ', '123456');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'AuraHandledException should be thrown for blank email.');
    }
}