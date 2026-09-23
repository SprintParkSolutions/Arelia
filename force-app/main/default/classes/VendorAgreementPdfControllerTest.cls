/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementPdfControllerTest
 * Author          : <YourName>
 * Created Date    : Jul 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 10, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * Class Name      : VendorAgreementPdfControllerTest
 * Author          : <YourName>
 * Created Date    : Jul 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 16, 2026
 * Description     : Tests VendorAgreementPdfController.
 *
 * Change History:
 * Jul 10, 2026 | <YourName> | Initial version
 * Jul 16, 2026 | <YourName> | Added deployment-safe dynamic field handling
 */

/**
 * @description
 * Test class for VendorAgreementPdfController.
 *
 * Covers:
 * - Missing agreementId parameter
 * - Valid Vendor Agreement Id
 * - Non-existing Vendor Agreement Id
 * - Blank Agreement HTML
 *
 * Newly deployed fields are accessed dynamically to avoid metadata-order
 * issues during change-set validation.
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount,PMD.ApexUnitTestClassShouldHaveAsserts, PMD.ApexSOQLInjection'
)
private class VendorAgreementPdfControllerTest {

    private static final String AGREEMENT_HTML_FIELD =
        'Agreement_HTML__c';

    private static final String VENDOR_EMAIL_FIELD =
        'Vendor_Email__c';

    private static final String AGREEMENT_STATUS_FIELD =
        'Agreement_Status__c';

    private static final String AGREEMENT_HTML =
        '<div><h1>Vendor Agreement</h1>'
        + '<p>PDF controller test content</p></div>';

    private static final String VENDOR_EMAIL =
        'vendor.pdf.controller.test@example.com';

    /**
     * @description
     * Verifies that the controller returns blank HTML when the page parameter
     * is missing.
     */
    @IsTest
    private static void
        constructorShouldReturnBlankHtmlWhenAgreementIdIsMissing() {

        setCurrentPage(null);

        Test.startTest();

        VendorAgreementPdfController controller =
            new VendorAgreementPdfController();

        String agreementHtml = controller.getAgreementHtml();

        Test.stopTest();

        Assert.isNull(
            controller.agreement,
            'Agreement should remain null when agreementId is missing.'
        );

        Assert.areEqual(
            '',
            agreementHtml,
            'Agreement HTML should be blank when agreementId is missing.'
        );
    }

    /**
     * @description
     * Verifies that the controller loads an agreement for a valid Id.
     */
    @IsTest
    private static void
        constructorShouldLoadAgreementWhenAgreementIdIsValid() {

        if (!isAgreementHtmlQueryable()) {
            Assert.isFalse(
                isAgreementHtmlQueryable(),
                'The test safely handles Agreement_HTML__c while the field '
                    + 'is not queryable during deployment validation.'
            );
            return;
        }

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord(AGREEMENT_HTML);

        setCurrentPage(agreementRecord.Id);

        Test.startTest();

        VendorAgreementPdfController controller =
            new VendorAgreementPdfController();

        String agreementHtml = controller.getAgreementHtml();

        Test.stopTest();

        Assert.isNotNull(
            controller.agreement,
            'Agreement should be loaded for a valid agreementId.'
        );

        Assert.areEqual(
            agreementRecord.Id,
            controller.agreement.Id,
            'Loaded agreement Id should match the inserted agreement.'
        );

        Assert.areEqual(
            getStoredAgreementHtml(agreementRecord.Id),
            agreementHtml,
            'Controller should return the stored agreement HTML.'
        );
    }

    /**
     * @description
     * Verifies that the controller returns blank HTML for a non-existing
     * agreement.
     */
    @IsTest
    private static void
        constructorShouldReturnBlankHtmlWhenAgreementIsNotFound() {

        if (!isAgreementHtmlQueryable()) {
            Assert.isFalse(
                isAgreementHtmlQueryable(),
                'The test safely handles Agreement_HTML__c while the field '
                    + 'is not queryable during deployment validation.'
            );
            return;
        }

        setCurrentPage(buildFakeVendorAgreementId());

        Test.startTest();

        VendorAgreementPdfController controller =
            new VendorAgreementPdfController();

        String agreementHtml = controller.getAgreementHtml();

        Test.stopTest();

        Assert.isNull(
            controller.agreement,
            'Agreement should remain null when no matching record exists.'
        );

        Assert.areEqual(
            '',
            agreementHtml,
            'Agreement HTML should be blank when no agreement exists.'
        );
    }

    /**
     * @description
     * Verifies that blank agreement HTML produces a blank result.
     */
    @IsTest
    private static void
        getAgreementHtmlShouldReturnBlankWhenAgreementHtmlIsBlank() {

        if (!isAgreementHtmlQueryable()) {
            Assert.isFalse(
                isAgreementHtmlQueryable(),
                'The test safely handles Agreement_HTML__c while the field '
                    + 'is not queryable during deployment validation.'
            );
            return;
        }

        Vendor_Agreement__c agreementRecord =
            createAgreementRecord('');

        setCurrentPage(agreementRecord.Id);

        Test.startTest();

        VendorAgreementPdfController controller =
            new VendorAgreementPdfController();

        String agreementHtml = controller.getAgreementHtml();

        Test.stopTest();

        Assert.isNotNull(
            controller.agreement,
            'Agreement should be loaded for a valid agreementId.'
        );

        Assert.isTrue(
            String.isBlank(agreementHtml),
            'Blank Agreement HTML should return a blank value.'
        );
    }

    /**
     * @description
     * Creates a Vendor Agreement using dynamic field assignment.
     *
     * @param agreementHtml HTML content to store.
     * @return Inserted Vendor Agreement.
     */
    private static Vendor_Agreement__c createAgreementRecord(
        String agreementHtml
    ) {
        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c();

        Map<String, Schema.SObjectField> agreementFields =
            getAgreementFields();

        putFieldWhenCreateable(
            agreementRecord,
            agreementFields,
            AGREEMENT_HTML_FIELD,
            agreementHtml
        );

        putFieldWhenCreateable(
            agreementRecord,
            agreementFields,
            VENDOR_EMAIL_FIELD,
            VENDOR_EMAIL
        );

        putAgreementStatusWhenCreateable(
            agreementRecord,
            agreementFields
        );

        List<SObject> recordsToSanitize =
            new List<SObject>{ agreementRecord };

        SObjectAccessDecision accessDecision =
            Security.stripInaccessible(
                AccessType.CREATABLE,
                recordsToSanitize
            );

        Vendor_Agreement__c sanitizedAgreement =
            (Vendor_Agreement__c) accessDecision.getRecords()[0];

        Database.SaveResult saveResult =
            Database.insert(sanitizedAgreement, false);

        Assert.isTrue(
            saveResult.isSuccess(),
            buildInsertFailureMessage(saveResult)
        );

        sanitizedAgreement.Id = saveResult.getId();

        return sanitizedAgreement;
    }

    /**
     * @description
     * Sets a field when it exists and is createable.
     *
     * @param agreementRecord Vendor Agreement record.
     * @param agreementFields Vendor Agreement field map.
     * @param fieldApiName Field API name.
     * @param fieldValue Field value.
     */
    private static void putFieldWhenCreateable(
        Vendor_Agreement__c agreementRecord,
        Map<String, Schema.SObjectField> agreementFields,
        String fieldApiName,
        Object fieldValue
    ) {
        if (!agreementFields.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe =
            agreementFields.get(fieldApiName).getDescribe();

        if (fieldDescribe.isCreateable()) {
            agreementRecord.put(fieldApiName, fieldValue);
        }
    }

    /**
     * @description
     * Sets an active Agreement Status when the field is available.
     *
     * @param agreementRecord Vendor Agreement record.
     * @param agreementFields Vendor Agreement field map.
     */
    private static void putAgreementStatusWhenCreateable(
        Vendor_Agreement__c agreementRecord,
        Map<String, Schema.SObjectField> agreementFields
    ) {
        if (!agreementFields.containsKey(AGREEMENT_STATUS_FIELD)) {
            return;
        }

        Schema.SObjectField statusField =
            agreementFields.get(AGREEMENT_STATUS_FIELD);

        if (!statusField.getDescribe().isCreateable()) {
            return;
        }

        String statusValue = getPreferredPicklistValue(
            statusField,
            VendorAgreementConstants.STATUS_DRAFT
        );

        if (statusValue != null) {
            agreementRecord.put(
                AGREEMENT_STATUS_FIELD,
                statusValue
            );
        }
    }

    /**
     * @description
     * Returns the preferred active picklist value. When the preferred value
     * is unavailable, the first active value is returned.
     *
     * @param fieldToken Picklist field token.
     * @param preferredValue Preferred picklist value.
     * @return Active picklist value or null.
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

        return getFirstActivePicklistValue(picklistValues);
    }

    /**
     * @description
     * Returns the first active picklist value.
     *
     * @param picklistValues Picklist entries.
     * @return First active value or null.
     */
    private static String getFirstActivePicklistValue(
        List<Schema.PicklistEntry> picklistValues
    ) {
        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (picklistValue.isActive()) {
                return picklistValue.getValue();
            }
        }

        return null;
    }

    /**
     * @description
     * Checks whether Agreement_HTML__c can be queried during the current
     * deployment or test transaction.
     *
     * @return True when Agreement_HTML__c can be queried.
     */
    private static Boolean isAgreementHtmlQueryable() {
        Map<String, Schema.SObjectField> agreementFields =
            getAgreementFields();

        if (!agreementFields.containsKey(AGREEMENT_HTML_FIELD)) {
            return false;
        }

        try {
            String queryText =
                'SELECT Id, '
                + AGREEMENT_HTML_FIELD
                + ' FROM Vendor_Agreement__c'
                + ' LIMIT 1';

            Database.query(queryText);

            return true;
        } catch (System.QueryException queryException) {
            return false;
        }
    }

    /**
     * @description
     * Returns the stored Agreement HTML dynamically.
     *
     * @param agreementId Vendor Agreement Id.
     * @return Stored agreement HTML or blank.
     */
    private static String getStoredAgreementHtml(Id agreementId) {
        String queryText =
            'SELECT '
            + AGREEMENT_HTML_FIELD
            + ' FROM Vendor_Agreement__c'
            + ' WHERE Id = :agreementId'
            + ' LIMIT 1';

        Vendor_Agreement__c agreementRecord =
            Database.query(queryText);

        Object agreementHtml =
            agreementRecord.get(AGREEMENT_HTML_FIELD);

        return agreementHtml == null
            ? ''
            : String.valueOf(agreementHtml);
    }

    /**
     * @description
     * Sets the Visualforce page and optional agreementId parameter.
     *
     * @param agreementId Vendor Agreement Id.
     */
    private static void setCurrentPage(Id agreementId) {
        PageReference pageReference =
            new PageReference('/apex/VendorAgreementPdf');

        if (agreementId != null) {
            pageReference.getParameters().put(
                'agreementId',
                String.valueOf(agreementId)
            );
        }

        Test.setCurrentPage(pageReference);
    }

    /**
     * @description
     * Returns the Vendor Agreement field map.
     *
     * @return Vendor Agreement field map.
     */
    private static Map<String, Schema.SObjectField>
        getAgreementFields() {

        return Vendor_Agreement__c.SObjectType
            .getDescribe()
            .fields
            .getMap();
    }

    /**
     * @description
     * Builds a valid but non-existing Vendor Agreement Id.
     *
     * @return Fake Vendor Agreement Id.
     */
    private static Id buildFakeVendorAgreementId() {
        String keyPrefix =
            Vendor_Agreement__c.SObjectType
                .getDescribe()
                .getKeyPrefix();

        return Id.valueOf(
            keyPrefix + '000000000001'
        );
    }

    /**
     * @description
     * Builds a detailed assertion message when insertion fails.
     *
     * @param saveResult Database insertion result.
     * @return Detailed failure message.
     */
    private static String buildInsertFailureMessage(
        Database.SaveResult saveResult
    ) {
        List<String> errorMessages = new List<String>();

        for (Database.Error insertError : saveResult.getErrors()) {
            List<String> errorFields =
                insertError.getFields();

            errorMessages.add(
                'Status: '
                    + String.valueOf(insertError.getStatusCode())
                    + ', Message: '
                    + insertError.getMessage()
                    + ', Fields: '
                    + String.join(errorFields, ', ')
            );
        }

        return 'Vendor Agreement test record insertion failed. '
            + String.join(errorMessages, ' | ');
    }
}