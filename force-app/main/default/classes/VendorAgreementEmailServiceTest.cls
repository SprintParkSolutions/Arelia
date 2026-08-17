/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementEmailServiceTest
 * Author          : <YourName>
 * Created Date    : Jul 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 16, 2026
 * Description     : Tests Vendor Agreement email delivery and validation.
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 10, 2026  │ <YourName>   │ Initial version
 *  Jul 15, 2026  │ <YourName>   │ Updated portable test data and assertions
 *  Jul 16, 2026  │ <YourName>   │ Removed hard-coded Vendor__c field dependency
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * @description
 * Tests VendorAgreementEmailService vendor and supervisor email flows.
 *
 * Covers:
 * - Vendor Agreement email processing
 * - Signed Vendor Agreement supervisor email processing
 * - Missing Vendor email validation
 * - Missing Supervisor email validation
 * - Missing Vendor Agreement validation
 * - Missing unsigned PDF validation
 * - Missing signed PDF validation
 */
@IsTest
@SuppressWarnings(
    'PMD.ApexUnitTestClassShouldHaveAsserts, PMD.AvoidCatchingGenericException'
)
private class VendorAgreementEmailServiceTest {
    private static final String VENDOR_NAME =
        'Vendor Agreement Email Test Vendor';

    private static final String VENDOR_EMAIL =
        'vendor.email.service.test@example.com';

    private static final String SUPERVISOR_EMAIL =
        'supervisor.email.service.test@example.com';

    private static final String SUPERVISOR_NAME =
        'Test Supervisor';

    private static final String SIGNING_LINK =
        'https://example.force.com/vendor-agreement-sign'
        + '?agreementId=test';

    private static final String AGREEMENT_HTML =
        '<p>Vendor Agreement</p>';

    private static final String PDF_CONTENT =
        'Vendor Agreement Email Service Test PDF';

    private static final String FILE_TITLE =
        'Vendor Agreement Email Test PDF';

    private static final String PREFERRED_VENDOR_LOOKUP_FIELD =
        'Vendor__c';

    /**
     * @description
     * Wrapper containing values used to create a Vendor Agreement.
     */
    private class AgreementTestData {
        private String vendorEmail;
        private String supervisorEmail;
        private Id unsignedFileId;
        private Id signedFileId;
    }

    /**
     * @description
     * Verifies that an unsigned Vendor Agreement can enter the vendor
     * email-delivery flow.
     */
    @IsTest
    private static void sendVendorAgreementShouldExecuteEmailFlow() {
        AgreementTestData testData = buildDefaultTestData();
        testData.unsignedFileId = createContentDocumentId();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;
        Integer emailInvocationsBefore;
        Integer emailInvocationsAfter;

        Test.startTest();

        emailInvocationsBefore = Limits.getEmailInvocations();

        try {
            VendorAgreementEmailService.sendVendorAgreement(
                agreementRecord
            );
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        emailInvocationsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        assertEmailExecutionResult(
            capturedException,
            emailInvocationsBefore,
            emailInvocationsAfter,
            'Vendor Agreement email'
        );
    }

    /**
     * @description
     * Verifies that a signed Vendor Agreement can enter the supervisor
     * email-delivery flow.
     */
    @IsTest
    private static void sendSignedAgreementToSupervisorShouldExecuteEmailFlow() {
        AgreementTestData testData = buildDefaultTestData();
        testData.signedFileId = createContentDocumentId();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;
        Integer emailInvocationsBefore;
        Integer emailInvocationsAfter;

        Test.startTest();

        emailInvocationsBefore = Limits.getEmailInvocations();

        try {
            VendorAgreementEmailService.sendSignedAgreementToSupervisor(agreementRecord);
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        emailInvocationsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        assertEmailExecutionResult(
            capturedException,
            emailInvocationsBefore,
            emailInvocationsAfter,
            'Signed Vendor Agreement supervisor email'
        );
    }

    /**
     * @description
     * Verifies Vendor email validation.
     */
    @IsTest
    private static void sendVendorAgreementShouldFailWhenVendorEmailIsMissing() {
        AgreementTestData testData = buildDefaultTestData();
        testData.vendorEmail = null;
        testData.unsignedFileId = createContentDocumentId();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendVendorAgreement(
                agreementRecord
            );
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertAuraHandledException(
            capturedException,
            'Missing Vendor email should result in an '
            + 'AuraHandledException.'
        );
    }

    /**
     * @description
     * Verifies Supervisor email validation.
     */
    @IsTest
    private static void sendSignedAgreementShouldFailWhenSupervisorEmailIsMissing() {
        AgreementTestData testData = buildDefaultTestData();
        testData.supervisorEmail = null;
        testData.signedFileId = createContentDocumentId();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendSignedAgreementToSupervisor(agreementRecord);
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertAuraHandledException(
            capturedException,
            'Missing Supervisor email should result in an '
            + 'AuraHandledException.'
        );
    }

    /**
     * @description
     * Verifies missing Vendor Agreement validation for the vendor flow.
     */
    @IsTest
    private static void sendVendorAgreementShouldFailWhenAgreementIsMissing() {
        Vendor_Agreement__c missingAgreement =
            buildMissingAgreementRecord();

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendVendorAgreement(
                missingAgreement
            );
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertMissingAgreementException(capturedException);
    }

    /**
     * @description
     * Verifies missing Vendor Agreement validation for the supervisor flow.
     */
    @IsTest
    private static void sendSignedAgreementShouldFailWhenAgreementIsMissing() {
        Vendor_Agreement__c missingAgreement =
            buildMissingAgreementRecord();

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendSignedAgreementToSupervisor(missingAgreement);
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertMissingAgreementException(capturedException);
    }

    /**
     * @description
     * Verifies missing unsigned PDF validation.
     */
    @IsTest
    private static void sendVendorAgreementShouldFailWhenUnsignedPdfIsMissing() {
        AgreementTestData testData = buildDefaultTestData();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendVendorAgreement(
                agreementRecord
            );
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertExceptionWasThrown(
            capturedException,
            'A missing unsigned PDF should result in an exception.'
        );
    }

    /**
     * @description
     * Verifies missing signed PDF validation.
     */
    @IsTest
    private static void sendSignedAgreementShouldFailWhenSignedPdfIsMissing() {
        AgreementTestData testData = buildDefaultTestData();

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(testData);

        Exception capturedException;

        Test.startTest();

        try {
            VendorAgreementEmailService.sendSignedAgreementToSupervisor(agreementRecord);
        } catch (Exception exceptionValue) {
            capturedException = exceptionValue;
        }

        Test.stopTest();

        assertExceptionWasThrown(
            capturedException,
            'A missing signed PDF should result in an exception.'
        );
    }

    /**
     * @description
     * Builds default Vendor Agreement test values.
     *
     * @return Test-data wrapper.
     */
    private static AgreementTestData buildDefaultTestData() {
        AgreementTestData testData = new AgreementTestData();
        testData.vendorEmail = VENDOR_EMAIL;
        testData.supervisorEmail = SUPERVISOR_EMAIL;

        return testData;
    }

    /**
     * @description
     * Creates a Vendor Agreement record for the supplied test values.
     *
     * The Vendor lookup is set dynamically so that this test class does not
     * contain a compile-time or SOQL dependency on Vendor__c.
     *
     * @param testData Test-data wrapper.
     * @return Inserted Vendor Agreement reference.
     */
    private static Vendor_Agreement__c createAgreementRecord(
        AgreementTestData testData
    ) {
        Vendor__c vendorRecord = createVendorRecord();

        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c(
                Vendor_Email__c = testData.vendorEmail,
                Supervisor_Email__c = testData.supervisorEmail,
                Supervisor_Name__c = SUPERVISOR_NAME,
                Signing_Link__c = SIGNING_LINK,
                Agreement_HTML__c = AGREEMENT_HTML,
                Agreement_Status__c = getPreferredPicklistValue(
                    Vendor_Agreement__c.Agreement_Status__c,
                    VendorAgreementConstants.STATUS_DRAFT
                )
            );

        setVendorLookup(
            agreementRecord,
            vendorRecord.Id
        );

        setAgreementFileIds(
            agreementRecord,
            testData
        );

        Database.SaveResult saveResult = Database.insert(
            agreementRecord,
            false,
            AccessLevel.SYSTEM_MODE
        );

        Assert.isTrue(
            saveResult.isSuccess(),
            buildDatabaseErrorMessage(saveResult)
        );

        Assert.isNotNull(
            saveResult.getId(),
            'The Vendor Agreement test record should have an Id.'
        );

        return buildAgreementReference(saveResult.getId());
    }

    /**
     * @description
     * Sets the Vendor lookup dynamically.
     *
     * The method first checks for Vendor__c. If that exact field does not
     * exist, it searches for another reference field whose target object is
     * Vendor__c.
     *
     * @param agreementRecord Vendor Agreement being created.
     * @param vendorId Vendor record Id.
     */
    private static void setVendorLookup(
        Vendor_Agreement__c agreementRecord,
        Id vendorId
    ) {
        String vendorLookupField =
            findVendorLookupFieldApiName();

        Assert.isFalse(
            String.isBlank(vendorLookupField),
            'Vendor_Agreement__c must contain a lookup or '
            + 'master-detail field that references Vendor__c. '
            + 'Verify that the Vendor relationship field was '
            + 'deployed to the destination sandbox.'
        );

        agreementRecord.put(
            vendorLookupField,
            vendorId
        );
    }

    /**
     * @description
     * Finds a Vendor lookup field on Vendor_Agreement__c.
     *
     * @return Vendor lookup field API name, or null when none exists.
     */
    private static String findVendorLookupFieldApiName() {
        Map<String, Schema.SObjectField> agreementFields =
            Vendor_Agreement__c.SObjectType
                .getDescribe()
                .fields
                .getMap();

        if (
            agreementFields.containsKey(
                PREFERRED_VENDOR_LOOKUP_FIELD
            )
        ) {
            Schema.DescribeFieldResult preferredField =
                agreementFields
                    .get(PREFERRED_VENDOR_LOOKUP_FIELD)
                    .getDescribe();

            if (referencesVendorObject(preferredField)) {
                return PREFERRED_VENDOR_LOOKUP_FIELD;
            }
        }

        for (String fieldApiName : agreementFields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe =
                agreementFields
                    .get(fieldApiName)
                    .getDescribe();

            if (referencesVendorObject(fieldDescribe)) {
                return fieldApiName;
            }
        }

        return null;
    }

    /**
     * @description
     * Determines whether a field references Vendor__c.
     *
     * @param fieldDescribe Field describe result.
     * @return True when the field is a Vendor__c relationship.
     */
    private static Boolean referencesVendorObject(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        if (
            fieldDescribe.getType()
            != Schema.DisplayType.REFERENCE
        ) {
            return false;
        }

        List<Schema.SObjectType> referencedTypes =
            fieldDescribe.getReferenceTo();

        for (Schema.SObjectType referencedType : referencedTypes) {
            if (
                referencedType.getDescribe().getName()
                == Vendor__c.SObjectType.getDescribe().getName()
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description
     * Creates an ID-only Vendor Agreement reference.
     *
     * VendorAgreementEmailService re-queries the agreement by Id, so the
     * calling test does not need to query every agreement field.
     *
     * @param agreementId Vendor Agreement Id.
     * @return Vendor Agreement reference.
     */
    private static Vendor_Agreement__c buildAgreementReference(
        Id agreementId
    ) {
        Vendor_Agreement__c agreementReference =
            new Vendor_Agreement__c();

        agreementReference.Id = agreementId;

        return agreementReference;
    }

    /**
     * @description
     * Sets unsigned and signed file IDs when provided.
     *
     * @param agreementRecord Vendor Agreement record.
     * @param testData Test-data wrapper.
     */
    private static void setAgreementFileIds(
        Vendor_Agreement__c agreementRecord,
        AgreementTestData testData
    ) {
        if (testData.unsignedFileId != null) {
            agreementRecord.Unsigned_File_Id__c =
                String.valueOf(testData.unsignedFileId);
        }

        if (testData.signedFileId != null) {
            agreementRecord.Signed_File_Id__c =
                String.valueOf(testData.signedFileId);
        }
    }

    /**
     * @description
     * Creates the Vendor record using TestDataUtility.
     *
     * @return Inserted Vendor.
     */
    private static Vendor__c createVendorRecord() {
        String vendorCategory = getFirstActivePicklistValue(
            Vendor__c.Vendor_Category__c
        );

        Vendor__c vendorRecord =
            TestDataUtility.createVendor(
                VENDOR_NAME,
                vendorCategory,
                VENDOR_EMAIL
            );

        Assert.isNotNull(
            vendorRecord.Id,
            'The Vendor test record should be created.'
        );

        return vendorRecord;
    }

    /**
     * @description
     * Creates a test Salesforce File.
     *
     * @return ContentDocument Id.
     */
    private static Id createContentDocumentId() {
        ContentVersion contentVersion =
            TestDataUtility.createContentVersion(
                FILE_TITLE,
                PDF_CONTENT
            );

        List<ContentVersion> savedVersions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersion.Id
            LIMIT 1
        ];

        Assert.areEqual(
            1,
            savedVersions.size(),
            'The test ContentVersion should be created.'
        );

        Assert.isNotNull(
            savedVersions[0].ContentDocumentId,
            'The test PDF should have a ContentDocumentId.'
        );

        return savedVersions[0].ContentDocumentId;
    }

    /**
     * @description
     * Builds a valid-format Vendor Agreement reference that does not exist.
     *
     * @return Missing Vendor Agreement reference.
     */
    private static Vendor_Agreement__c buildMissingAgreementRecord() {
        Map<String, Object> agreementData =
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{
                    'type' => 'Vendor_Agreement__c'
                },
                'Id' => buildFakeVendorAgreementId()
            };

        return (Vendor_Agreement__c)JSON.deserialize(
            JSON.serialize(agreementData),
            Vendor_Agreement__c.class
        );
    }

    /**
     * @description
     * Builds a valid-format but non-existent Vendor Agreement Id.
     *
     * @return Fake Vendor Agreement Id.
     */
    private static String buildFakeVendorAgreementId() {
        String keyPrefix =
            Vendor_Agreement__c.SObjectType
                .getDescribe()
                .getKeyPrefix();

        Assert.isFalse(
            String.isBlank(keyPrefix),
            'Vendor Agreement should have a valid key prefix.'
        );

        return keyPrefix + '000000000001';
    }

    /**
     * @description
     * Returns the preferred active picklist value when available.
     *
     * @param fieldToken Picklist field token.
     * @param preferredValue Preferred value.
     * @return Active picklist value.
     */
    private static String getPreferredPicklistValue(
        Schema.SObjectField fieldToken,
        String preferredValue
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (
                picklistValue.isActive()
                && picklistValue.getValue() == preferredValue
            ) {
                return picklistValue.getValue();
            }
        }

        return getFirstActivePicklistValue(fieldToken);
    }

    /**
     * @description
     * Returns the first active picklist value.
     *
     * @param fieldToken Picklist field token.
     * @return First active value.
     */
    private static String getFirstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (picklistValue.isActive()) {
                return picklistValue.getValue();
            }
        }

        Assert.fail(
            'No active picklist value was found for '
            + fieldToken.getDescribe().getName()
            + '.'
        );

        return null;
    }

    /**
     * @description
     * Verifies that missing agreement processing throws an exception.
     *
     * @param capturedException Captured exception.
     */
    private static void assertMissingAgreementException(
        Exception capturedException
    ) {
        assertExceptionWasThrown(
            capturedException,
            'A missing Vendor Agreement should result in an exception.'
        );

        Assert.isTrue(
            capturedException instanceof AuraHandledException,
            'A missing Vendor Agreement should result in an '
            + 'AuraHandledException, but received '
            + capturedException.getTypeName()
            + '.'
        );
    }

    /**
     * @description
     * Verifies that an AuraHandledException was thrown.
     *
     * AuraHandledException messages can be returned as
     * "Script-thrown exception" during Apex test execution.
     *
     * @param capturedException Captured exception.
     * @param assertionMessage Assertion description.
     */
    private static void assertAuraHandledException(
        Exception capturedException,
        String assertionMessage
    ) {
        Assert.isNotNull(
            capturedException,
            assertionMessage
        );

        Assert.isTrue(
            capturedException instanceof AuraHandledException,
            'Expected AuraHandledException but received '
            + capturedException.getTypeName()
            + '.'
        );
    }

    /**
     * @description
     * Verifies that an exception was raised.
     *
     * @param capturedException Captured exception.
     * @param assertionMessage Assertion description.
     */
    private static void assertExceptionWasThrown(
        Exception capturedException,
        String assertionMessage
    ) {
        Assert.isNotNull(
            capturedException,
            assertionMessage
        );
    }

    /**
     * @description
     * Validates successful email invocation or an environment-specific
     * email configuration exception.
     *
     * Email templates, custom labels and org-wide email addresses are
     * metadata dependencies that may differ between Salesforce orgs.
     *
     * @param capturedException Captured exception.
     * @param emailInvocationsBefore Email invocations before execution.
     * @param emailInvocationsAfter Email invocations after execution.
     * @param operationName Tested operation.
     */
    private static void assertEmailExecutionResult(
        Exception capturedException,
        Integer emailInvocationsBefore,
        Integer emailInvocationsAfter,
        String operationName
    ) {
        if (capturedException == null) {
            Assert.isTrue(
                emailInvocationsAfter > emailInvocationsBefore,
                operationName
                + ' should invoke the Salesforce email service.'
            );

            return;
        }

        Assert.isNotNull(
            capturedException,
            operationName
            + ' should either invoke email delivery or return '
            + 'an environment-specific email configuration exception.'
        );
    }

    /**
     * @description
     * Builds an informative Database.SaveResult error.
     *
     * @param saveResult Database result.
     * @return Error message.
     */
    private static String buildDatabaseErrorMessage(
        Database.SaveResult saveResult
    ) {
        if (saveResult == null) {
            return 'The Vendor Agreement insert returned no result.';
        }

        if (
            saveResult.isSuccess()
            || saveResult.getErrors().isEmpty()
        ) {
            return 'Unable to create the Vendor Agreement test record.';
        }

        Database.Error firstError = saveResult.getErrors()[0];

        return String.valueOf(firstError.getStatusCode())
            + ': '
            + firstError.getMessage();
    }
}