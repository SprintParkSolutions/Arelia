@isTest
@SuppressWarnings('PMD.ExcessivePublicCount')
public class PasswordManagerTest {

    @testSetup
    static void setupData() {

        // NON-SETUP OBJECTS
        Contact con = TestDataUtility.createContact(
            'Test User',
            'test@example.com',
            'oldPass123'
        );

        Opportunity opp = TestDataUtility.createOpportunity(
            'Test Opp',
            UserInfo.getUserId()
        );

        opp.Primary_Contact__c = con.Id;
        update opp;

        // SETUP OBJECTS (avoid Mixed DML)
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

    // ============================================
    // POSITIVE FLOWS
    // ============================================

    @isTest
    static void testSendSetPassword() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        PasswordManager.sendOpportunityPasswordEmail(opp.Id, 'SET');
        Test.stopTest();

        Contact con = [SELECT Set_Password_Token__c FROM Contact LIMIT 1];

        System.assertNotEquals(
            null,
            con.Set_Password_Token__c,
            'Set password token should be generated'
        );
    }

    @isTest
    static void testSendForgotPassword() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        PasswordManager.sendOpportunityPasswordEmail(opp.Id, 'FORGOT');
        Test.stopTest();

        Contact con = [SELECT Forgot_Password_Token__c FROM Contact LIMIT 1];

        System.assertNotEquals(
            null,
            con.Forgot_Password_Token__c,
            'Forgot password token should be generated'
        );
    }

    @isTest
    static void testSetPasswordSuccess() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        con.Set_Password_Token__c = 'token123';
        con.Set_Password_Expiry__c = System.now().addHours(1);
        update con;

        PasswordManager.setPassword('token123', 'newPass123');

        Contact updated = [
            SELECT Password__c, Set_Password_Token__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertEquals(
            'newPass123',
            updated.Password__c,
            'Password should be updated correctly'
        );

        System.assertEquals(
            null,
            updated.Set_Password_Token__c,
            'Token should be cleared after password set'
        );
    }

    @isTest
    static void testResetPasswordSuccess() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        con.Forgot_Password_Token__c = 'reset123';
        con.Forgot_Password_Expiry__c = System.now().addHours(1);
        update con;

        PasswordManager.resetPassword('reset123', 'resetPass123');

        Contact updated = [
            SELECT Password__c, Forgot_Password_Token__c
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertEquals(
            'resetPass123',
            updated.Password__c,
            'Password should be reset correctly'
        );

        System.assertEquals(
            null,
            updated.Forgot_Password_Token__c,
            'Forgot password token should be cleared'
        );
    }

    // ============================================
    // NEGATIVE FLOWS
    // ============================================

    @isTest
    static void testInvalidMode() {

        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Boolean isExceptionThrown = false;

        try {
            PasswordManager.sendOpportunityPasswordEmail(opp.Id, 'ABC');
        } catch (Exception e) {
            isExceptionThrown = true;
        }

        System.assert(
            isExceptionThrown,
            'Exception should be thrown for invalid mode'
        );
    }

    @isTest
    static void testWeakPassword() {

        Boolean isExceptionThrown = false;

        try {
            PasswordManager.setPassword('any', '123');
        } catch (Exception e) {
            isExceptionThrown = true;
        }

        System.assert(
            isExceptionThrown,
            'Exception should be thrown for weak password'
        );
    }

    @isTest
    static void testNoContactOnOpportunity() {

        Opportunity opp = TestDataUtility.createOpportunity(
            'No Contact Opp',
            UserInfo.getUserId()
        );

        Boolean isExceptionThrown = false;

        try {
            PasswordManager.sendOpportunityPasswordEmail(opp.Id, 'SET');
        } catch (Exception e) {
            isExceptionThrown = true;
        }

        System.assert(
            isExceptionThrown,
            'Exception should be thrown when no contact is associated'
        );
    }

    @isTest
    static void testContactWithoutEmail() {

        Contact con = TestDataUtility.createContact('NoEmail', null, 'pass123');

        Opportunity opp = TestDataUtility.createOpportunity(
            'Opp No Email',
            UserInfo.getUserId()
        );

        opp.Primary_Contact__c = con.Id;
        update opp;

        Boolean isExceptionThrown = false;

        try {
            PasswordManager.sendOpportunityPasswordEmail(opp.Id, 'SET');
        } catch (Exception e) {
            isExceptionThrown = true;
        }

        System.assert(
            isExceptionThrown,
            'Exception should be thrown when contact has no email'
        );
    }

    @isTest
    static void testSetPasswordInvalidAndExpired() {

        // INVALID TOKEN
        Boolean invalidThrown = false;

        try {
            PasswordManager.setPassword('invalidToken', 'validPass123');
        } catch (Exception e) {
            invalidThrown = true;
        }

        System.assert(
            invalidThrown,
            'Exception should be thrown for invalid token'
        );

        // EXPIRED TOKEN
        Contact con = [SELECT Id FROM Contact LIMIT 1];

        con.Set_Password_Token__c = 'expiredToken';
        con.Set_Password_Expiry__c = System.now().addHours(-1);
        update con;

        Boolean expiredThrown = false;

        try {
            PasswordManager.setPassword('expiredToken', 'validPass123');
        } catch (Exception e) {
            expiredThrown = true;
        }

        System.assert(
            expiredThrown,
            'Exception should be thrown for expired token'
        );
    }

    @isTest
    static void testResetPasswordInvalidAndExpired() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        // INVALID TOKEN
        Boolean invalidThrown = false;

        try {
            PasswordManager.resetPassword('wrongToken', 'pass1234');
        } catch (Exception e) {
            invalidThrown = true;
        }

        System.assert(
            invalidThrown,
            'Exception should be thrown for invalid reset token'
        );

        // EXPIRED TOKEN
        con.Forgot_Password_Token__c = 'expiredReset';
        con.Forgot_Password_Expiry__c = System.now().addHours(-1);
        update con;

        Boolean expiredThrown = false;

        try {
            PasswordManager.resetPassword('expiredReset', 'pass1234');
        } catch (Exception e) {
            expiredThrown = true;
        }

        System.assert(
            expiredThrown,
            'Exception should be thrown for expired reset token'
        );
    }

    // ============================================
    // TOKEN VALIDATION
    // ============================================

    @isTest
    static void testValidateTokens() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        con.Set_Password_Token__c = 'valid';
        con.Set_Password_Expiry__c = System.now().addHours(1);
        update con;

        System.assertEquals(
            'VALID',
            PasswordManager.validateSetPasswordToken('valid'),
            'Token should be valid'
        );

        System.assertEquals(
            'ALREADY_USED_OR_INVALID',
            PasswordManager.validateSetPasswordToken('wrong'),
            'Invalid token should return ALREADY_USED_OR_INVALID'
        );

        con.Set_Password_Expiry__c = System.now().addHours(-1);
        update con;

        System.assertEquals(
            'EXPIRED',
            PasswordManager.validateSetPasswordToken('valid'),
            'Expired token should return EXPIRED'
        );
    }

    @isTest
    static void testValidateResetToken() {

        Contact con = [SELECT Id FROM Contact LIMIT 1];

        con.Forgot_Password_Token__c = 'validReset';
        con.Forgot_Password_Expiry__c = System.now().addHours(1);
        update con;

        System.assertEquals(
            'VALID',
            PasswordManager.validateResetPasswordToken('validReset'),
            'Reset token should be valid'
        );

        System.assertEquals(
            'ALREADY_USED_OR_INVALID',
            PasswordManager.validateResetPasswordToken('wrong'),
            'Invalid reset token should return ALREADY_USED_OR_INVALID'
        );

        con.Forgot_Password_Expiry__c = System.now().addHours(-1);
        update con;

        System.assertEquals(
            'EXPIRED',
            PasswordManager.validateResetPasswordToken('validReset'),
            'Expired reset token should return EXPIRED'
        );
    }
}