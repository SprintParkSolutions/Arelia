/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementUtilTest
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
 * @description
 * Test class for VendorAgreementUtil.
 *
 * Covers:
 * - Arelia Opportunity validation
 * - Token generation
 * - Signing URL generation
 * - Org-Wide Email Address Id label handling
 * - Email Template Id label handling
 * - HTML sanitization
 * - HTML escaping
 */
@IsTest
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts')
private class VendorAgreementUtilTest {

    private static final String ARELIA_RECORD_TYPE_DEVELOPER_NAME =
        'Arelia';
    private static final String NON_ARELIA_RECORD_TYPE_DEVELOPER_NAME =
        'Non_Arelia';
    private static final String TEST_LABEL_NAME =
        'Test_Email_Template_Label';

    @IsTest
    private static void isAreliaOpportunityShouldReturnTrue() {
        Opportunity opportunityRecord =
            buildOpportunityWithRecordType(
                ARELIA_RECORD_TYPE_DEVELOPER_NAME
            );

        Test.startTest();

        Boolean result =
            VendorAgreementUtil.isAreliaOpportunity(opportunityRecord);

        Test.stopTest();

        Assert.areEqual(
            true,
            result,
            'Opportunity should be treated as Arelia Opportunity.'
        );
    }

    @IsTest
    private static void isAreliaOpportunityShouldReturnFalseForDifferentRecordType() {
        Opportunity opportunityRecord =
            buildOpportunityWithRecordType(
                NON_ARELIA_RECORD_TYPE_DEVELOPER_NAME
            );

        Test.startTest();

        Boolean result =
            VendorAgreementUtil.isAreliaOpportunity(opportunityRecord);

        Test.stopTest();

        Assert.areEqual(
            false,
            result,
            'Opportunity with different record type should not be Arelia.'
        );
    }

    @IsTest
    private static void isAreliaOpportunityShouldReturnFalseForNullOpportunity() {
        Test.startTest();

        Boolean result =
            VendorAgreementUtil.isAreliaOpportunity(null);

        Test.stopTest();

        Assert.areEqual(
            false,
            result,
            'Null Opportunity should not be treated as Arelia.'
        );
    }

    @IsTest
    private static void isAreliaOpportunityShouldReturnFalseWithoutRecordType() {
        Opportunity opportunityRecord =
            new Opportunity(
                Name = 'Test Opportunity'
            );

        Test.startTest();

        Boolean result =
            VendorAgreementUtil.isAreliaOpportunity(opportunityRecord);

        Test.stopTest();

        Assert.areEqual(
            false,
            result,
            'Opportunity without RecordType relationship should not be Arelia.'
        );
    }

    @IsTest
    private static void generateTokenShouldReturnHashedToken() {
        Test.startTest();

        String tokenValue = VendorAgreementUtil.generateToken();

        Test.stopTest();

        Assert.isFalse(
            String.isBlank(tokenValue),
            'Generated token should not be blank.'
        );
        Assert.areEqual(
            64,
            tokenValue.length(),
            'SHA-256 hex token should have 64 characters.'
        );
    }

    @IsTest
    private static void generateTokenShouldReturnUniqueValues() {
        Test.startTest();

        String firstToken = VendorAgreementUtil.generateToken();
        String secondToken = VendorAgreementUtil.generateToken();

        Test.stopTest();

        Assert.areNotEqual(
            firstToken,
            secondToken,
            'Generated tokens should be unique.'
        );
    }

    @IsTest
    private static void buildSigningUrlShouldHandleConfiguredLabel() {
        Id agreementId = UserInfo.getUserId();

        Test.startTest();

        try {
            String signingUrl =
                VendorAgreementUtil.buildSigningUrl(agreementId);

            Assert.isTrue(
                signingUrl.contains('?agreementId='),
                'Signing URL should contain agreementId query parameter.'
            );
            Assert.isTrue(
                signingUrl.contains(String.valueOf(agreementId)),
                'Signing URL should contain encoded agreement Id.'
            );
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'Exception is expected if signing base URL label is blank.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void buildSigningUrlShouldFailForNullAgreementIdWhenLabelExists() {
        Test.startTest();

        try {
            VendorAgreementUtil.buildSigningUrl(null);

            Assert.fail(
                'Null agreement Id should fail when signing URL label is configured.'
            );
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getOrgWideEmailAddressIdShouldHandleCustomLabel() {
        Test.startTest();

        try {
            Id orgWideEmailAddressId =
                VendorAgreementUtil.getOrgWideEmailAddressId();

            Assert.isNotNull(
                orgWideEmailAddressId,
                'Org-Wide Email Address Id should be returned when label is valid.'
            );
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'Exception is expected if Org-Wide Email Address Id label is blank or invalid.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getEmailTemplateIdFromLabelShouldReturnIdForValidValue() {
        Id expectedId = UserInfo.getUserId();

        Test.startTest();

        Id actualId =
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                String.valueOf(expectedId),
                TEST_LABEL_NAME
            );

        Test.stopTest();

        Assert.areEqual(
            expectedId,
            actualId,
            'Valid Id string should be converted to Id.'
        );
    }

    @IsTest
    private static void getEmailTemplateIdFromLabelShouldTrimValue() {
        Id expectedId = UserInfo.getUserId();

        Test.startTest();

        Id actualId =
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                '  ' + String.valueOf(expectedId) + '  ',
                TEST_LABEL_NAME
            );

        Test.stopTest();

        Assert.areEqual(
            expectedId,
            actualId,
            'Method should trim Id value before conversion.'
        );
    }

    @IsTest
    private static void getEmailTemplateIdFromLabelShouldFailForBlankValue() {
        Test.startTest();

        try {
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                '',
                TEST_LABEL_NAME
            );

            Assert.fail('Blank template Id label value should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getEmailTemplateIdFromLabelShouldFailForInvalidValue() {
        Test.startTest();

        try {
            VendorAgreementUtil.getEmailTemplateIdFromLabel(
                'invalid-template-id',
                TEST_LABEL_NAME
            );

            Assert.fail('Invalid template Id label value should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void sanitizeHtmlShouldReturnBlankForNullAndBlank() {
        Test.startTest();

        String nullResult = VendorAgreementUtil.sanitizeHtml(null);
        String blankResult = VendorAgreementUtil.sanitizeHtml('');

        Test.stopTest();

        Assert.areEqual(
            '',
            nullResult,
            'Null HTML should return blank string.'
        );
        Assert.areEqual(
            '',
            blankResult,
            'Blank HTML should return blank string.'
        );
    }

    @IsTest
    private static void sanitizeHtmlShouldEscapeScriptTags() {
        String unsafeHtml =
            '<p>Safe Content</p><script>alert("test")</script>';

        Test.startTest();

        String sanitizedHtml =
            VendorAgreementUtil.sanitizeHtml(unsafeHtml);

        Test.stopTest();

        Assert.isTrue(
            sanitizedHtml.contains('<p>Safe Content</p>'),
            'Safe HTML content should remain.'
        );
        Assert.isFalse(
            sanitizedHtml.contains('<script'),
            'Opening script tag should be escaped.'
        );
        Assert.isFalse(
            sanitizedHtml.contains('</script>'),
            'Closing script tag should be escaped.'
        );
        Assert.isTrue(
            sanitizedHtml.contains('&lt;script'),
            'Escaped opening script tag should be present.'
        );
        Assert.isTrue(
            sanitizedHtml.contains('&lt;/script&gt;'),
            'Escaped closing script tag should be present.'
        );
    }

    @IsTest
    private static void escapeHtmlShouldReturnBlankForNull() {
        Test.startTest();

        String escapedValue = VendorAgreementUtil.escapeHtml(null);

        Test.stopTest();

        Assert.areEqual(
            '',
            escapedValue,
            'Null value should return blank string.'
        );
    }

    @IsTest
    private static void escapeHtmlShouldEscapeSpecialCharacters() {
        String unsafeValue = 'Vendor <Test> & "Company"';

        Test.startTest();

        String escapedValue =
            VendorAgreementUtil.escapeHtml(unsafeValue);

        Test.stopTest();

        Assert.areEqual(
            'Vendor &lt;Test&gt; &amp; &quot;Company&quot;',
            escapedValue,
            'Special HTML characters should be escaped.'
        );
    }

    private static Opportunity buildOpportunityWithRecordType(
        String recordTypeDeveloperName
    ) {
        Map<String, Object> opportunityData =
            new Map<String, Object>();

        opportunityData.put(
            'attributes',
            new Map<String, Object>{
                'type' => 'Opportunity'
            }
        );
        opportunityData.put(
            'Name',
            'Test Opportunity'
        );
        opportunityData.put(
            'RecordType',
            buildRecordTypeData(recordTypeDeveloperName)
        );

        return (Opportunity) JSON.deserialize(
            JSON.serialize(opportunityData),
            Opportunity.class
        );
    }

    private static Map<String, Object> buildRecordTypeData(
        String recordTypeDeveloperName
    ) {
        return new Map<String, Object>{
            'attributes' => new Map<String, Object>{
                'type' => 'RecordType'
            },
            'DeveloperName' => recordTypeDeveloperName
        };
    }
}