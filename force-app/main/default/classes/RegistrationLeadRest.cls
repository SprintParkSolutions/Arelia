@RestResource(urlMapping='/registration/leads')
global without sharing class RegistrationLeadRest {

    @HttpPost
    global static LeadResponse registerLead() {

        LeadResponse response =
            new LeadResponse(
                false,
                null,
                null
            );

        try {

            RestRequest requestValue =
                RestContext.request;

            /*
             * =========================================
             * REQUEST BODY VALIDATION
             * =========================================
             */
            if (
                requestValue == null ||
                requestValue.requestBody == null
            ) {
                RestContext.response.statusCode = 400;

                response.message =
                    'Request body is required.';

                return response;
            }

            String requestBody =
                requestValue.requestBody.toString();

            if (String.isBlank(requestBody)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Request body is required.';

                return response;
            }

            /*
             * =========================================
             * PARSE REQUEST JSON
             * =========================================
             */
            Map<String, Object> payload =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    requestBody
                );

            String firstName =
                getStringValue(
                    payload,
                    'firstName'
                );

            String lastName =
                getStringValue(
                    payload,
                    'lastName'
                );

            String email =
                getStringValue(
                    payload,
                    'email'
                );

            String phone =
                getStringValue(
                    payload,
                    'phone'
                );

            String companyName =
                getStringValue(
                    payload,
                    'companyName'
                );

            String password =
                getStringValue(
                    payload,
                    'password'
                );

            String confirmPassword =
                getStringValue(
                    payload,
                    'confirmPassword'
                );

            /*
             * Optional source Lead.
             *
             * Used when another Lead is created
             * for the same customer and portal
             * credentials have to be copied.
             */
            String sourceLeadIdValue =
                getStringValue(
                    payload,
                    'sourceLeadId'
                );

            Lead sourceLead;

            /*
             * =========================================
             * SOURCE LEAD VALIDATION
             * =========================================
             */
            if (!String.isBlank(sourceLeadIdValue)) {

                Id sourceLeadId;

                try {

                    sourceLeadId =
                        (Id) sourceLeadIdValue.trim();

                } catch (Exception exceptionValue) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Invalid source Lead ID.';

                    return response;
                }

                if (
                    sourceLeadId == null ||
                    sourceLeadId.getSObjectType() !=
                        Lead.SObjectType
                ) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Invalid source Lead ID.';

                    return response;
                }

                List<Lead> sourceLeads = [
                    SELECT
                        Id,
                        Email,
                        Enter_Password__c,
                        Confirm_password__c
                    FROM Lead
                    WHERE Id = :sourceLeadId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];

                if (sourceLeads.isEmpty()) {

                    RestContext.response.statusCode = 404;

                    response.message =
                        'The source customer account was not found.';

                    return response;
                }

                sourceLead =
                    sourceLeads[0];

                /*
                 * Source Lead Email must match
                 * incoming Email.
                 */
                if (
                    String.isBlank(sourceLead.Email) ||
                    String.isBlank(email) ||
                    !sourceLead.Email
                        .equalsIgnoreCase(
                            email.trim()
                        )
                ) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'The source customer does not match '
                        + 'the supplied email.';

                    return response;
                }

                /*
                 * Source Lead must contain
                 * portal password.
                 */
                if (
                    String.isBlank(
                        sourceLead.Enter_Password__c
                    )
                ) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'The source customer does not have '
                        + 'portal credentials.';

                    return response;
                }
            }

            /*
             * Password fields are optional because
             * the endpoint may also be used for
             * Book Consultation.
             */
            Boolean isProspectAccountSignup =
                !String.isBlank(password) ||
                !String.isBlank(confirmPassword);

            /*
             * =========================================
             * REQUIRED FIELD VALIDATION
             * =========================================
             */
            if (String.isBlank(firstName)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'First Name is required.';

                return response;
            }

            if (String.isBlank(lastName)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Last Name is required.';

                return response;
            }

            if (String.isBlank(email)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Email is required.';

                return response;
            }

            if (String.isBlank(phone)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Phone number is required.';

                return response;
            }

            /*
             * =========================================
             * NORMALIZE DATA
             * =========================================
             */
            email =
                email
                    .trim()
                    .toLowerCase();

            phone =
                String.isBlank(phone) ? null : phone.trim();

            /*
             * =========================================
             * EMAIL FORMAT VALIDATION
             *
             * NOTE:
             * This validates FORMAT only.
             *
             * It DOES NOT check whether the Email
             * already exists in Salesforce.
             * =========================================
             */
            if (!isValidEmail(email)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Please enter a valid email address.';

                return response;
            }

            /*
             * =========================================
             * PHONE VALIDATION
             * =========================================
             */
            if (!String.isBlank(phone) && !isValidPhone(phone)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Enter a valid phone number with country code '
                    + '(for example, +919876543210).';

                return response;
            }

            /*
             * Default Company
             */
            if (String.isBlank(companyName)) {

                companyName =
                    'self';
            }

            /*
             * =========================================
             * PASSWORD VALIDATIONS
             * =========================================
             */
            if (isProspectAccountSignup) {

                if (String.isBlank(password)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Enter Password is required.';

                    return response;
                }

                if (String.isBlank(confirmPassword)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Confirm Password is required.';

                    return response;
                }

                /*
                 * Minimum 8 characters
                 */
                if (password.length() < 8) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password must contain at least '
                        + '8 characters.';

                    return response;
                }

                /*
                 * Salesforce fields are Text(20)
                 */
                if (password.length() > 20) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password cannot contain more than '
                        + '20 characters.';

                    return response;
                }

                if (confirmPassword.length() > 20) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Confirm Password cannot contain '
                        + 'more than 20 characters.';

                    return response;
                }

                /*
                 * Passwords must match
                 */
                if (password != confirmPassword) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password and Confirm Password '
                        + 'do not match.';

                    return response;
                }

                /*
                 * Uppercase validation
                 */
                if (!containsUppercase(password)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password must contain at least '
                        + 'one uppercase letter.';

                    return response;
                }

                /*
                 * Lowercase validation
                 */
                if (!containsLowercase(password)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password must contain at least '
                        + 'one lowercase letter.';

                    return response;
                }

                /*
                 * Number validation
                 */
                if (!containsNumber(password)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password must contain at least '
                        + 'one number.';

                    return response;
                }

                /*
                 * Special character validation
                 */
                if (!containsSpecialCharacter(password)) {

                    RestContext.response.statusCode = 400;

                    response.message =
                        'Password must contain at least '
                        + 'one special character.';

                    return response;
                }

                /*
                 * =====================================
                 * DUPLICATE EMAIL VALIDATION REMOVED
                 * =====================================
                 *
                 * DO NOT add existingProspects query.
                 *
                 * Same Email is intentionally allowed
                 * to create multiple Lead records.
                 */
            }

            /*
             * =========================================
             * CREATE NEW LEAD
             * =========================================
             */
            Lead leadRecord =
                new Lead();

            leadRecord.FirstName =
                firstName.trim();

            leadRecord.LastName =
                lastName.trim();

            leadRecord.Email =
                email;

            leadRecord.Phone =
                phone;

            leadRecord.Company =
                companyName.trim();

            /*
             * =========================================
             * PASSWORD / SOURCE LEAD HANDLING
             * =========================================
             */

            /*
             * Existing customer creating another Lead.
             *
             * Copy password from source Lead.
             */
            if (sourceLead != null) {

                leadRecord.Enter_Password__c =
                    sourceLead.Enter_Password__c;

                if (
                    String.isBlank(
                        sourceLead.Confirm_password__c
                    )
                ) {

                    leadRecord.Confirm_password__c =
                        sourceLead.Enter_Password__c;

                } else {

                    leadRecord.Confirm_password__c =
                        sourceLead.Confirm_password__c;
                }

            } else if (isProspectAccountSignup) {

                /*
                 * New Prospect Signup.
                 */
                leadRecord.Enter_Password__c =
                    password;

                leadRecord.Confirm_password__c =
                    confirmPassword;
            }

            /*
             * =========================================
             * SALESFORCE DUPLICATE RULE HANDLING
             * =========================================
             *
             * Salesforce Duplicate Rule may detect:
             * - Same Email
             * - Same Phone
             * - Other Matching Rules
             *
             * allowSave = true means record should
             * still be allowed to save.
             */
            Database.DMLOptions dmlOptions =
                new Database.DMLOptions();

            dmlOptions
                .DuplicateRuleHeader
                .allowSave = true;

            dmlOptions
                .DuplicateRuleHeader
                .runAsCurrentUser = true;

            /*
             * =========================================
             * INSERT LEAD
             * =========================================
             */
            Database.SaveResult saveResult =
                Database.insert(
                    leadRecord,
                    dmlOptions,
                    AccessLevel.SYSTEM_MODE
                );

            /*
             * =========================================
             * INSERT ERROR HANDLING
             * =========================================
             */
            if (!saveResult.isSuccess()) {

                RestContext.response.statusCode = 400;

                response.success = false;
                response.leadId = null;

                Database.Error[] errors =
                    saveResult.getErrors();

                if (
                    errors == null ||
                    errors.isEmpty()
                ) {

                    response.message =
                        'Unable to create the Lead record.';

                } else {

                    response.message =
                        errors[0].getMessage();
                }

                return response;
            }

            /*
             * =========================================
             * SUCCESS RESPONSE
             * =========================================
             */
            leadRecord.Id =
                saveResult.getId();

            RestContext.response.statusCode = 200;

            response.success = true;

            response.leadId =
                leadRecord.Id;

            response.message =
                isProspectAccountSignup
                    ? 'Prospect account created successfully.'
                    : 'Lead registered successfully.';

            return response;

        } catch (DmlException exceptionValue) {

            RestContext.response.statusCode = 400;

            response.success = false;
            response.leadId = null;

            response.message =
                exceptionValue.getDmlMessage(0);

            return response;

        } catch (JSONException exceptionValue) {

            RestContext.response.statusCode = 400;

            response.success = false;
            response.leadId = null;

            response.message =
                'Invalid request format.';

            return response;

        } catch (Exception exceptionValue) {

            RestContext.response.statusCode = 500;

            response.success = false;
            response.leadId = null;

            response.message =
                exceptionValue.getMessage();

            return response;
        }
    }


    /*
     * =============================================
     * GET VALUE FROM JSON
     * =============================================
     */
    private static String getStringValue(
        Map<String, Object> payload,
        String keyName
    ) {

        if (
            payload == null ||
            !payload.containsKey(keyName) ||
            payload.get(keyName) == null
        ) {
            return null;
        }

        String value =
            String.valueOf(
                payload.get(keyName)
            );
        if (keyName != 'password' && keyName != 'confirmPassword') value = value.trim();

        if (
            String.isBlank(value) ||
            value.toLowerCase() == 'null'
        ) {
            return null;
        }

        return value;
    }


    /*
     * =============================================
     * EMAIL FORMAT VALIDATION
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean isValidEmail(
        String email
    ) {

        if (String.isBlank(email)) {
            return false;
        }

        String value =
            email.trim();

        /*
         * Spaces are not allowed.
         */
        if (value.contains(' ')) {
            return false;
        }

        Integer firstAtIndex =
            value.indexOf('@');

        Integer lastAtIndex =
            value.lastIndexOf('@');

        /*
         * Must contain exactly one @.
         *
         * @ cannot be first character.
         */
        if (
            firstAtIndex <= 0 ||
            firstAtIndex != lastAtIndex
        ) {
            return false;
        }

        /*
         * Need characters after @.
         */
        if (
            firstAtIndex >=
            value.length() - 1
        ) {
            return false;
        }

        Integer dotIndex =
            value.lastIndexOf('.');

        /*
         * Dot must come after @
         * and there must be at least
         * one character between @ and .
         */
        if (
            dotIndex <= firstAtIndex + 1
        ) {
            return false;
        }

        /*
         * Require minimum 2 characters
         * after the final dot.
         *
         * Example:
         * .com
         * .in
         */
        if (
            dotIndex >=
            value.length() - 2
        ) {
            return false;
        }

        /*
         * Email cannot start with dot.
         */
        if (value.startsWith('.')) {
            return false;
        }

        /*
         * Email cannot have dot
         * immediately before @.
         */
        if (
            firstAtIndex > 0 &&
            value.substring(
                firstAtIndex - 1,
                firstAtIndex
            ) == '.'
        ) {
            return false;
        }

        /*
         * Domain cannot start with dot.
         */
        if (
            firstAtIndex + 1 <
            value.length() &&
            value.substring(
                firstAtIndex + 1,
                firstAtIndex + 2
            ) == '.'
        ) {
            return false;
        }

        return true;
    }


    /*
     * =============================================
     * PHONE VALIDATION
     *
     * International numbers: + followed by up to 15 digits. Legacy 10-digit numbers remain supported.
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean isValidPhone(
        String phone
    ) {

        if (String.isBlank(phone)) {
            return false;
        }

        String value =
            phone.trim();

        if (value.startsWith('+')) {
            value = value.substring(1);
            if (value.length() < 7 || value.length() > 15 || value.startsWith('0')) {
                return false;
            }
        } else if (value.length() != 10) {
            return false;
        }

        String validDigits =
            '0123456789';

        for (
            Integer indexValue = 0;
            indexValue < value.length();
            indexValue++
        ) {

            String characterValue =
                value.substring(
                    indexValue,
                    indexValue + 1
                );

            if (
                !validDigits.contains(
                    characterValue
                )
            ) {
                return false;
            }
        }

        return true;
    }


    /*
     * =============================================
     * PASSWORD UPPERCASE VALIDATION
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean containsUppercase(
        String password
    ) {

        if (String.isBlank(password)) {
            return false;
        }

        String uppercaseCharacters =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

        for (
            Integer indexValue = 0;
            indexValue < password.length();
            indexValue++
        ) {

            String characterValue =
                password.substring(
                    indexValue,
                    indexValue + 1
                );

            if (
                uppercaseCharacters.contains(
                    characterValue
                )
            ) {
                return true;
            }
        }

        return false;
    }


    /*
     * =============================================
     * PASSWORD LOWERCASE VALIDATION
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean containsLowercase(
        String password
    ) {

        if (String.isBlank(password)) {
            return false;
        }

        String lowercaseCharacters =
            'abcdefghijklmnopqrstuvwxyz';

        for (
            Integer indexValue = 0;
            indexValue < password.length();
            indexValue++
        ) {

            String characterValue =
                password.substring(
                    indexValue,
                    indexValue + 1
                );

            if (
                lowercaseCharacters.contains(
                    characterValue
                )
            ) {
                return true;
            }
        }

        return false;
    }


    /*
     * =============================================
     * PASSWORD NUMBER VALIDATION
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean containsNumber(
        String password
    ) {

        if (String.isBlank(password)) {
            return false;
        }

        String numberCharacters =
            '0123456789';

        for (
            Integer indexValue = 0;
            indexValue < password.length();
            indexValue++
        ) {

            String characterValue =
                password.substring(
                    indexValue,
                    indexValue + 1
                );

            if (
                numberCharacters.contains(
                    characterValue
                )
            ) {
                return true;
            }
        }

        return false;
    }


    /*
     * =============================================
     * PASSWORD SPECIAL CHARACTER VALIDATION
     *
     * Anything other than:
     * A-Z
     * a-z
     * 0-9
     *
     * is treated as a special character.
     *
     * NO Pattern
     * NO matches()
     * =============================================
     */
    private static Boolean containsSpecialCharacter(
        String password
    ) {

        if (String.isBlank(password)) {
            return false;
        }

        String uppercaseCharacters =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

        String lowercaseCharacters =
            'abcdefghijklmnopqrstuvwxyz';

        String numberCharacters =
            '0123456789';

        for (
            Integer indexValue = 0;
            indexValue < password.length();
            indexValue++
        ) {

            String characterValue =
                password.substring(
                    indexValue,
                    indexValue + 1
                );

            Boolean isUppercase =
                uppercaseCharacters.contains(
                    characterValue
                );

            Boolean isLowercase =
                lowercaseCharacters.contains(
                    characterValue
                );

            Boolean isNumber =
                numberCharacters.contains(
                    characterValue
                );

            if (
                !isUppercase &&
                !isLowercase &&
                !isNumber
            ) {
                return true;
            }
        }

        return false;
    }


    /*
     * =============================================
     * RESPONSE CLASS
     * =============================================
     */
    global class LeadResponse {

        public Boolean success;
        public Id leadId;
        public String message;

        public LeadResponse(
            Boolean success,
            Id leadId,
            String message
        ) {

            this.success =
                success;

            this.leadId =
                leadId;

            this.message =
                message;
        }
    }
}