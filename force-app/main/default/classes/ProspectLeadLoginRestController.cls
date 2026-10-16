@RestResource(urlMapping='/registration/lead/login')
global without sharing class ProspectLeadLoginRestController {

    @HttpPost
    global static LoginResponse loginProspect() {

        LoginResponse response = new LoginResponse();

        response.success = false;
        response.projectSubmitted = false;

        try {

            RestContext.response.addHeader(
                'Content-Type',
                'application/json'
            );

            RestRequest requestValue = RestContext.request;

            // =========================================================
            // 1. VALIDATE REQUEST
            // =========================================================
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

            // =========================================================
            // 2. READ JSON
            // =========================================================

            Map<String, Object> payload =
                (Map<String, Object>)
                JSON.deserializeUntyped(
                    requestBody
                );

            String email =
                getStringValue(
                    payload,
                    'email'
                );

            String password =
                getStringValue(
                    payload,
                    'password'
                );

            // =========================================================
            // 3. VALIDATE EMAIL
            // =========================================================

            if (String.isBlank(email)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Email address is required.';

                return response;
            }

            email =
                email.trim().toLowerCase();

            if (!isValidEmail(email)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Please enter a valid email address.';

                return response;
            }

            // =========================================================
            // 4. VALIDATE PASSWORD
            // =========================================================

            if (String.isBlank(password)) {

                RestContext.response.statusCode = 400;

                response.message =
                    'Password is required.';

                return response;
            }

            /*
             * IMPORTANT:
             *
             * Same email can exist on multiple Lead records.
             *
             * Therefore DO NOT search only by Email.
             *
             * Email + Password together identify
             * the correct Lead.
             */

            // Contact.Email and Contact.Password__c are authoritative
            // after conversion.
            // Only the immutable conversion link can associate it
            // with a Lead.

            Map<Id, Contact> contactsById =
                new Map<Id, Contact>([
                    SELECT
                        Id,
                        FirstName,
                        LastName,
                        Email,
                        Phone,
                        Password__c
                    FROM Contact
                    WHERE
                        Email = :email
                        AND Password__c = :password
                    WITH SYSTEM_MODE
                ]);

            // Enforce exact, case-sensitive Contact password matching.
            for (
                Id candidateId :
                new List<Id>(contactsById.keySet())
            ) {

                String storedPassword =
                    contactsById
                        .get(candidateId)
                        .Password__c;

                if (
                    storedPassword == null ||
                    !storedPassword.equals(password)
                ) {

                    contactsById.remove(
                        candidateId
                    );
                }
            }

            Set<Id> contactIds =
                contactsById.keySet();

            List<Lead> matchingLeads = [
                SELECT
                    Id,
                    FirstName,
                    LastName,
                    Email,
                    Phone,
                    Enter_Password__c,
                    Project_Request_Submitted__c,
                    IsConverted,
                    ConvertedContactId,
                    Portal_Account_Key__c
                FROM Lead
                WHERE (
                    (
                        IsConverted = false
                        AND Email = :email
                        AND Enter_Password__c = :password
                    )
                    OR
                    (
                        IsConverted = true
                        AND ConvertedContactId IN :contactIds
                    )
                )
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            // =========================================================
            // 5. INVALID LOGIN
            // =========================================================

            if (matchingLeads.isEmpty()) {

                RestContext.response.statusCode = 401;

                response.message =
                    'Invalid email address or password.';

                return response;
            }

            // =========================================================
            // 6. EXACT LEAD MATCHED
            // =========================================================

            Lead leadRecord =
                matchingLeads[0];

            /*
             * Additional projects retain the original portal identity
             * and Contact access.
             */
            if (
                !String.isBlank(
                    leadRecord.Portal_Account_Key__c
                )
            ) {

                String accountKey =
                    leadRecord.Portal_Account_Key__c;

                List<Lead> accountLeads = [
                    SELECT
                        Id,
                        FirstName,
                        LastName,
                        Email,
                        Phone,
                        Enter_Password__c,
                        Project_Request_Submitted__c,
                        IsConverted,
                        ConvertedContactId
                    FROM Lead
                    WHERE Id = :accountKey
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];

                if (!accountLeads.isEmpty()) {

                    Lead accountLead =
                        accountLeads[0];

                    if (
                        (
                            accountLead.IsConverted &&
                            contactsById.containsKey(
                                accountLead.ConvertedContactId
                            )
                        )
                        ||
                        (
                            !accountLead.IsConverted &&
                            accountLead.Email != null &&
                            accountLead.Email.equalsIgnoreCase(
                                email
                            ) &&
                            accountLead.Enter_Password__c != null &&
                            accountLead.Enter_Password__c.equals(
                                password
                            )
                        )
                    ) {

                        leadRecord =
                            accountLead;
                    }
                }
            }

            Contact convertedContact =
                leadRecord.IsConverted
                    ? contactsById.get(
                        leadRecord.ConvertedContactId
                    )
                    : null;

            String fullName =
                buildFullName(
                    convertedContact == null
                        ? leadRecord.FirstName
                        : convertedContact.FirstName,

                    convertedContact == null
                        ? leadRecord.LastName
                        : convertedContact.LastName
                );

            // =========================================================
            // 7. LOGIN SUCCESS
            // =========================================================

            RestContext.response.statusCode =
                200;

            response.success =
                true;

            response.message =
                'Sign in successful.';

            /*
             * MOST IMPORTANT VALUE:
             * Flutter must save this Lead ID
             * and use it for all future requests.
             */
            response.leadId =
                leadRecord.Id;

            response.contactId =
                convertedContact == null
                    ? null
                    : convertedContact.Id;

            response.fullName =
                fullName;

            response.email =
                convertedContact == null
                    ? leadRecord.Email
                    : convertedContact.Email;

            response.phone =
                convertedContact == null
                    ? leadRecord.Phone
                    : convertedContact.Phone;

            response.projectSubmitted =
                leadRecord
                    .Project_Request_Submitted__c ==
                true;

            return response;

        } catch (JSONException exceptionValue) {

            RestContext.response.statusCode =
                400;

            response.success =
                false;

            response.message =
                'Invalid request format.';

            return response;

        } catch (Exception exceptionValue) {

            RestContext.response.statusCode =
                500;

            response.success =
                false;

            response.message =
                'Unable to sign in. '
                + exceptionValue.getMessage();

            return response;
        }
    }

    // =============================================================
    // GET STRING VALUE
    // =============================================================

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
            ).trim();

        if (
            String.isBlank(value) ||
            value.toLowerCase() == 'null'
        ) {

            return null;
        }

        return value;
    }

    // =============================================================
    // EMAIL VALIDATION
    // =============================================================

    private static Boolean isValidEmail(
        String email
    ) {

        if (String.isBlank(email)) {

            return false;
        }

        Pattern emailPattern =
            Pattern.compile(
                '^[A-Za-z0-9._%+-]+'
                + '@[A-Za-z0-9.-]+'
                + '\\.[A-Za-z]{2,}$'
            );

        return emailPattern
            .matcher(email)
            .matches();
    }

    // =============================================================
    // FULL NAME
    // =============================================================

    private static String buildFullName(
        String firstName,
        String lastName
    ) {

        List<String> nameParts =
            new List<String>();

        if (!String.isBlank(firstName)) {

            nameParts.add(
                firstName.trim()
            );
        }

        if (!String.isBlank(lastName)) {

            nameParts.add(
                lastName.trim()
            );
        }

        return String.join(
            nameParts,
            ' '
        );
    }

    // =============================================================
    // RESPONSE
    // =============================================================

    global class LoginResponse {

        public Boolean success;
        public String message;

        public Id leadId;
        public Id contactId;

        public String fullName;
        public String email;
        public String phone;

        public Boolean projectSubmitted;

        public LoginResponse() {

            success =
                false;

            projectSubmitted =
                false;
        }
    }
}