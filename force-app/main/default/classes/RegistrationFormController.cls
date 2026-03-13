/**
 * @File Name      : RegistrationFormController.cls
 * @description    : Handles registration form operations - email verification and lead creation.
 * @author         : Arelia Living
 */
@SuppressWarnings('PMD.CognitiveComplexity')
public without sharing class RegistrationFormController {

    private static Id cachedWelcomeTemplateId;
    private static EmailTemplate cachedVerificationTemplate;

    // ----------------------------------------------------------------------
    // Public API – Send OTP verification email (template only)
    // ----------------------------------------------------------------------

    /**
     * @description Sends an OTP verification email using the verification email template.
     * The email content is taken entirely from the template and token {{{VerificationCode}}}
     * is replaced with the runtime verificationCode.
     * @param email            Email address to which OTP should be sent.
     * @param verificationCode Generated OTP to include in the email.
     */
    @AuraEnabled
    public static void sendVerificationEmail(String email, String verificationCode) {
        validateEmail(email);
        ensureVerificationCodeProvided(verificationCode);

        EmailTemplate template = requireVerificationTemplate();
        Messaging.SingleEmailMessage msg =
            buildVerificationEmailMessage(email, verificationCode, template);

        setOrgWideAddressForGuest(msg);
        msg.setSaveAsActivity(true);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }

    /**
     * @description Ensures verification code is not blank.
     * @param verificationCode Generated OTP.
     */
    private static void ensureVerificationCodeProvided(String verificationCode) {
        if (String.isBlank(verificationCode)) {
            throw new AuraHandledException('Verification code is required.');
        }
    }

    /**
     * @description Returns a verification email template and validates that it is usable.
     * @return EmailTemplate configured via custom label.
     */
    private static EmailTemplate requireVerificationTemplate() {
        EmailTemplate tpl = getVerificationTemplate();
        if (tpl == null) {
            // Config issue only; no fallback body
            throw new AuraHandledException(
                'Verification email template is not configured. Please contact support.'
            );
        }

        // Template MUST have some body
        if (String.isBlank(tpl.Body) && String.isBlank(tpl.HtmlValue)) {
            throw new AuraHandledException(
                'Verification email template has no body. Please contact support.'
            );
        }
        return tpl;
    }

    /**
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

        // Prefer HTML body when present; otherwise send plain text.
        if (String.isNotBlank(htmlBody)) {
            msg.setHtmlBody(htmlBody);
        } else {
            msg.setPlainTextBody(textBody);
            //System.debug('Hello');
        }

        return msg;
    }

    /**
     * @description Replaces the verification token in a template string if present.
     * @param source           Template text (may be null or blank).
     * @param verificationCode Verification code to inject.
     * @return String with token replaced, or original value when blank.
     */
    private static String replaceVerificationToken(String source, String verificationCode) {
        if (String.isBlank(source)) {
            return source;
        }
        return source.replace('{{{VerificationCode}}}', verificationCode);
    }

    // ----------------------------------------------------------------------
    // Public API – Create Lead and send welcome email (template only)
    // ----------------------------------------------------------------------

    /**
     * @description Creates a Lead record from the payload and sends a welcome email
     * using the configured welcome template.
     * @param payload Map containing firstName, lastName, email, phone.
     * @return Id of the created Lead.
     */
    
    @AuraEnabled
    public static Id registerLead(Map<String, Object> payload) {
        validatePayload(payload);

        String firstName   = (String)payload.get('firstName');
        String lastName    = (String)payload.get('lastName');
        String email       = (String)payload.get('email');
        String phone       = (String)payload.get('phone');
        String companyName = (String)payload.get('companyName');

        validateNameFields(firstName, lastName);
        validateEmail(email);

        Lead leadToInsert = buildLead(firstName, lastName, email, phone, companyName);

        assertCanCreateLead();

        // ✅ DMLOptions to allow duplicates (same as UI "Similar Records Exist" warning)
        Database.DMLOptions dmo = new Database.DMLOptions();
        dmo.DuplicateRuleHeader.allowSave = true;           // do not block on duplicates
        dmo.DuplicateRuleHeader.runAsCurrentUser = true;    // evaluate like UI/current user

        // ✅ Most reliable insert signature: Database.insert(list, dmlOptions, accessLevel)
        Database.SaveResult[] srList = Database.insert(new List<Lead>{ leadToInsert }, dmo,AccessLevel.SYSTEM_MODE);

        if (srList == null || srList.isEmpty() || !srList[0].isSuccess()) {
            // surface the real error message back to LWC
            String msg = 'Failed to register. Please try again.';
            if (srList != null && !srList.isEmpty() && srList[0].getErrors() != null && srList[0].getErrors().size() > 0) {
                msg = srList[0].getErrors()[0].getMessage();
            }
            throw new AuraHandledException(msg);
        }

        Id leadId = srList[0].getId();

        // keep your existing email logic
        leadToInsert.Id = leadId;
        sendWelcomeEmailSafely(leadToInsert);

        return leadId;
    }


    /**
     * @description Validates that payload is not null or empty.
     * @param payload Payload from LWC.
     */
    private static void validatePayload(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty()) {
            throw new AuraHandledException('Registration payload cannot be empty.');
        }
    }

    /**
     * @description Validates that first and last name are provided.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     */
    private static void validateNameFields(String firstName, String lastName) {
        if (String.isBlank(firstName) || String.isBlank(lastName)) {
            throw new AuraHandledException('First Name and Last Name are required.');
        }
    }

    /**
     * @description Builds a Lead instance from provided fields.
     * @param firstName Lead first name.
     * @param lastName  Lead last name.
     * @param email     Lead email.
     * @param phone     Lead phone.
     * @return Lead record (not yet inserted).
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static Lead buildLead(String firstName,String lastName,String email,String phone, String companyName)
    {
        String finalCompany = String.isBlank(companyName) ? 'Self-'+firstName+' '+lastName : companyName.trim();
        return new Lead(
            FirstName = firstName != null ? firstName.trim() : null,
            LastName  = lastName != null ? lastName.trim() : null,
            Email     = email != null ? email.trim() : null,
            Phone     = phone,
            Company   = finalCompany
        );
    }

    /**
     * @description Sends welcome email and swallows any exception (email failure
     * should not block registration).
     * @param leadRecord Inserted Lead record.
     */
    private static void sendWelcomeEmailSafely(Lead leadRecord) {
        try {
             // 1) Customer welcome email
            sendWelcomeEmail(leadRecord);

            // 2) Internal notification to enrollment team
            sendEnrollmentNotification(leadRecord);
        } catch (Exception ex) {
            System.debug('Custom Exception occurred: ' + ex.getMessage());
            // Intentionally ignore email failure – registration succeeded.
        }
    }

    // ----------------------------------------------------------------------
    // Private – Welcome email using template (DeveloperName from label)
    // ----------------------------------------------------------------------

    /**
     * @description Sends a welcome email to the provided Lead using the welcome template.
     * @param leadRecord Lead that will receive the email.
     */
    private static void sendWelcomeEmail(Lead leadRecord) {
        if (leadRecord == null || leadRecord.Id == null || String.isBlank(leadRecord.Email)) {
            return;
        }

        EmailTemplate template = getWelcomeTemplate();
        if (template == null) {
            return;
        }

        // Build link: label + ?id=<leadId>
        String projectRequestLink = Label.Arelia_Site_Label + Label.Arelia_Project_Request_Page_URL + '?id=' + leadRecord.Id;

        // Build recipient name
        String leadName = ((leadRecord.FirstName != null ? leadRecord.FirstName + ' ' : '')
                        + leadRecord.LastName);

        WelcomeTokenData data = new WelcomeTokenData();
        data.name        = leadName;
        data.email       = leadRecord.Email;
        data.phone       = leadRecord.Phone;
        data.projectLink = projectRequestLink;

        String subject  = template.Subject;
        String textBody = template.Body;
        String htmlBody = template.HtmlValue;

        subject  = replaceWelcomeTokens(subject,  data);
        textBody = replaceWelcomeTokens(textBody, data);
        htmlBody = replaceWelcomeTokens(htmlBody, data);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();

        // 🔹 IMPORTANT: relate email to the Lead so it appears in Activity
        msg.setTargetObjectId(leadRecord.Id);
        msg.setTreatTargetObjectAsRecipient(true); // Lead is the actual recipient

        // (Optional, but fine to keep)
        msg.setToAddresses(new List<String>{ leadRecord.Email });

        if (String.isNotBlank(subject)) {
            msg.setSubject(subject);
        }

        if (String.isNotBlank(htmlBody)) {
            msg.setHtmlBody(htmlBody);
        } else {
            msg.setPlainTextBody(textBody);
        }

        msg.setSaveAsActivity(true);   // now this will WORK because TargetObjectId is set
        setOrgWideAddressForGuest(msg);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }



    /**
     * @description Sends an internal notification email to Arelia Enrollment members
     * using a separate email template. Recipients are taken from the custom label
     * Arelia_Living_Enrollment_Members (comma-separated emails).
     * @param leadRecord Newly registered Lead.
     */
    private static void sendEnrollmentNotification(Lead leadRecord) {
        // Basic guard
        if (leadRecord == null || leadRecord.Id == null) {
            return;
        }

        // Parse enrollment email addresses from label
        List<String> enrollmentEmails = getEnrollmentEmails();
        if (enrollmentEmails.isEmpty()) {
            // No configured recipients – nothing to do
            return;
        }

        // Get enrollment template
        EmailTemplate template = getEnrollmentTemplate();
        if (template == null) {
            // No template configured – nothing to do
            return;
        }

        String projectRequestLink = Label.Arelia_Site_Label + Label.Arelia_Project_Request_Page_URL + '?id=' + leadRecord.Id;

        // Build customer name
        String leadName = ((leadRecord.FirstName != null ? leadRecord.FirstName + ' ' : '')
                        + leadRecord.LastName);

        // Reuse the same DTO used for welcome email
        WelcomeTokenData data = new WelcomeTokenData();
        data.name        = leadName;
        data.email       = leadRecord.Email;
        data.phone       = leadRecord.Phone;
        data.projectLink = projectRequestLink;

        // Start from template values
        String subject  = template.Subject;
        String textBody = template.Body;
        String htmlBody = template.HtmlValue;

        // Replace custom tokens
        subject  = replaceWelcomeTokens(subject,  data);
        textBody = replaceWelcomeTokens(textBody, data);
        htmlBody = replaceWelcomeTokens(htmlBody, data);

        // Build message
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(enrollmentEmails);

        if (String.isNotBlank(subject)) {
            msg.setSubject(subject);
        }

        // Prefer HTML when available
        if (String.isNotBlank(htmlBody)) {
            msg.setHtmlBody(htmlBody);
        } else {
            msg.setPlainTextBody(textBody);
        }

        // Optional: log as activity on Lead (if you want)
        msg.setTargetObjectId(leadRecord.Id);
        msg.setTreatTargetObjectAsRecipient(false);
        msg.setSaveAsActivity(true); // set true if you want a task on the Lead

        // For guest user, still use OrgWide address
        setOrgWideAddressForGuest(msg);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg });
    }


    /** Small DTO to prevent long-parameter-list PMD issue */
    private class WelcomeTokenData {
        String name;
        String email;
        String phone;
        String projectLink;
    }

    /**
     * @description Replaces custom welcome tokens in the template.
     * Supported tokens:
     *  - {{{Recipient.Name}}}
     *  - {{{Recipient.Email}}}
     *  - {{{Recipient.Phone}}}
     *  - {{{ProjectRequestLink}}}
     */
    private static String replaceWelcomeTokens(String source, WelcomeTokenData data) {
        if (String.isBlank(source)) {
            return source;
        }

        String result = source;

        result = result.replace('{{{Recipient.Name}}}',  data.name);
        result = result.replace('{{{Recipient.Email}}}', data.email  == null ? '' : data.email);
        result = result.replace('{{{Recipient.Phone}}}', data.phone == null ? '' : data.phone);
        result = result.replace('{{{ProjectRequestLink}}}', data.projectLink);

        return result;
    }


    // ----------------------------------------------------------------------
    // Helpers – Validation, CRUD, and configuration
    // ----------------------------------------------------------------------

    /**
     * @description Validates email format (very basic check).
     * @param email Email address.
     */
    private static void validateEmail(String email) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email is required.');
        }
        String trimmed = email.trim();
        if (!trimmed.contains('@') || !trimmed.contains('.')) {
            throw new AuraHandledException('Please provide a valid email address.');
        }
    }

    /**
     * @description Ensures the running user has create permission on Lead.
     */
    private static void assertCanCreateLead() {
        if (!Schema.sObjectType.Lead.isCreateable()) {
            throw new AuraHandledException(
                'You do not have permission to create Lead records.'
            );
        }
    }

    /**
     * @description Returns the welcome email template (full record) configured via
     * custom label Registration_Welcome_Template_DevName.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static EmailTemplate getWelcomeTemplate() {
        String devName = System.Label.Registration_Welcome_Template_DevName;
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [SELECT Id, Subject, Body, HtmlValue FROM EmailTemplate
            WHERE DeveloperName = :devName LIMIT 1];

        return templates.isEmpty() ? null : templates[0];
    }

    /**
     * @description Returns the enrollment notification email template configured via
     * custom label Registration_Enrollment_Template_DevName.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static EmailTemplate getEnrollmentTemplate() {
        String devName = System.Label.Registration_Enrollment_Template_DevName;
        if (String.isBlank(devName)) {
            return null;
        }

        List<EmailTemplate> templates = [SELECT Id, Subject, Body, HtmlValue FROM EmailTemplate
            WHERE DeveloperName = :devName LIMIT 1];

        return templates.isEmpty() ? null : templates[0];
    }


    /**
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

        List<EmailTemplate> templates = [SELECT Id, Subject, Body, HtmlValue FROM EmailTemplate
            WHERE DeveloperName = :devName LIMIT 1];

        if (templates.isEmpty()) {
            return null;
        }

        cachedVerificationTemplate = templates[0];
        return cachedVerificationTemplate;
    }

    /**
     * @description Sets Org-Wide Email Address Id for guest users using
     * @param msg Email message to update.
     */
    private static void setOrgWideAddressForGuest(Messaging.SingleEmailMessage msg) {
        if (msg == null) {
            return;
        }

        Id orgWideId = getOrgWideEmailAddressId();
        if (orgWideId != null && UserInfo.getUserType() == 'Guest') {
            msg.setOrgWideEmailAddressId(orgWideId);
        }
    }

    /**
     * @description Gets Org-Wide Email Address ID used for outbound emails.
     */
    private static Id getOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :Label.Arelia_OWD AND IsAllowAllProfiles = true LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }

    /**
     * @description Parses comma-separated enrollment member emails from
     * custom label Arelia_Living_Enrollment_Members.
     * @return List of trimmed email addresses.
     */
    private static List<String> getEnrollmentEmails() {
        List<String> result = new List<String>();

        String raw = System.Label.Arelia_Living_Enrollment_Members;
        if (String.isBlank(raw)) {
            return result;
        }

        for (String part : raw.split(',')) {
            if (String.isNotBlank(part)) {
                String email = part.trim();
                // Very light validation – same as other checks
                if (email.contains('@') && email.contains('.')) {
                    result.add(email);
                }
            }
        }

        return result;
    }

}