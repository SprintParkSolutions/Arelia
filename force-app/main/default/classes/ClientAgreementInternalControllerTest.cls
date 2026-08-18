/**
 * @description Test class for ClientAgreementInternalController.
 * Covers agreement init data, supporting files, agreement/PDF creation,
 * validation failures, missing email failures, and Arelia Record Type validation.
 */
@IsTest
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc,PMD.TooManyMethods')
private class ClientAgreementInternalControllerTest {
    private static final String CLIENT_EMAIL = 'client@example.com';
    private static final String SUPERVISOR_ALIAS = 'supagr';
    private static final String TEMPLATE_FALLBACK_NAME =
        'Client_Agreement_Test_Template';

    private static final String ACCOUNT_NAME = 'Arelia Test Account';
    private static final String OPPORTUNITY_NAME = 'Arelia Test Opportunity';
    private static final String FILE_BODY = 'Test file content';

    @TestSetup
    static void setupData() {
        TestDataUtility.createSupervisorUser(SUPERVISOR_ALIAS);
        createConfiguredEmailTemplate();
    }

    @IsTest
    static void getAgreementInitDataShouldReturnPopulatedAgreementHtml() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);

        createPaymentTerm(
            opportunityRecord.Id,
            'Booking Advance',
            10
        );

        createPaymentTerm(
            opportunityRecord.Id,
            'Final Payment',
            90
        );

        createContentVersion(
            opportunityRecord.Id,
            'Floor Plan',
            'pdf'
        );

        Test.startTest();
        ClientAgreementDTO.InitResponse response =
            ClientAgreementInternalController.getAgreementInitData(
                opportunityRecord.Id
            );
        Test.stopTest();

        String expectedDuration = formatExpectedDuration(
            String.valueOf(
                opportunityRecord.ReVisit_Site_Estimated_Completion_Months__c
            )
        );

        System.assertEquals(
            opportunityRecord.Id,
            response.opportunityId,
            'Opportunity Id should match.'
        );
        System.assertEquals(
            opportunityRecord.Name,
            response.opportunityName,
            'Opportunity name should match.'
        );
        System.assertEquals(
            CLIENT_EMAIL,
            response.clientEmail,
            'Client email should match.'
        );
        System.assertNotEquals(
            null,
            response.supervisorEmail,
            'Supervisor email should be returned.'
        );
        System.assertNotEquals(
            null,
            response.agreementHtml,
            'Agreement HTML should be generated.'
        );
        System.assert(
            response.agreementHtml.contains('Client Interior Design'),
            'Agreement HTML should contain agreement title.'
        );
        System.assert(
            response.agreementHtml.contains('Client Name'),
            'Agreement HTML should contain client name label.'
        );
        System.assert(
            response.agreementHtml.contains('Test Client'),
            'Agreement HTML should contain client name.'
        );
        System.assert(
            response.agreementHtml.contains('Hyderabad Site'),
            'Agreement HTML should contain site location.'
        );
        System.assert(
            response.agreementHtml.contains('INR 250000.00'),
            'Agreement HTML should contain revisit budget.'
        );
        System.assert(
            response.agreementHtml.contains(expectedDuration),
            'Agreement HTML should contain expected project duration.'
        );
        System.assert(
            response.agreementHtml.contains('Booking Advance'),
            'Agreement HTML should contain payment term.'
        );
        System.assert(
            response.agreementHtml.contains('10%'),
            'Agreement HTML should contain payment percentage.'
        );
        System.assert(
            response.agreementHtml.contains('INR 25000.00'),
            'Agreement HTML should contain calculated payment amount.'
        );
        System.assertNotEquals(
            null,
            response.supportingFiles,
            'Supporting files should not be null.'
        );
        System.assertEquals(
            1,
            response.supportingFiles.size(),
            'One supporting file should be returned.'
        );
    }

    @IsTest
    static void getAgreementInitDataShouldUseFallbackBudgetAndDuration() {
        Opportunity opportunityRecord = createAreliaOpportunity(false, false);

        Test.startTest();
        ClientAgreementDTO.InitResponse response =
            ClientAgreementInternalController.getAgreementInitData(
                opportunityRecord.Id
            );
        Test.stopTest();

        String expectedDuration = formatExpectedDuration(
            String.valueOf(
                opportunityRecord.Project_Estimated_Completion_Months__c
            )
        );

        System.assert(
            response.agreementHtml.contains('INR 100000.00'),
            'Agreement HTML should contain fallback budget.'
        );
        System.assert(
            response.agreementHtml.contains(expectedDuration),
            'Agreement HTML should contain fallback duration.'
        );
        System.assert(
            response.agreementHtml.contains(
                'No payment terms have been defined'
            ),
            'Agreement HTML should show no payment terms message.'
        );
    }

    @IsTest
    static void getOpportunitySupportingFilesShouldReturnFiles() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);

        createContentVersion(
            opportunityRecord.Id,
            'Design Image',
            'png'
        );

        Test.startTest();
        List<ClientAgreementDTO.SupportingFileDTO> files =
            ClientAgreementInternalController.getOpportunitySupportingFiles(
                opportunityRecord.Id
            );
        Test.stopTest();

        System.assertEquals(
            1,
            files.size(),
            'One supporting file should be returned.'
        );
        System.assertEquals(
            'Design Image.png',
            files[0].fileName,
            'Supporting file name should match.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldCreateAgreementAndPdfFile() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);

        ContentVersion supportingVersion = createContentVersion(
            opportunityRecord.Id,
            'Supporting PDF',
            'pdf'
        );

        String pdfBase64 = EncodingUtil.base64Encode(
            Blob.valueOf('%PDF-1.4 Test Agreement PDF')
        );

        Id agreementId;
        Boolean emailExceptionThrown = false;

        Test.startTest();

        try {
            agreementId = ClientAgreementInternalController.sendAgreementToClient(
                opportunityRecord.Id,
                '<p>Agreement Body</p>',
                pdfBase64,
                new List<String>{
                    String.valueOf(supportingVersion.ContentDocumentId)
                }
            );
        } catch (AuraHandledException exceptionRecord) {
            emailExceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'Email-related AuraHandledException is acceptable after agreement creation.'
            );
        }

        Test.stopTest();

        Client_Agreement__c agreementRecord =
            getLatestAgreementForOpportunity(opportunityRecord.Id);

        if (agreementId != null) {
            System.assertEquals(
                agreementId,
                agreementRecord.Id,
                'Returned agreement Id should match latest agreement.'
            );
        }

        System.assertEquals(
            'Sent',
            agreementRecord.Status__c,
            'Agreement should be moved to Sent before email processing.'
        );
        System.assertEquals(
            '<p>Agreement Body</p>',
            agreementRecord.Agreement_HTML__c,
            'Agreement HTML should be saved.'
        );
        System.assertEquals(
            opportunityRecord.Id,
            agreementRecord.Opportunity__c,
            'Agreement should be linked to Opportunity.'
        );
        System.assertNotEquals(
            null,
            agreementRecord.PDF_File_Id__c,
            'PDF File Id should be populated before email processing.'
        );
        System.assert(
            emailExceptionThrown || agreementId != null,
            'Send flow should either complete or fail only after creating agreement and PDF.'
        );
    }

    @IsTest
    static void getAgreementInitDataShouldThrowWhenOpportunityIdIsNull() {
        Boolean exceptionThrown = initShouldThrow(null);

        System.assertEquals(
            true,
            exceptionThrown,
            'Null Opportunity Id should throw exception.'
        );
    }

    @IsTest
    static void getOpportunitySupportingFilesShouldThrowWhenOpportunityIdIsNull() {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementInternalController.getOpportunitySupportingFiles(
                null
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Null Opportunity Id should throw exception.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldThrowWhenOpportunityIdIsNull() {
        Boolean exceptionThrown = sendShouldThrow(
            null,
            '<p>Body</p>',
            validPdfBase64()
        );

        System.assertEquals(
            true,
            exceptionThrown,
            'Null Opportunity Id should throw exception.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldThrowWhenAgreementHtmlIsBlank() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);

        Boolean exceptionThrown = sendShouldThrow(
            opportunityRecord.Id,
            '',
            validPdfBase64()
        );

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank agreement HTML should throw exception.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldThrowWhenPdfBase64IsBlank() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);

        Boolean exceptionThrown = sendShouldThrow(
            opportunityRecord.Id,
            '<p>Body</p>',
            ''
        );

        System.assertEquals(
            true,
            exceptionThrown,
            'Blank PDF Base64 should throw exception.'
        );
    }

    @IsTest
    static void getAgreementInitDataShouldThrowWhenClientEmailIsMissing() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);
        opportunityRecord.Email__c = null;
        update opportunityRecord;

        Boolean exceptionThrown = initShouldThrow(opportunityRecord.Id);

        System.assertEquals(
            true,
            exceptionThrown,
            'Missing client email should throw exception.'
        );
    }

    @IsTest
    static void getAgreementInitDataShouldThrowWhenSupervisorEmailIsMissing() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);
        opportunityRecord.Supervisor_User__c = null;
        update opportunityRecord;

        Boolean exceptionThrown = initShouldThrow(opportunityRecord.Id);

        System.assertEquals(
            true,
            exceptionThrown,
            'Missing supervisor email should throw exception.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldThrowWhenClientEmailIsMissing() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);
        opportunityRecord.Email__c = null;
        update opportunityRecord;

        Boolean exceptionThrown = sendShouldThrow(
            opportunityRecord.Id,
            '<p>Body</p>',
            validPdfBase64()
        );

        System.assertEquals(
            true,
            exceptionThrown,
            'Missing client email should throw exception.'
        );
    }

    @IsTest
    static void sendAgreementToClientShouldThrowWhenSupervisorEmailIsMissing() {
        Opportunity opportunityRecord = createAreliaOpportunity(true, true);
        opportunityRecord.Supervisor_User__c = null;
        update opportunityRecord;

        Boolean exceptionThrown = sendShouldThrow(
            opportunityRecord.Id,
            '<p>Body</p>',
            validPdfBase64()
        );

        System.assertEquals(
            true,
            exceptionThrown,
            'Missing supervisor email should throw exception.'
        );
    }

    private static Boolean initShouldThrow(Id opportunityId) {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementInternalController.getAgreementInitData(
                opportunityId
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        return exceptionThrown;
    }

    private static Boolean sendShouldThrow(
        Id opportunityId,
        String agreementHtml,
        String pdfBase64
    ) {
        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            ClientAgreementInternalController.sendAgreementToClient(
                opportunityId,
                agreementHtml,
                pdfBase64,
                new List<String>()
            );
        } catch (AuraHandledException exceptionRecord) {
            exceptionThrown = true;
            System.assertNotEquals(
                null,
                exceptionRecord,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();

        return exceptionThrown;
    }

    private static Opportunity createAreliaOpportunity(
        Boolean useRevisitBudget,
        Boolean useRevisitDuration
    ) {
        Account accountRecord = TestDataUtility.createAccount(ACCOUNT_NAME);

        User supervisorUser = [
            SELECT Id
            FROM User
            WHERE Alias = :SUPERVISOR_ALIAS
            LIMIT 1
        ];

        Opportunity opportunityRecord = TestDataUtility.createOpportunity(
            OPPORTUNITY_NAME,
            supervisorUser.Id
        );

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.Email__c = CLIENT_EMAIL;
        opportunityRecord.Lead_Name__c = 'Test Client';
        opportunityRecord.Site_Location__c = 'Hyderabad Site';
        opportunityRecord.Supervisor_Estimated_Budget__c = 100000;
        opportunityRecord.Project_Estimated_Completion_Months__c =
            getFirstActivePicklistValue(
                Opportunity.Project_Estimated_Completion_Months__c
            );

        if (useRevisitBudget) {
            opportunityRecord.Re_Visit_Site_Supervisor_Estimate_Budget__c =
                250000;
        }

        if (useRevisitDuration) {
            opportunityRecord.ReVisit_Site_Estimated_Completion_Months__c =
                getFirstActivePicklistValue(
                    Opportunity.ReVisit_Site_Estimated_Completion_Months__c
                );
        }

        update opportunityRecord;

        System.assertEquals(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    private static Payment_Term__c createPaymentTerm(
        Id opportunityId,
        String name,
        Decimal percentage
    ) {
        Payment_Term__c termRecord = new Payment_Term__c();
        termRecord.Name = name;
        termRecord.Opportunity__c = opportunityId;
        termRecord.Percentage__c = percentage;
        termRecord.Due_Date__c = Date.today().addDays(7);

        insert termRecord;

        return termRecord;
    }

    private static ContentVersion createContentVersion(
        Id firstPublishLocationId,
        String title,
        String fileExtension
    ) {
        ContentVersion contentVersionRecord = new ContentVersion();
        contentVersionRecord.Title = title;
        contentVersionRecord.PathOnClient = title + '.' + fileExtension;
        contentVersionRecord.VersionData = Blob.valueOf(FILE_BODY);
        contentVersionRecord.FirstPublishLocationId = firstPublishLocationId;
        contentVersionRecord.IsMajorVersion = true;

        insert contentVersionRecord;

        return [
            SELECT Id,
                   ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionRecord.Id
            LIMIT 1
        ];
    }

    private static Client_Agreement__c getLatestAgreementForOpportunity(
        Id opportunityId
    ) {
        return [
            SELECT Id,
                   Status__c,
                   Agreement_HTML__c,
                   PDF_File_Id__c,
                   Opportunity__c
            FROM Client_Agreement__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static String getFirstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        List<Schema.PicklistEntry> entries =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        System.assert(
            false,
            'No active picklist value found for '
                + fieldToken.getDescribe().getName()
        );

        return null;
    }

    private static String formatExpectedDuration(String durationValue) {
        if (String.isBlank(durationValue)) {
            return '';
        }

        String value = durationValue.trim();

        if (value.toLowerCase().contains('month')) {
            return value;
        }

        if (value == '1') {
            return value + ' Month';
        }

        return value + ' Months';
    }

    private static String validPdfBase64() {
        return EncodingUtil.base64Encode(
            Blob.valueOf('%PDF-1.4 Test PDF Content')
        );
    }

    private static void createConfiguredEmailTemplate() {
        String configuredDeveloperName = System.Label.Agreement_Email_Template;

        if (String.isBlank(configuredDeveloperName)) {
            configuredDeveloperName = TEMPLATE_FALLBACK_NAME;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestDataUtility.createSpecificEmailTemplate(
                configuredDeveloperName,
                configuredDeveloperName,
                'Agreement {{OPPORTUNITY_NAME}}',
                '<html><body>{{SIGNING_URL}}</body></html>'
            );
        }
    }
}