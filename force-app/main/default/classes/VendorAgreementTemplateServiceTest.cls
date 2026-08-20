/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementTemplateServiceTest
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
 * Test class for VendorAgreementTemplateService.
 *
 * Covers:
 * - Agreement HTML generation
 * - Vendor detail population
 * - Opportunity/project detail population
 * - Vendor category rendering
 * - Vendor address rendering
 * - Blank value handling
 * - HTML escaping
 * - Agreement legal sections
 * - Signature section rendering
 */
@IsTest
@SuppressWarnings('PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts')
private class VendorAgreementTemplateServiceTest {

    private static final String VENDOR_NAME = 'ABC Interiors Vendor';
    private static final String VENDOR_EMAIL =
        'vendor.template.test@example.com';
    private static final String VENDOR_PHONE = '9876543210';
    private static final String VENDOR_CATEGORY = 'Electrical';
    private static final String VENDOR_ADDRESS =
        'Test Vendor Address, Hyderabad';
    private static final String OPPORTUNITY_NAME =
        'Arelia Premium Interior Project';

    @IsTest
    private static void buildAgreementHtmlShouldRenderCoreTemplate() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                VENDOR_NAME,
                VENDOR_EMAIL,
                VENDOR_PHONE,
                VENDOR_CATEGORY,
                VENDOR_ADDRESS,
                OPPORTUNITY_NAME
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        Assert.isNotNull(
            agreementHtml,
            'Agreement HTML should not be null.'
        );
        Assert.isTrue(
            agreementHtml.contains('ARELIA SPACE'),
            'Agreement should contain company name.'
        );
        Assert.isTrue(
            agreementHtml.contains('VENDOR AGREEMENT'),
            'Agreement should contain agreement title.'
        );
        Assert.isTrue(
            agreementHtml.contains(
                'Interior Design Vendor / Contractor Agreement'
            ),
            'Agreement should contain subtitle.'
        );
        Assert.isTrue(
            agreementHtml.contains('class="reference-table"'),
            'Agreement should contain reference table.'
        );
        Assert.isTrue(
            agreementHtml.contains('class="details-table"'),
            'Agreement should contain vendor details table.'
        );
    }

    @IsTest
    private static void buildAgreementHtmlShouldPopulateVendorData() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                VENDOR_NAME,
                VENDOR_EMAIL,
                VENDOR_PHONE,
                VENDOR_CATEGORY,
                VENDOR_ADDRESS,
                OPPORTUNITY_NAME
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        assertContains(
            agreementHtml,
            OPPORTUNITY_NAME,
            'Project name should be populated.'
        );
        assertContains(
            agreementHtml,
            VENDOR_NAME,
            'Vendor name should be populated.'
        );
        assertContains(
            agreementHtml,
            VENDOR_EMAIL,
            'Vendor email should be populated.'
        );
        assertContains(
            agreementHtml,
            VENDOR_PHONE,
            'Vendor contact number should be populated.'
        );
        assertContains(
            agreementHtml,
            VENDOR_CATEGORY,
            'Vendor category should be populated.'
        );
        assertContains(
            agreementHtml,
            VENDOR_ADDRESS,
            'Vendor address should be populated.'
        );
        assertContains(
            agreementHtml,
            String.valueOf(Date.today()),
            'Agreement date should be populated.'
        );
    }

    @IsTest
    private static void buildAgreementHtmlShouldRenderLegalSections() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                VENDOR_NAME,
                VENDOR_EMAIL,
                VENDOR_PHONE,
                VENDOR_CATEGORY,
                VENDOR_ADDRESS,
                OPPORTUNITY_NAME
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        assertContains(agreementHtml, '1. Parties', 'Parties section missing.');
        assertContains(
            agreementHtml,
            '2. Scope of Work',
            'Scope of Work section missing.'
        );
        assertContains(
            agreementHtml,
            '3. Vendor Responsibilities',
            'Vendor Responsibilities section missing.'
        );
        assertContains(
            agreementHtml,
            '7. Payment Terms',
            'Payment Terms section missing.'
        );
        assertContains(
            agreementHtml,
            '10. Confidentiality',
            'Confidentiality section missing.'
        );
        assertContains(
            agreementHtml,
            '12. Warranty and Defect Liability',
            'Warranty section missing.'
        );
        assertContains(
            agreementHtml,
            '18. General Terms',
            'General Terms section missing.'
        );
    }

    @IsTest
    private static void buildAgreementHtmlShouldRenderSignatureSection() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                VENDOR_NAME,
                VENDOR_EMAIL,
                VENDOR_PHONE,
                VENDOR_CATEGORY,
                VENDOR_ADDRESS,
                OPPORTUNITY_NAME
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        assertContains(
            agreementHtml,
            'For the Vendor',
            'Vendor signature section should be present.'
        );
        assertContains(
            agreementHtml,
            '<strong>Name:</strong> ' + VENDOR_NAME,
            'Vendor name should be present in signature section.'
        );
        assertContains(
            agreementHtml,
            '<strong>Vendor Category:</strong> ' + VENDOR_CATEGORY,
            'Vendor category should be present in signature section.'
        );

        Assert.isFalse(
            agreementHtml.contains('For Arelia Space'),
            'Arelia Space signature section should not be present.'
        );
        Assert.isFalse(
            agreementHtml.contains('Authorized Representative'),
            'Authorized Representative should not be present.'
        );
    }

    @IsTest
    private static void buildAgreementHtmlShouldEscapeUnsafeValues() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                'Vendor <Test> & Company',
                'vendor.escape@example.com',
                '9988776655',
                'Category <One>',
                'Address <Hyderabad> & Telangana',
                'Project <Alpha> & Beta'
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        assertContains(
            agreementHtml,
            'Vendor &lt;Test&gt; &amp; Company',
            'Vendor name should be HTML escaped.'
        );
        assertContains(
            agreementHtml,
            'Category &lt;One&gt;',
            'Vendor category should be HTML escaped.'
        );
        assertContains(
            agreementHtml,
            'Address &lt;Hyderabad&gt; &amp; Telangana',
            'Vendor address should be HTML escaped.'
        );
        assertContains(
            agreementHtml,
            'Project &lt;Alpha&gt; &amp; Beta',
            'Opportunity name should be HTML escaped.'
        );

        Assert.isFalse(
            agreementHtml.contains('Vendor <Test> & Company'),
            'Unescaped vendor name should not be present.'
        );
    }

    @IsTest
    private static void buildAgreementHtmlShouldHandleBlankValues() {
        Vendor_Opportunity__c vendorOpportunity =
            buildVendorOpportunity(
                '',
                '',
                '',
                '',
                '',
                ''
            );

        Test.startTest();

        String agreementHtml =
            VendorAgreementTemplateService.buildAgreementHtml(
                vendorOpportunity
            );

        Test.stopTest();

        Assert.isNotNull(
            agreementHtml,
            'Agreement HTML should be generated even for blank values.'
        );
        assertContains(
            agreementHtml,
            '<td>&nbsp;</td>',
            'Blank values should render as non-breaking space.'
        );
        assertContains(
            agreementHtml,
            'Vendor Details',
            'Vendor details section should still render.'
        );
        // assertContains(
        //     agreementHtml,
        //     'GST Number',
        //     'GST Number row should still render.'
        // );
    }

    private static Vendor_Opportunity__c buildVendorOpportunity(
        String vendorName,
        String vendorEmail,
        String vendorPhone,
        String vendorCategory,
        String vendorAddress,
        String opportunityName
    ) {
        Map<String, Object> vendorOpportunityData =
            new Map<String, Object>();

        vendorOpportunityData.put(
            'attributes',
            new Map<String, Object>{
                'type' => 'Vendor_Opportunity__c'
            }
        );
        vendorOpportunityData.put(
            'Vendor_Category__c',
            vendorCategory
        );
        vendorOpportunityData.put(
            'Vendor__r',
            buildVendorData(
                vendorName,
                vendorEmail,
                vendorPhone,
                vendorAddress
            )
        );
        vendorOpportunityData.put(
            'Opportunity__r',
            buildOpportunityData(opportunityName)
        );

        return (Vendor_Opportunity__c) JSON.deserialize(
            JSON.serialize(vendorOpportunityData),
            Vendor_Opportunity__c.class
        );
    }

    private static Map<String, Object> buildVendorData(
        String vendorName,
        String vendorEmail,
        String vendorPhone,
        String vendorAddress
    ) {
        return new Map<String, Object>{
            'attributes' => new Map<String, Object>{
                'type' => 'Vendor__c'
            },
            'Name' => vendorName,
            'Email__c' => vendorEmail,
            'Phone__c' => vendorPhone,
            'Address__c' => vendorAddress
        };
    }

    private static Map<String, Object> buildOpportunityData(
        String opportunityName
    ) {
        return new Map<String, Object>{
            'attributes' => new Map<String, Object>{
                'type' => 'Opportunity'
            },
            'Name' => opportunityName
        };
    }

    private static void assertContains(
        String actualValue,
        String expectedValue,
        String message
    ) {
        Assert.isTrue(
            actualValue.contains(expectedValue),
            message
        );
    }
}