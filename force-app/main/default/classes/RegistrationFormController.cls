/**
 * @File Name      : RegistrationFormController.cls
 * @description    : Handles registration form operations - email verification and lead creation.
 * @author         : Arelia Living
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public without sharing class RegistrationFormController {

    private static final String ARELIA_LEAD_RECORD_TYPE_DEVELOPER_NAME = 'Arelia';
    private static EmailTemplate cachedVerificationTemplate;
    private static Id cachedAreliaLeadRecordTypeId;

    // ----------------------------------------------------------------------
    // Public API – Send OTP verification email
    // ----------------------------------------------------------------------

    /*
     * @description Sends an OTP verification email using the verification email template.
     * The email content is taken entirely from the template and token {{{VerificationCode}}}
     * is replaced with the runtime verificationCode.
     * @param email            Email address to which OTP should be sent.
     * @param verificationCode Generated OTP to include in the email.
     */
    @AuraEnabled
    public static void sendVerificationEmail(String email, String verificationCode) {
        try {
            validateEmail(email);
            ensureVerificationCodeProvided(verificationCode);

            EmailTemplate template = requireVerificationTemplate();
            Messaging.SingleEmailMessage msg =
                buildVerificationEmailMessage(email, verificationCode, template);

            setOrgWideAddressForGuest(msg);
            msg.setSaveAsActivity(true);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
        } catch (Exception ex) {
            throw toAuraHandledException(ex);
        }
    }

    /*
     * @description Creates a Lead record from the payload.
     * Email sending is handled from Trigger / LeadEmailHandler.
     * @param payload Map containing firstName, lastName, email, phone.
     * @return Id of the created Lead.
     */
    @AuraEnabled
    public static Id registerLead(Map<String, Object> payload) {
        try {
            return registerLeadInternal(payload);
        } catch (Exception ex) {
            throw toAuraHandledException(ex);
        }
    }

    public static Id registerLeadFromApi(Map<String, Object> payload) {
        return registerLeadInternal(payload);
    }

    private static Id registerLeadInternal(Map<String, Object> payload) {
        validatePayload(payload);

        String firstName   = (String) payload.get('firstName');
        String lastName    = (String) payload.get('lastName');
        String email       = (String) payload.get('email');
        String phone       = (String) payload.get('phone');
        String companyName = (String) payload.get('companyName');

        validateNameFields(firstName, lastName);
        validateEmail(email);

        Lead leadToInsert = buildLead(firstName, lastName, email, phone, companyName);

        assertCanCreateLead();

        Database.DMLOptions dmo = new Database.DMLOptions();
        dmo.DuplicateRuleHeader.allowSave = true;
        dmo.DuplicateRuleHeader.runAsCurrentUser = true;

        Database.SaveResult[] srList = Database.insert(
            new List<Lead>{ leadToInsert },
            dmo,
            AccessLevel.SYSTEM_MODE
        );

        if (srList == null || srList.isEmpty() || !srList[0].isSuccess()) {
            String msg = 'Failed to register. Please try again.';
            if (srList != null &&
                !srList.isEmpty() &&
                srList[0].getErrors() != null &&
                !srList[0].getErrors().isEmpty()) {
                msg = srList[0].getErrors()[0].getMessage();
            }
            throw new RegistrationFormException(msg);
        }

        return srList[0].getId();
    }

    // ----------------------------------------------------------------------
    // Verification Email Helpers
    // ----------------------------------------------------------------------

    /*
     * @description Ensures verification code is not blank.
     * @param verificationCode Generated OTP.
     */
    private static void ensureVerificationCodeProvided(String verificationCode) {
        if (String.isBlank(verificationCode)) {
            throw new RegistrationFormException('Verification code is required.');
        }
    }

    /*
     * @description Returns a verification email template and validates that it is usable.
     * @return EmailTemplate configured via custom label.
     */
    private static EmailTemplate requireVerificationTemplate() {
        EmailTemplate tpl = getVerificationTemplate();
        if (tpl == null) {
            throw new RegistrationFormException(
                'Verification email template is not configured. Please contact support.'
            );
        }

        if (String.isBlank(tpl.Body) && String.isBlank(tpl.HtmlValue)) {
            throw new RegistrationFormException(
                'Verification email template has no body. Please contact support.'
            );
        }
        return tpl;
    }

    /*
     * @description Builds the SingleEmailMessage for verification email using template
     * subject/body and replacing the {{{VerificationCode}}} token.
     * @param email            Recipient email address.
     * @param verificationCode OTP code to inject.
     * @param template         Email template used for subject and body.
     * @return SingleEmailMessage ready to be sent.
     */
    private static Messaging.SingleEmailMessage buildVerificationEmailMessage(
        String email,
        String verificationCode,
        EmailTemplate template
    ) {
        String subject = replaceVerificationToken(template.Subject, verificationCode);
        String textBody = replaceVerificationToken(template.Body, verificationCode);
        String htmlBody = replaceVerificationToken(template.HtmlValue, verificationCode);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ email.trim() });

        if (String.isNotBlank(subject)) {
            msg.setSubject(subject);
        }

        if (String.isNotBlank(htmlBody)) {
            msg.setHtmlBody(htmlBody);
        } else {
            msg.setPlainTextBody(textBody);
        }

        return msg;
    }

    /*
     * @description Replaces the verification token in a template string if present.
     * @param source           Template text.
     * @param verificationCode Verification code to inject.
     * @return String with token replaced.
     */
    private static String replaceVerificationToken(String source, String verificationCode) {
        if (String.isBlank(source)) {
            return source;
        }
        return source.replace('{{{VerificationCode}}}', verificationCode);
    }

    /*
     * @description Returns the verification email template configured via
     * custom label Registration_Verification_Template_DevName.
     * @return EmailTemplate instance or null if not found.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static EmailTemplate getVerificationTemplate() {
        if (cachedVerificationTemplate != null) {
            return cachedVerificationTemplate;
        }

        String devName = System.Label.Registration_Verification_Template_DevName;
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [
            SELECT Id, Subject, Body, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :devName
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            return null;
        }

        cachedVerificationTemplate = templates[0];
        return cachedVerificationTemplate;
    }

    // ----------------------------------------------------------------------
    // Lead Creation Helpers
    // ----------------------------------------------------------------------

    /*
     * @description Validates that payload is not null or empty.
     * @param payload Payload from LWC.
     */
    private static void validatePayload(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty()) {
            throw new RegistrationFormException('Registration payload cannot be empty.');
        }
    }

    /*
     * @description Validates that first and last name are provided.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     */
    private static void validateNameFields(String firstName, String lastName) {
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw new RegistrationFormException('First Name and Last Name are required.');
        }
    }

    /*
     * @description Validates email format.
     * @param email Email address.
     */
    private static void validateEmail(String email) {
        if (String.isBlank(email)) {
            throw new RegistrationFormException('Email is required.');
        }

        String trimmed = email.trim();
        if (!trimmed.contains('@') || !trimmed.contains('.')) {
            throw new RegistrationFormException('Please provide a valid email address.');
        }
    }

    /*
     * @description Builds a Lead instance from provided fields.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     * @param email     Lead email.
     * @param phone     Lead phone.
     * @param companyName Lead company name.
     * @return Lead record (not yet inserted).
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Lead buildLead(
        String firstName,
        String lastName,
        String email,
        String phone,
        String companyName
    ) {
        String finalCompany = String.isBlank(companyName)
            ? 'Self-' + firstName + ' ' + lastName
            : companyName.trim();
        Id leadRecordTypeId = getAreliaLeadRecordTypeId();

        return new Lead(
            RecordTypeId = leadRecordTypeId,
            FirstName = firstName != null ? firstName.trim() : null,
            LastName  = lastName != null ? lastName.trim() : null,
            Email     = email != null ? email.trim() : null,
            Phone     = phone,
            Company   = finalCompany
        );
    }

    /*
     * @description Returns the Lead Record Type Id for the Arelia lead flow.
     * @return Lead RecordType Id.
     */
    private static Id getAreliaLeadRecordTypeId() {
        if (cachedAreliaLeadRecordTypeId != null) {
            return cachedAreliaLeadRecordTypeId;
        }

        Schema.RecordTypeInfo leadRecordTypeInfo = Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get(ARELIA_LEAD_RECORD_TYPE_DEVELOPER_NAME);

        if (leadRecordTypeInfo == null) {
            throw new RegistrationFormException(
                'Arelia Lead record type is not available. Please contact support.'
            );
        }

        cachedAreliaLeadRecordTypeId = leadRecordTypeInfo.getRecordTypeId();
        return cachedAreliaLeadRecordTypeId;
    }

    /*
     * @description Ensures the running user has create permission on Lead.
     */
    private static void assertCanCreateLead() {
        if (!Schema.sObjectType.Lead.isCreateable()) {
            throw new RegistrationFormException(
                'You do not have permission to create Lead records.'
            );
        }
    }

    private static AuraHandledException toAuraHandledException(Exception ex) {
        return new AuraHandledException(ex == null ? 'Unexpected error occurred.' : ex.getMessage());
    }

    public class RegistrationFormException extends Exception {}

    // ----------------------------------------------------------------------
    // Org-Wide Email Helper
    // ----------------------------------------------------------------------

    /*
     * @description Sets Org-Wide Email Address Id for guest users.
     * @param msg Email message to update.
     */
    private static void setOrgWideAddressForGuest(Messaging.SingleEmailMessage msg) {
        if (msg == null) {
            return;
        }

        Id orgWideId = getOrgWideEmailAddressId();
        if (orgWideId != null) {
            msg.setOrgWideEmailAddressId(orgWideId);
        }
    }

    /*
     * @description Gets Org-Wide Email Address ID used for outbound emails.
     */
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
                            WHERE Address = :Label.Arelia_OWD LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }
}