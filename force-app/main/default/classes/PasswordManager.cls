/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PasswordManager
 * Author          : Arelia
 * Created Date    : Mar 24, 2026
 * Last Modified On: Mar 24, 2026
 * Description     : This class implements for......
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class PasswordManager {

    private static final Integer TOKEN_EXPIRY_HOURS = 24;
    private static final Integer MIN_PASSWORD_LENGTH = 6;

    // ============================================================
    // QUICK ACTION – Opportunity → Contact
    // ============================================================
    @AuraEnabled
    public static void sendOpportunityPasswordEmail(Id opportunityId, String mode) {

        Opportunity opp = [
            SELECT Id, Primary_Contact__c // ContactId
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (opp.Primary_Contact__c == null) {
            throw new AuraHandledException('No Contact associated.');
        }

        Contact con = [
            SELECT Id, Email
            FROM Contact
            WHERE Id = :opp.Primary_Contact__c
            LIMIT 1
        ];

        if (String.isBlank(con.Email)) {
            throw new AuraHandledException('Contact has no email.');
        }

        if (mode == 'SET') {
            handleSetPassword(con);
        }
        else if (mode == 'FORGOT') {
            handleForgotPassword(con);
        }
        else {
            throw new AuraHandledException('Invalid mode.');
        }
    }

    // ============================================================
    // SET PASSWORD FLOW
    // ============================================================
    private static void handleSetPassword(Contact con) {

        String token = generateToken(con.Id);
        String link = buildLink(token, Label.PASSWORD_RESET_PATH);

        con.Set_Password_Token__c = token;
        con.Set_Password_Expiry__c = System.now().addHours(TOKEN_EXPIRY_HOURS);
        con.Set_Password_Link__c = link;

        update con;

        sendEmail(con.Id, con.Email, Label.PASSWORD_RESET_TEMPLATE_ID);
    }

    // ============================================================
    // FORGOT PASSWORD FLOW
    // ============================================================
    private static void handleForgotPassword(Contact con) {

        String token = generateToken(con.Id);
        String link = buildLink(token, Label.FORGOT_PASSWORD_PATH);

        con.Forgot_Password_Token__c = token;
        con.Forgot_Password_Expiry__c = System.now().addHours(TOKEN_EXPIRY_HOURS);
        con.Forgot_Password_Link__c = link;

        update con;

        sendEmail(con.Id, con.Email, Label.FORGOT_PASSWORD_TEMPLATE_ID);
    }

    // ============================================================
    // SET PASSWORD PAGE ACTION
    // ============================================================
    @AuraEnabled
    public static void setPassword(String token, String newPassword) {

        validatePassword(newPassword);

        // Query list to avoid "List has no rows" error
        List<Contact> contacts = [
            SELECT Id, Set_Password_Token__c, Set_Password_Expiry__c
            FROM Contact
            WHERE Set_Password_Token__c = :token
        ];

        if (contacts.isEmpty()) {
            throw new AuraHandledException('Password has been already set or expired token.');
        }

        Contact con = contacts[0];

        if (con.Set_Password_Expiry__c < System.now()) {
            throw new AuraHandledException('Link expired.');
        }

        con.Password__c = newPassword;
        con.User_Password__c    = newPassword;
        con.Set_Password_Token__c = null;
        con.Set_Password_Expiry__c = null;
        con.Set_Password_Link__c = null;

        update con;
    }

    // ============================================================
    // RESET PASSWORD PAGE ACTION
    // ============================================================
    @AuraEnabled
    public static void resetPassword(String token, String newPassword) {

        validatePassword(newPassword);

        // Query list to avoid "List has no rows" error
        List<Contact> contacts = [
            SELECT Id, Forgot_Password_Token__c, Forgot_Password_Expiry__c
            FROM Contact
            WHERE Forgot_Password_Token__c = :token
        ];

        if (contacts.isEmpty()) {
            throw new AuraHandledException('Password has been already reset or expired token.');
        }

        Contact con = contacts[0];

        if (con.Forgot_Password_Expiry__c < System.now()) {
            throw new AuraHandledException('Link expired.');
        }

        con.Password__c = newPassword;
        con.User_Password__c    = newPassword;
        con.Forgot_Password_Token__c = null;
        con.Forgot_Password_Expiry__c = null;
        con.Forgot_Password_Link__c = null;

        update con;
    }

    @AuraEnabled
    public static String validateSetPasswordToken(String token) {

        List<Contact> contacts = [
            SELECT Id, Set_Password_Expiry__c
            FROM Contact
            WHERE Set_Password_Token__c = :token
        ];

        if (contacts.isEmpty()) {
            return 'ALREADY_USED_OR_INVALID';
        }

        if (contacts[0].Set_Password_Expiry__c < System.now()) {
            return 'EXPIRED';
        }

        return 'VALID';
    }

    @AuraEnabled
    public static String validateResetPasswordToken(String token) {

        List<Contact> contacts = [
            SELECT Id, Forgot_Password_Expiry__c
            FROM Contact
            WHERE Forgot_Password_Token__c = :token
        ];

        if (contacts.isEmpty()) {
            return 'ALREADY_USED_OR_INVALID';
        }

        if (contacts[0].Forgot_Password_Expiry__c < System.now()) {
            return 'EXPIRED';
        }

        return 'VALID';
    }

    // ============================================================
    // COMMON METHODS
    // ============================================================
    private static void validatePassword(String pwd) {
        if (String.isBlank(pwd) || pwd.length() < MIN_PASSWORD_LENGTH) {
            throw new AuraHandledException(
                'Password must be at least ' + MIN_PASSWORD_LENGTH + ' characters.'
            );
        }
    }

    private static String generateToken(Id recordId) {
        Blob hash = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(recordId + String.valueOf(System.now().getTime()))
        );
        return EncodingUtil.convertToHex(hash);
    }

    private static String buildLink(String token, String path) {
        return Label.PASSWORD_RESET_URL +
               path +
               '?token=' +
               EncodingUtil.urlEncode(token, 'UTF-8');
    }

    private static void sendEmail(Id contactId, String toEmail, String templateId) {

        Messaging.SingleEmailMessage mail =
            Messaging.renderStoredEmailTemplate(
                templateId,
                contactId,
                null
            );

        mail.setToAddresses(new List<String>{ toEmail });
        mail.setSaveAsActivity(false);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }
}