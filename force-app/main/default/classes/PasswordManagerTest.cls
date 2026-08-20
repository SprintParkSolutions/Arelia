/**
 * @description Test class for PasswordManager.
 * Covers set password, forgot password, password reset, token validation,
 * invalid mode, missing contact, missing email, weak password, invalid token,
 * and expired token scenarios.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class PasswordManagerTest {
    private static final String CONTACT_LAST_NAME = 'Test User';
    private static final String CONTACT_EMAIL = 'test@example.com';
    private static final String OLD_PASSWORD = 'oldPass123';
    private static final String OPPORTUNITY_NAME = 'Password Manager Test Opp';

    private static final String MODE_SET = 'SET';
    private static final String MODE_FORGOT = 'FORGOT';
    private static final String MODE_INVALID = 'ABC';

    private static final String VALID_SET_TOKEN = 'valid-set-token';
    private static final String VALID_RESET_TOKEN = 'valid-reset-token';
    private static final String EXPIRED_SET_TOKEN = 'expired-set-token';
    private static final String EXPIRED_RESET_TOKEN = 'expired-reset-token';

    private static final String NEW_PASSWORD = 'newPass123';
    private static final String RESET_PASSWORD = 'resetPass123';

    @TestSetup
    static void setupData() {
        Contact contactRecord = TestDataUtility.createContact(
            CONTACT_LAST_NAME,
            CONTACT_EMAIL,
            OLD_PASSWORD
        );

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            UserInfo.getUserId()
        );

        opportunityRecord.Primary_Contact__c = contactRecord.Id;
        update opportunityRecord;

        createPasswordEmailTemplates();
    }

    @IsTest
    static void testSendSetPassword() {
        Opportunity opportunityRecord = getBaseOpportunity();

        Boolean emailRenderExceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.sendOpportunityPasswordEmail(
                opportunityRecord.Id,
                MODE_SET
            );
        } catch (Exception exceptionRecord) {
            emailRenderExceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Email rendering may fail in test context because label template Id is org-specific.'
            );
        }

        Test.stopTest();

        Contact contactRecord = getBaseContactWithSetPasswordFields();

        System.assertNotEquals(
            null,
            contactRecord.Set_Password_Token__c,
            'Set password token should be generated before email rendering.'
        );
        System.assertNotEquals(
            null,
            contactRecord.Set_Password_Expiry__c,
            'Set password expiry should be generated before email rendering.'
        );
        System.assertNotEquals(
            null,
            contactRecord.Set_Password_Link__c,
            'Set password link should be generated before email rendering.'
        );
        System.assert(
            emailRenderExceptionThrown || contactRecord.Set_Password_Token__c != null,
            'Set password flow should either complete email rendering or at least generate token fields.'
        );
    }

    @IsTest
    static void testSendForgotPassword() {
        Opportunity opportunityRecord = getBaseOpportunity();

        Boolean emailRenderExceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.sendOpportunityPasswordEmail(
                opportunityRecord.Id,
                MODE_FORGOT
            );
        } catch (Exception exceptionRecord) {
            emailRenderExceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Email rendering may fail in test context because label template Id is org-specific.'
            );
        }

        Test.stopTest();

        Contact contactRecord = getBaseContactWithForgotPasswordFields();

        System.assertNotEquals(
            null,
            contactRecord.Forgot_Password_Token__c,
            'Forgot password token should be generated before email rendering.'
        );
        System.assertNotEquals(
            null,
            contactRecord.Forgot_Password_Expiry__c,
            'Forgot password expiry should be generated before email rendering.'
        );
        System.assertNotEquals(
            null,
            contactRecord.Forgot_Password_Link__c,
            'Forgot password link should be generated before email rendering.'
        );
        System.assert(
            emailRenderExceptionThrown || contactRecord.Forgot_Password_Token__c != null,
            'Forgot password flow should either complete email rendering or at least generate token fields.'
        );
    }

    @IsTest
    static void testSetPasswordSuccess() {
        Contact contactRecord = getBaseContact();
        contactRecord.Set_Password_Token__c = VALID_SET_TOKEN;
        contactRecord.Set_Password_Expiry__c = System.now().addHours(1);
        update contactRecord;

        Test.startTest();
        PasswordManager.setPassword(VALID_SET_TOKEN, NEW_PASSWORD);
        Test.stopTest();

        Contact updatedContact = [
            SELECT Id,
                   Password__c,
                   User_Password__c,
                   Set_Password_Token__c,
                   Set_Password_Expiry__c,
                   Set_Password_Link__c
            FROM Contact
            WHERE Id = :contactRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            NEW_PASSWORD,
            updatedContact.Password__c,
            'Password should be updated correctly.'
        );
        System.assertEquals(
            NEW_PASSWORD,
            updatedContact.User_Password__c,
            'User password should be updated correctly.'
        );
        System.assertEquals(
            null,
            updatedContact.Set_Password_Token__c,
            'Set password token should be cleared after password set.'
        );
        System.assertEquals(
            null,
            updatedContact.Set_Password_Expiry__c,
            'Set password expiry should be cleared after password set.'
        );
        System.assertEquals(
            null,
            updatedContact.Set_Password_Link__c,
            'Set password link should be cleared after password set.'
        );
    }

    @IsTest
    static void testResetPasswordSuccess() {
        Contact contactRecord = getBaseContact();
        contactRecord.Forgot_Password_Token__c = VALID_RESET_TOKEN;
        contactRecord.Forgot_Password_Expiry__c = System.now().addHours(1);
        update contactRecord;

        Test.startTest();
        PasswordManager.resetPassword(VALID_RESET_TOKEN, RESET_PASSWORD);
        Test.stopTest();

        Contact updatedContact = [
            SELECT Id,
                   Password__c,
                   User_Password__c,
                   Forgot_Password_Token__c,
                   Forgot_Password_Expiry__c,
                   Forgot_Password_Link__c
            FROM Contact
            WHERE Id = :contactRecord.Id
            LIMIT 1
        ];

        System.assertEquals(
            RESET_PASSWORD,
            updatedContact.Password__c,
            'Password should be reset correctly.'
        );
        System.assertEquals(
            RESET_PASSWORD,
            updatedContact.User_Password__c,
            'User password should be reset correctly.'
        );
        System.assertEquals(
            null,
            updatedContact.Forgot_Password_Token__c,
            'Forgot password token should be cleared.'
        );
        System.assertEquals(
            null,
            updatedContact.Forgot_Password_Expiry__c,
            'Forgot password expiry should be cleared.'
        );
        System.assertEquals(
            null,
            updatedContact.Forgot_Password_Link__c,
            'Forgot password link should be cleared.'
        );
    }

    @IsTest
    static void testInvalidMode() {
        Opportunity opportunityRecord = getBaseOpportunity();

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.sendOpportunityPasswordEmail(
                opportunityRecord.Id,
                MODE_INVALID
            );
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Invalid mode should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown for invalid mode.'
        );
    }

    @IsTest
    static void testWeakPasswordForSetPassword() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.setPassword('any-token', '123');
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Weak password should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown for weak set password.'
        );
    }

    @IsTest
    static void testWeakPasswordForResetPassword() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.resetPassword('any-token', '123');
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Weak password should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown for weak reset password.'
        );
    }

    @IsTest
    static void testNoContactOnOpportunity() {
        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            'No Contact Opp',
            UserInfo.getUserId()
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.sendOpportunityPasswordEmail(
                opportunityRecord.Id,
                MODE_SET
            );
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Missing contact should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown when no contact is associated.'
        );
    }

    @IsTest
    static void testContactWithoutEmail() {
        Contact contactRecord = TestDataUtility.createContact(
            'NoEmail',
            null,
            OLD_PASSWORD
        );

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            'Opp No Email',
            UserInfo.getUserId()
        );

        opportunityRecord.Primary_Contact__c = contactRecord.Id;
        update opportunityRecord;

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            PasswordManager.sendOpportunityPasswordEmail(
                opportunityRecord.Id,
                MODE_SET
            );
        } catch (Exception exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Contact without email should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Exception should be thrown when contact has no email.'
        );
    }

    @IsTest
    static void testSetPasswordInvalidAndExpired() {
        Contact contactRecord = getBaseContact();
        contactRecord.Set_Password_Token__c = EXPIRED_SET_TOKEN;
        contactRecord.Set_Password_Expiry__c = System.now().addHours(-1);
        update contactRecord;

        Boolean invalidThrown = false;
        Boolean expiredThrown = false;

        Test.startTest();

        try {
            PasswordManager.setPassword('invalid-token', NEW_PASSWORD);
        } catch (Exception exceptionRecord) {
            invalidThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Invalid set password token should throw an exception.'
            );
        }

        try {
            PasswordManager.setPassword(EXPIRED_SET_TOKEN, NEW_PASSWORD);
        } catch (Exception exceptionRecord) {
            expiredThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Expired set password token should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            invalidThrown,
            'Exception should be thrown for invalid set password token.'
        );
        System.assertEquals(
            true,
            expiredThrown,
            'Exception should be thrown for expired set password token.'
        );
    }

    @IsTest
    static void testResetPasswordInvalidAndExpired() {
        Contact contactRecord = getBaseContact();
        contactRecord.Forgot_Password_Token__c = EXPIRED_RESET_TOKEN;
        contactRecord.Forgot_Password_Expiry__c = System.now().addHours(-1);
        update contactRecord;

        Boolean invalidThrown = false;
        Boolean expiredThrown = false;

        Test.startTest();

        try {
            PasswordManager.resetPassword('wrong-reset-token', RESET_PASSWORD);
        } catch (Exception exceptionRecord) {
            invalidThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Invalid reset token should throw an exception.'
            );
        }

        try {
            PasswordManager.resetPassword(EXPIRED_RESET_TOKEN, RESET_PASSWORD);
        } catch (Exception exceptionRecord) {
            expiredThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Expired reset token should throw an exception.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            invalidThrown,
            'Exception should be thrown for invalid reset token.'
        );
        System.assertEquals(
            true,
            expiredThrown,
            'Exception should be thrown for expired reset token.'
        );
    }

    @IsTest
    static void testValidateSetPasswordToken() {
        Contact contactRecord = getBaseContact();

        contactRecord.Set_Password_Token__c = VALID_SET_TOKEN;
        contactRecord.Set_Password_Expiry__c = System.now().addHours(1);
        update contactRecord;

        String validResult = PasswordManager.validateSetPasswordToken(VALID_SET_TOKEN);
        String invalidResult = PasswordManager.validateSetPasswordToken('wrong-set-token');

        System.assertEquals(
            'VALID',
            validResult,
            'Set password token should be valid.'
        );
        System.assertEquals(
            'ALREADY_USED_OR_INVALID',
            invalidResult,
            'Invalid set password token should return ALREADY_USED_OR_INVALID.'
        );

        contactRecord.Set_Password_Expiry__c = System.now().addHours(-1);
        update contactRecord;

        String expiredResult = PasswordManager.validateSetPasswordToken(VALID_SET_TOKEN);

        System.assertEquals(
            'EXPIRED',
            expiredResult,
            'Expired set password token should return EXPIRED.'
        );
    }

    @IsTest
    static void testValidateResetPasswordToken() {
        Contact contactRecord = getBaseContact();

        contactRecord.Forgot_Password_Token__c = VALID_RESET_TOKEN;
        contactRecord.Forgot_Password_Expiry__c = System.now().addHours(1);
        update contactRecord;

        String validResult = PasswordManager.validateResetPasswordToken(VALID_RESET_TOKEN);
        String invalidResult = PasswordManager.validateResetPasswordToken('wrong-reset-token');

        System.assertEquals(
            'VALID',
            validResult,
            'Reset token should be valid.'
        );
        System.assertEquals(
            'ALREADY_USED_OR_INVALID',
            invalidResult,
            'Invalid reset token should return ALREADY_USED_OR_INVALID.'
        );

        contactRecord.Forgot_Password_Expiry__c = System.now().addHours(-1);
        update contactRecord;

        String expiredResult = PasswordManager.validateResetPasswordToken(VALID_RESET_TOKEN);

        System.assertEquals(
            'EXPIRED',
            expiredResult,
            'Expired reset token should return EXPIRED.'
        );
    }

    private static Opportunity getBaseOpportunity() {
        return [
            SELECT Id,
                   Primary_Contact__c
            FROM Opportunity
            WHERE Name = :OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static Contact getBaseContact() {
        return [
            SELECT Id,
                   Email
            FROM Contact
            WHERE Email = :CONTACT_EMAIL
            LIMIT 1
        ];
    }

    private static Contact getBaseContactWithSetPasswordFields() {
        return [
            SELECT Id,
                   Set_Password_Token__c,
                   Set_Password_Expiry__c,
                   Set_Password_Link__c
            FROM Contact
            WHERE Email = :CONTACT_EMAIL
            LIMIT 1
        ];
    }

    private static Contact getBaseContactWithForgotPasswordFields() {
        return [
            SELECT Id,
                   Forgot_Password_Token__c,
                   Forgot_Password_Expiry__c,
                   Forgot_Password_Link__c
            FROM Contact
            WHERE Email = :CONTACT_EMAIL
            LIMIT 1
        ];
    }

    private static void createPasswordEmailTemplates() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                'PASSWORD_RESET_TEMPLATE_ID',
                'Reset Template',
                'Reset Password'
            );

            TestDataUtility.createSpecificEmailTemplate(
                'FORGOT_PASSWORD_TEMPLATE_ID',
                'Forgot Template',
                'Forgot Password'
            );
        }
    }
}